import Foundation
import Observation

/// Image selection/validation for verbatim disc-image burns (U8, R11/R12).
@MainActor
@Observable
public final class ImageBurnViewModel {
    public static let supportedExtensions: Set<String> = ["iso", "dmg", "img"]

    public enum ValidationResult: Sendable, Equatable {
        case ok
        case unsupportedType(ext: String)
        case tooLarge(overBy: Int64)
        case noMedia
        case unreadable
    }

    public private(set) var selectedImage: URL?
    public private(set) var imageSizeBytes: Int64?
    public var verifyAfterBurn = true

    private let deviceMonitor: DeviceMonitor
    private let fileSizer: @Sendable (URL) -> Int64?

    /// `fileSizer` is injectable so tests validate without real files.
    public init(
        deviceMonitor: DeviceMonitor,
        fileSizer: @escaping @Sendable (URL) -> Int64? = { url in
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
        }
    ) {
        self.deviceMonitor = deviceMonitor
        self.fileSizer = fileSizer
    }

    @discardableResult
    public func select(imageAt url: URL) -> ValidationResult {
        let ext = url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            selectedImage = nil
            imageSizeBytes = nil
            return .unsupportedType(ext: ext)
        }
        guard let size = fileSizer(url) else {
            selectedImage = nil
            imageSizeBytes = nil
            return .unreadable
        }
        selectedImage = url
        imageSizeBytes = size
        return validation
    }

    /// Capacity gate re-evaluated against current media (R12).
    public var validation: ValidationResult {
        guard let size = imageSizeBytes, selectedImage != nil else { return .unreadable }
        guard let media = deviceMonitor.currentMedia, media.isWritable else { return .noMedia }
        if size > media.capacityBytes {
            return .tooLarge(overBy: size - media.capacityBytes)
        }
        return .ok
    }

    public var canBurn: Bool { selectedImage != nil && validation == .ok }

    public func clear() {
        selectedImage = nil
        imageSizeBytes = nil
    }
}
