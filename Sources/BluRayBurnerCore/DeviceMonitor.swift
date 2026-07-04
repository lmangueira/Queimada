import Foundation
import Observation

/// Live view of connected burners and inserted media (U3).
/// Binds the service's device event stream to observable UI state.
@MainActor
@Observable
public final class DeviceMonitor {
    public private(set) var devices: [OpticalDevice] = []

    /// The device the app targets: first with writable media, else first device.
    public var currentDevice: OpticalDevice? {
        devices.first(where: { $0.media?.isWritable == true }) ?? devices.first
    }

    /// Media in the current device, if any.
    public var currentMedia: DiscMedia? { currentDevice?.media }

    private let service: DiscBurningService
    private var monitorTask: Task<Void, Never>?

    public init(service: DiscBurningService) {
        self.service = service
    }

    /// Loads the current snapshot and follows live change events.
    public func start() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self, service] in
            let initial = await service.devices()
            await MainActor.run { [weak self] in self?.devices = initial }
            for await event in service.deviceEvents() {
                guard !Task.isCancelled else { return }
                switch event {
                case .devicesChanged(let updated):
                    await MainActor.run { [weak self] in self?.devices = updated }
                }
            }
        }
    }

    public func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }
}
