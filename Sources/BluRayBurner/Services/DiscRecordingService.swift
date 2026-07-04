import Foundation
import DiscRecording
import BluRayBurnerCore

/// Concrete `DiscBurningService` over Apple's DiscRecording framework
/// (KTD1: the only place framework types live). U3/U6/U7/U8.
final class DiscRecordingService: DiscBurningService, @unchecked Sendable {

    private let lock = NSLock()
    private var currentBurn: DRBurn?
    private var currentErase: DRErase?
    private var cancelled = false

    // MARK: - Devices (U3)

    func devices() async -> [OpticalDevice] {
        let drDevices = (DRDevice.devices() as? [DRDevice]) ?? []
        return drDevices.map(Self.map(device:))
    }

    /// Live updates via polling (2 s): robust across framework notification
    /// name drift; the UI only needs insertion/removal latency of seconds.
    func deviceEvents() -> AsyncStream<DeviceEvent> {
        AsyncStream { continuation in
            let task = Task {
                var last: [OpticalDevice] = []
                while !Task.isCancelled {
                    let now = await self.devices()
                    if now != last {
                        last = now
                        continuation.yield(.devicesChanged(now))
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func map(device: DRDevice) -> OpticalDevice {
        let info = device.info() as NSDictionary? ?? [:]
        let status = device.status() as NSDictionary? ?? [:]

        let vendor = info[DRDeviceVendorNameKey] as? String ?? ""
        let product = info[DRDeviceProductNameKey] as? String ?? "Optical Drive"
        let writeCaps = info[DRDeviceWriteCapabilitiesKey] as? NSDictionary ?? [:]

        let canCD = (writeCaps[DRDeviceCanWriteCDRKey] as? Bool) ?? false
        let canDVD = (writeCaps[DRDeviceCanWriteDVDRKey] as? Bool) ?? false
        let canBD = (writeCaps[DRDeviceCanWriteBDRKey] as? Bool) ?? false

        var media: DiscMedia?
        if let state = status[DRDeviceMediaStateKey] as? String,
           state == DRDeviceMediaStateMediaPresent,
           let mediaInfo = status[DRDeviceMediaInfoKey] as? NSDictionary {
            media = map(mediaInfo: mediaInfo)
        }

        return OpticalDevice(
            id: (info[DRDeviceFirmwareRevisionKey] as? String).map { "\(vendor)-\(product)-\($0)" } ?? "\(vendor)-\(product)",
            displayName: [vendor, product].filter { !$0.isEmpty }.joined(separator: " "),
            canWriteCD: canCD,
            canWriteDVD: canDVD,
            canWriteBD: canBD,
            media: media
        )
    }

    private static func map(mediaInfo: NSDictionary) -> DiscMedia? {
        guard let typeString = mediaInfo[DRDeviceMediaTypeKey] as? String else { return nil }

        let type: MediaType?
        switch typeString {
        case DRDeviceMediaTypeCDR: type = .cdR
        case DRDeviceMediaTypeCDRW: type = .cdRW
        case DRDeviceMediaTypeDVDR, DRDeviceMediaTypeDVDPlusR,
             DRDeviceMediaTypeDVDRDualLayer, DRDeviceMediaTypeDVDPlusRDoubleLayer:
            type = .dvdR
        case DRDeviceMediaTypeDVDRW, DRDeviceMediaTypeDVDPlusRW, DRDeviceMediaTypeDVDRAM:
            type = .dvdRW
        case DRDeviceMediaTypeBDR: type = .bdR   // BD-R DL: same constant, larger capacity
        case DRDeviceMediaTypeBDRE: type = .bdRE
        default: type = nil  // read-only media (CD-ROM/DVD-ROM/BD-ROM) or unknown
        }
        guard let mediaType = type else { return nil }

        let isBlank = (mediaInfo[DRDeviceMediaIsBlankKey] as? Bool) ?? false
        let isAppendable = (mediaInfo[DRDeviceMediaIsAppendableKey] as? Bool) ?? false
        let isOverwritable = (mediaInfo[DRDeviceMediaIsOverwritableKey] as? Bool) ?? false
        let blocksFree = (mediaInfo[DRDeviceMediaBlocksFreeKey] as? Int64) ?? 0
        let blockSize: Int64 = 2048  // data-disc block size

        // MVP burns finalized discs: writable = blank write-once media, or
        // overwritable rewritable media (KTD5).
        let isWritable = isBlank || isOverwritable

        return DiscMedia(
            type: mediaType,
            capacityBytes: blocksFree * blockSize,
            isBlank: isBlank,
            isAppendable: isAppendable,
            isWritable: isWritable
        )
    }

    private func drDevice(for device: OpticalDevice) -> DRDevice? {
        let all = (DRDevice.devices() as? [DRDevice]) ?? []
        return all.first { Self.map(device: $0).id == device.id } ?? all.first
    }

    // MARK: - Burn (U6)

    func burn(
        layout: LayoutNode,
        on device: OpticalDevice,
        options: BurnOptions,
        progress: @escaping @Sendable (BurnProgress) -> Void
    ) async throws {
        guard let drDevice = drDevice(for: device) else {
            throw DiscOperationError.mediaUnavailable(reason: "The selected drive is no longer connected.")
        }
        let mediaType = device.media?.type ?? .bdR

        // Translate neutral LayoutNode tree → DRFolder/DRFile (U4 boundary).
        guard case .folder(let volumeName, let children) = layout else {
            throw DiscOperationError.writeFailed(reason: "Invalid layout root.")
        }
        guard let root = DRFolder(name: volumeName) else {
            throw DiscOperationError.writeFailed(reason: "Could not create disc root folder.")
        }
        for child in children {
            guard let object = Self.makeFSObject(child) else {
                throw DiscOperationError.sourceUnreadable(path: child.name)
            }
            root.addChild(object)
        }

        // KTD2: explicit filesystem inclusion — UDF always; +ISO9660/Joliet on CD.
        var mask = DRFilesystemInclusionMask(DRFilesystemInclusionMaskUDF)
        if mediaType.isCD {
            mask |= DRFilesystemInclusionMask(DRFilesystemInclusionMaskISO9660)
            mask |= DRFilesystemInclusionMask(DRFilesystemInclusionMaskJoliet)
        }
        root.setExplicitFilesystemMask(mask)

        guard let burn = DRBurn(device: drDevice) else {
            throw DiscOperationError.mediaUnavailable(reason: "The drive rejected the burn session.")
        }
        var properties = burn.properties() as? [AnyHashable: Any] ?? [:]
        properties[DRBurnVerifyDiscKey] = options.verifyAfterBurn
        properties[DRBurnAppendableKey] = !options.finalize  // MVP: finalize → not appendable (KTD5)
        properties[DRBurnCompletionActionKey] = DRBurnCompletionActionEject
        burn.setProperties(properties)

        lock.lock()
        currentBurn = burn
        cancelled = false
        lock.unlock()

        burn.writeLayout(root)
        try await pollBurnStatus(burn, progress: progress)
    }

    private static func makeFSObject(_ node: LayoutNode) -> DRFSObject? {
        switch node {
        case .file(let name, let sourceURL):
            guard let file = DRFile(path: sourceURL.path) else { return nil }
            if file.baseName() != name { file.setBaseName(name) }
            return file
        case .folder(let name, let children):
            guard let folder = DRFolder(name: name) else { return nil }
            for child in children {
                guard let object = makeFSObject(child) else { return nil }
                folder.addChild(object)
            }
            return folder
        }
    }

    // MARK: - Image burn (U8)

    func burnImage(
        at url: URL,
        on device: OpticalDevice,
        options: BurnOptions,
        progress: @escaping @Sendable (BurnProgress) -> Void
    ) async throws {
        guard let drDevice = drDevice(for: device) else {
            throw DiscOperationError.mediaUnavailable(reason: "The selected drive is no longer connected.")
        }
        // Verbatim image layout via the framework's first-class API
        // (`+[DRBurn layoutForImageFile:]` — resolves the U8 deferred detail).
        guard let layout = DRBurn.layout(forImageFile: url.path) else {
            throw DiscOperationError.sourceUnreadable(path: url.path)
        }
        guard let burn = DRBurn(device: drDevice) else {
            throw DiscOperationError.mediaUnavailable(reason: "The drive rejected the burn session.")
        }
        var properties = burn.properties() as? [AnyHashable: Any] ?? [:]
        properties[DRBurnVerifyDiscKey] = options.verifyAfterBurn
        properties[DRBurnAppendableKey] = !options.finalize
        properties[DRBurnCompletionActionKey] = DRBurnCompletionActionEject
        burn.setProperties(properties)

        lock.lock()
        currentBurn = burn
        cancelled = false
        lock.unlock()

        burn.writeLayout(layout)
        try await pollBurnStatus(burn, progress: progress)
    }

    // MARK: - Erase (U7)

    func erase(
        device: OpticalDevice,
        mode: EraseMode,
        progress: @escaping @Sendable (BurnProgress) -> Void
    ) async throws {
        guard let drDevice = drDevice(for: device) else {
            throw DiscOperationError.mediaUnavailable(reason: "The selected drive is no longer connected.")
        }
        guard let erase = DRErase(device: drDevice) else {
            throw DiscOperationError.eraseFailed(reason: "The drive rejected the erase session.")
        }
        var properties = erase.properties() as? [AnyHashable: Any] ?? [:]
        properties[DREraseTypeKey] = (mode == .quick) ? DREraseTypeQuick : DREraseTypeComplete
        erase.setProperties(properties)

        lock.lock()
        currentErase = erase
        lock.unlock()

        erase.start()
        try await pollEraseStatus(erase, progress: progress)
    }

    // MARK: - Cancel

    func cancelCurrentOperation() async {
        lock.lock()
        cancelled = true
        let burn = currentBurn
        lock.unlock()
        burn?.abort()
    }

    // MARK: - Status polling

    private func pollBurnStatus(
        _ burn: DRBurn,
        progress: @escaping @Sendable (BurnProgress) -> Void
    ) async throws {
        while true {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let status = burn.status() as NSDictionary? ?? [:]
            let state = status[DRStatusStateKey] as? String ?? ""
            let percent = (status[DRStatusPercentCompleteKey] as? Double) ?? 0

            switch state {
            case DRStatusStatePreparing, DRStatusStateSessionOpen, DRStatusStateTrackOpen:
                progress(BurnProgress(phase: .preparing, fractionComplete: max(0, percent)))
            case DRStatusStateTrackWrite:
                progress(BurnProgress(phase: .writing, fractionComplete: max(0, percent)))
            case DRStatusStateVerifying:
                progress(BurnProgress(phase: .verifying, fractionComplete: max(0, percent)))
            case DRStatusStateTrackClose, DRStatusStateSessionClose, DRStatusStateFinishing:
                progress(BurnProgress(phase: .finishing, fractionComplete: max(0, percent)))
            case DRStatusStateDone:
                return
            case DRStatusStateFailed:
                lock.lock()
                let wasCancelled = cancelled
                lock.unlock()
                if wasCancelled { throw DiscOperationError.cancelled }
                throw DiscOperationError.writeFailed(reason: Self.errorReason(from: status))
            default:
                break
            }
        }
    }

    private func pollEraseStatus(
        _ erase: DRErase,
        progress: @escaping @Sendable (BurnProgress) -> Void
    ) async throws {
        while true {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let status = erase.status() as NSDictionary? ?? [:]
            let state = status[DRStatusStateKey] as? String ?? ""
            let percent = (status[DRStatusPercentCompleteKey] as? Double) ?? 0

            switch state {
            case DRStatusStateErasing:
                progress(BurnProgress(phase: .writing, fractionComplete: max(0, percent)))
            case DRStatusStateDone:
                return
            case DRStatusStateFailed:
                throw DiscOperationError.eraseFailed(reason: Self.errorReason(from: status))
            default:
                break
            }
        }
    }

    private static func errorReason(from status: NSDictionary) -> String {
        if let errorStatus = status[DRErrorStatusKey] as? NSDictionary,
           let message = errorStatus[DRErrorStatusErrorStringKey] as? String {
            return message
        }
        return "The burn engine reported a failure."
    }
}
