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
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

/// Top-level screens: a guided flow instead of tabs. The welcome screen is
/// the single entry point; drops route to the right workflow.
enum AppScreen: Equatable {
    case welcome
    case compile     // data disc: tree/split view
    case imageBurn   // verbatim disc-image burn with image info
    case erase
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

    /// Current screen in the guided flow.
    var screen: AppScreen = .welcome
    /// A single dropped disc image awaiting the write-vs-add decision.
    var pendingImageURL: URL?

    // MARK: - Flow navigation

    /// Route a welcome-screen drop (core-tested decision logic).
    func handleWelcomeDrop(urls: [URL]) {
        switch DropRouter.decide(urls: urls) {
        case .askImageOrData(let imageURL):
            pendingImageURL = imageURL
        case .dataItems(let urls):
            addDataItems(urls: urls)
            screen = .compile
        case nil:
            break
        }
    }

    /// Pending image → write its contents to disc.
    func chooseWriteImage() {
        guard let url = pendingImageURL else { return }
        pendingImageURL = nil
        imageVM.select(imageAt: url)
        screen = .imageBurn
    }

    /// Pending image → treat as a plain file on a data disc.
    func chooseAddImageAsFile() {
        guard let url = pendingImageURL else { return }
        pendingImageURL = nil
        addDataItems(urls: [url])
        screen = .compile
    }

    func addDataItems(urls: [URL]) {
        for url in urls {
            if let item = CompilationItemFactory.make(from: url) {
                compileVM.add(item)
            }
        }
    }

    /// Back to the welcome screen, discarding in-progress selections.
    /// Never navigates away mid-burn (the burn views own that state).
    func startOver() {
        guard case .idle = burnVM.state else { return }
        compileVM.clear()
        imageVM.clear()
        pendingImageURL = nil
        screen = .welcome
    }

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
