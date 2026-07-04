import Foundation
import Observation

/// Why the burn button is disabled — always surfaced with a reason (U5).
public enum BurnGate: Sendable, Equatable {
    case ready
    case emptyCompilation
    case noWritableMedia
    case overCapacity(overBy: Int64)
}

/// Drives the main compile screen: drop, remove, capacity, options (U5).
@MainActor
@Observable
public final class CompileViewModel {
    public private(set) var compilation = Compilation()
    public var verifyAfterBurn = true  // default on: archival users (plan assumption)

    private let deviceMonitor: DeviceMonitor

    public init(deviceMonitor: DeviceMonitor) {
        self.deviceMonitor = deviceMonitor
    }

    public var media: DiscMedia? { deviceMonitor.currentMedia }

    public var capacityState: CapacityState {
        compilation.capacityState(for: media)
    }

    /// Single gating decision for the burn button (U5 test scenarios).
    public var burnGate: BurnGate {
        if compilation.isEmpty { return .emptyCompilation }
        guard let media, media.isWritable else { return .noWritableMedia }
        switch compilation.capacityState(for: media) {
        case .overCapacity(let overBy): return .overCapacity(overBy: overBy)
        case .noMedia: return .noWritableMedia
        case .underCapacity, .exact: return .ready
        }
    }

    public var canBurn: Bool { burnGate == .ready }

    public func add(_ item: CompilationItem) {
        compilation.add(item)
    }

    public func remove(id: UUID) {
        compilation.remove(id: id)
    }

    public func setVolumeName(_ name: String) {
        compilation.volumeName = name
    }
}
