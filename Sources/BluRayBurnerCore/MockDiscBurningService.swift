import Foundation

/// Scriptable in-memory service for tests and UI previews (KTD1/KTD6).
/// Script the outcome and progress of the next operation, then assert on
/// the recorded calls.
public final class MockDiscBurningService: DiscBurningService, @unchecked Sendable {

    public enum ScriptedOutcome: Sendable {
        case success
        case failure(DiscOperationError)
    }

    // MARK: - Script (set by tests)

    private let lock = NSLock()
    private var _devices: [OpticalDevice] = []
    private var _burnOutcome: ScriptedOutcome = .success
    private var _eraseOutcome: ScriptedOutcome = .success
    /// Progress ticks emitted before the outcome resolves.
    private var _progressScript: [BurnProgress] = []
    private var eventContinuations: [UUID: AsyncStream<DeviceEvent>.Continuation] = [:]

    // MARK: - Recorded calls (asserted by tests)

    public struct RecordedBurn: Sendable {
        public let layout: LayoutNode
        public let device: OpticalDevice
        public let options: BurnOptions
    }

    public struct RecordedImageBurn: Sendable {
        public let url: URL
        public let device: OpticalDevice
        public let options: BurnOptions
    }

    public struct RecordedErase: Sendable {
        public let device: OpticalDevice
        public let mode: EraseMode
    }

    public private(set) var recordedBurns: [RecordedBurn] = []
    public private(set) var recordedImageBurns: [RecordedImageBurn] = []
    public private(set) var recordedErases: [RecordedErase] = []
    public private(set) var cancelRequested = false

    public init() {}

    // MARK: - Scripting API

    public func setDevices(_ devices: [OpticalDevice]) {
        lock.lock()
        _devices = devices
        let continuations = eventContinuations.values
        lock.unlock()
        for continuation in continuations {
            continuation.yield(.devicesChanged(devices))
        }
    }

    public func scriptBurn(outcome: ScriptedOutcome, progress: [BurnProgress] = []) {
        lock.lock(); defer { lock.unlock() }
        _burnOutcome = outcome
        _progressScript = progress
    }

    public func scriptErase(outcome: ScriptedOutcome, progress: [BurnProgress] = []) {
        lock.lock(); defer { lock.unlock() }
        _eraseOutcome = outcome
        _progressScript = progress
    }

    // MARK: - DiscBurningService

    public func devices() async -> [OpticalDevice] {
        lock.lock(); defer { lock.unlock() }
        return _devices
    }

    public func deviceEvents() -> AsyncStream<DeviceEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.lock()
            eventContinuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.eventContinuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    public func burn(
        layout: LayoutNode,
        on device: OpticalDevice,
        options: BurnOptions,
        progress: @escaping @Sendable (BurnProgress) -> Void
    ) async throws {
        lock.lock()
        recordedBurns.append(RecordedBurn(layout: layout, device: device, options: options))
        let script = _progressScript
        let outcome = _burnOutcome
        lock.unlock()
        try await resolve(outcome: outcome, progressScript: script, progress: progress)
    }

    public func burnImage(
        at url: URL,
        on device: OpticalDevice,
        options: BurnOptions,
        progress: @escaping @Sendable (BurnProgress) -> Void
    ) async throws {
        lock.lock()
        recordedImageBurns.append(RecordedImageBurn(url: url, device: device, options: options))
        let script = _progressScript
        let outcome = _burnOutcome
        lock.unlock()
        try await resolve(outcome: outcome, progressScript: script, progress: progress)
    }

    public func erase(
        device: OpticalDevice,
        mode: EraseMode,
        progress: @escaping @Sendable (BurnProgress) -> Void
    ) async throws {
        lock.lock()
        recordedErases.append(RecordedErase(device: device, mode: mode))
        let script = _progressScript
        let outcome = _eraseOutcome
        lock.unlock()
        try await resolve(outcome: outcome, progressScript: script, progress: progress)
    }

    public func cancelCurrentOperation() async {
        lock.lock(); defer { lock.unlock() }
        cancelRequested = true
        _burnOutcome = .failure(.cancelled)
    }

    // MARK: - Internals

    private func resolve(
        outcome: ScriptedOutcome,
        progressScript: [BurnProgress],
        progress: @escaping @Sendable (BurnProgress) -> Void
    ) async throws {
        for tick in progressScript {
            progress(tick)
            await Task.yield()
        }
        // Cancellation requested mid-operation wins over a scripted success.
        lock.lock()
        let cancelled = cancelRequested
        lock.unlock()
        if cancelled {
            throw DiscOperationError.cancelled
        }
        if case .failure(let error) = outcome {
            throw error
        }
    }
}
