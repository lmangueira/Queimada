import Foundation
import Observation

/// Erase lifecycle (U7): offered only for rewritable media.
public enum EraseState: Sendable, Equatable {
    case idle
    case erasing(BurnProgress)
    case done
    case failed(DiscOperationError)
}

@MainActor
@Observable
public final class EraseViewModel {
    public private(set) var state: EraseState = .idle

    private let service: DiscBurningService
    private let deviceMonitor: DeviceMonitor

    public init(service: DiscBurningService, deviceMonitor: DeviceMonitor) {
        self.service = service
        self.deviceMonitor = deviceMonitor
    }

    /// Erase is offered only when rewritable media is present (U7 gating).
    public var canErase: Bool {
        deviceMonitor.currentMedia?.type.isRewritable == true
    }

    public func erase(mode: EraseMode) {
        guard case .idle = state else { return }
        guard canErase, let device = deviceMonitor.currentDevice else {
            state = .failed(.mediaUnavailable(reason: "No rewritable media in the drive."))
            return
        }
        state = .erasing(BurnProgress(phase: .preparing, fractionComplete: 0))
        Task { [weak self, service] in
            do {
                try await service.erase(device: device, mode: mode) { progress in
                    Task { @MainActor [weak self] in
                        if case .erasing = self?.state { self?.state = .erasing(progress) }
                    }
                }
                await MainActor.run { [weak self] in self?.state = .done }
            } catch let error as DiscOperationError {
                await MainActor.run { [weak self] in self?.state = .failed(error) }
            } catch {
                await MainActor.run { [weak self] in
                    self?.state = .failed(.eraseFailed(reason: error.localizedDescription))
                }
            }
        }
    }

    public func reset() {
        if case .erasing = state { return }
        state = .idle
    }
}
