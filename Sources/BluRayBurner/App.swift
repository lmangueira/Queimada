import SwiftUI
import BluRayBurnerCore

@main
struct BluRayBurnerApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .frame(minWidth: 560, minHeight: 460)
        }
        .windowResizability(.contentSize)
    }
}

/// Composition root: picks the service implementation and owns shared models.
@MainActor
@Observable
final class AppModel {
    let service: DiscBurningService
    let deviceMonitor: DeviceMonitor
    let fileAccess: FileAccessManaging

    let compileVM: CompileViewModel
    let burnVM: BurnViewModel
    let eraseVM: EraseViewModel
    let imageVM: ImageBurnViewModel

    init() {
        // BRB_MOCK=1 runs the app against the mock (dev/smoke without hardware).
        let useMock = ProcessInfo.processInfo.environment["BRB_MOCK"] == "1"
        let service: DiscBurningService = useMock ? Self.makeDemoMock() : DiscRecordingService()
        self.service = service

        // Sandboxed builds bracket security-scoped access; the non-sandboxed
        // direct build uses plain paths (KTD4). Detection: sandbox container env.
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        let fileAccess: FileAccessManaging = sandboxed ? SecurityScopedFileAccess() : UnrestrictedFileAccess()
        self.fileAccess = fileAccess

        let monitor = DeviceMonitor(service: service)
        self.deviceMonitor = monitor
        self.compileVM = CompileViewModel(deviceMonitor: monitor)
        self.burnVM = BurnViewModel(service: service, fileAccess: fileAccess)
        self.eraseVM = EraseViewModel(service: service, deviceMonitor: monitor)
        self.imageVM = ImageBurnViewModel(deviceMonitor: monitor)
        monitor.start()
    }

    /// Demo mock with a blank BD-R inserted — used by BRB_MOCK smoke runs.
    private static func makeDemoMock() -> MockDiscBurningService {
        let mock = MockDiscBurningService()
        mock.setDevices([OpticalDevice(
            id: "demo", displayName: "Demo BD Writer (mock)",
            canWriteCD: true, canWriteDVD: true, canWriteBD: true,
            media: DiscMedia(type: .bdR, capacityBytes: 25_025_314_816, isBlank: true, isAppendable: false, isWritable: true)
        )])
        mock.scriptBurn(outcome: .success, progress: [
            BurnProgress(phase: .preparing, fractionComplete: 1),
            BurnProgress(phase: .writing, fractionComplete: 0.5),
            BurnProgress(phase: .writing, fractionComplete: 1),
            BurnProgress(phase: .verifying, fractionComplete: 1),
        ])
        return mock
    }
}
