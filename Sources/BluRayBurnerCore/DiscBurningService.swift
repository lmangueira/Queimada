import Foundation

/// Options for a single burn (MVP burns finalized discs only — KTD5).
public struct BurnOptions: Sendable, Equatable {
    /// Read the disc back after writing and fail on mismatch (R9).
    public var verifyAfterBurn: Bool
    /// MVP: always true (KTD5). Kept in the options so the deferred
    /// multisession follow-up flips a flag rather than reshaping the API.
    public var finalize: Bool

    public init(verifyAfterBurn: Bool, finalize: Bool = true) {
        self.verifyAfterBurn = verifyAfterBurn
        self.finalize = finalize
    }
}

/// Progress phases surfaced during a burn (see HTD lifecycle diagram).
public enum BurnPhase: Sendable, Equatable {
    case preparing
    case writing
    case verifying
    case finishing
}

/// A progress tick from the engine.
public struct BurnProgress: Sendable, Equatable {
    public var phase: BurnPhase
    /// 0.0 ... 1.0 within the current phase.
    public var fractionComplete: Double

    public init(phase: BurnPhase, fractionComplete: Double) {
        self.phase = phase
        self.fractionComplete = fractionComplete
    }
}

/// Terminal result of a burn or erase.
public enum DiscOperationError: Error, Sendable, Equatable {
    /// The engine reported a write failure.
    case writeFailed(reason: String)
    /// Post-burn verification read back a mismatch (R9) — never a success.
    case verificationFailed(reason: String)
    /// The user cancelled mid-operation.
    case cancelled
    /// A referenced source file could not be read (e.g. access lost mid-burn).
    case sourceUnreadable(path: String)
    /// No writable media / device available at start.
    case mediaUnavailable(reason: String)
    /// Erase failed.
    case eraseFailed(reason: String)
}

public enum EraseMode: Sendable, Equatable {
    case quick
    case complete
}

/// Device lifecycle events for live UI updates.
public enum DeviceEvent: Sendable, Equatable {
    case devicesChanged([OpticalDevice])
}

/// The framework seam (KTD1). The app depends on this protocol only;
/// `DiscRecordingService` (app target) implements it over DiscRecording,
/// `MockDiscBurningService` backs the CI tests.
public protocol DiscBurningService: AnyObject, Sendable {
    /// Current devices with their media snapshots.
    func devices() async -> [OpticalDevice]

    /// Live device/media change events (media inserted/removed, device attached/detached).
    func deviceEvents() -> AsyncStream<DeviceEvent>

    /// Burn a compiled layout to the given device. Emits progress ticks;
    /// returns normally on success, throws `DiscOperationError` on failure.
    /// The service does NOT manage source-file access lifetime — the caller
    /// brackets access for the full burn (KTD3/KTD4, see `FileAccessManaging`).
    func burn(
        layout: LayoutNode,
        on device: OpticalDevice,
        options: BurnOptions,
        progress: @escaping @Sendable (BurnProgress) -> Void
    ) async throws

    /// Burn an existing disc image verbatim (R11).
    func burnImage(
        at url: URL,
        on device: OpticalDevice,
        options: BurnOptions,
        progress: @escaping @Sendable (BurnProgress) -> Void
    ) async throws

    /// Erase rewritable media (R10).
    func erase(
        device: OpticalDevice,
        mode: EraseMode,
        progress: @escaping @Sendable (BurnProgress) -> Void
    ) async throws

    /// Request cancellation of the in-flight operation (best effort).
    func cancelCurrentOperation() async
}
