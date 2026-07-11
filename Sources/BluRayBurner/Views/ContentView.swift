import SwiftUI
import BluRayBurnerCore

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            Hairline()

            ZStack {
                switch app.screen {
                case .welcome: WelcomeView().transition(hubTransition)
                case .compile: CompileView().transition(workflowTransition)
                case .imageBurn: ImageBurnView().transition(workflowTransition)
                case .erase: EraseView().transition(workflowTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if app.screen != .welcome {
                Hairline()
                footer
                    .transition(reduceMotion ? .opacity : Theme.Motion.footer)
            }
        }
        .background(Theme.windowBg)
        .animation(Theme.Motion.screen, value: app.screen)
        .task { await SnapshotDriver.runIfRequested(app: app) }
    }

    private var hubTransition: AnyTransition {
        reduceMotion ? .opacity : Theme.Motion.hubScreen
    }

    private var workflowTransition: AnyTransition {
        reduceMotion ? .opacity : Theme.Motion.workflowScreen
    }

    /// Custom titlebar (the system one is hidden): centered title with the
    /// app name as subtitle past the welcome screen. Draggable like a real
    /// titlebar; traffic lights overlay the leading edge.
    private var titlebar: some View {
        VStack(spacing: 1) {
            Text(screenTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if app.screen != .welcome {
                Text("Blu-Ray Burner")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Theme.chromeTint)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    /// Footer bar: Start Over on the left, drive status centered, and the
    /// screen's primary controls (e.g. Verify + Burn) on the right.
    private var footer: some View {
        HStack(spacing: 12) {
            HStack {
                Button {
                    app.startOver()
                } label: {
                    Label("Start Over", systemImage: "chevron.backward")
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0.4)
                Spacer()
            }
            .frame(maxWidth: .infinity)

            DriveStatusPill()

            HStack(spacing: 22) {
                Spacer()
                switch app.screen {
                case .compile: CompileFooterControls()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .background(Theme.chromeTint)
    }

    private var canGoBack: Bool {
        if case .idle = app.burnVM.state {
            if case .erasing = app.eraseVM.state { return false }
            return true
        }
        return false
    }

    private var screenTitle: String {
        switch app.screen {
        case .welcome: return "Blu-Ray Burner"
        case .compile: return "Data Disc"
        case .imageBurn: return "Write Disc Image"
        case .erase: return "Erase Disc"
        }
    }
}

/// Always-visible device status pill (design: Drive Pill component).
struct DriveStatusPill: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: app.deviceMonitor.currentMedia == nil ? "opticaldiscdrive" : "opticaldiscdrive.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.gold)
            if let device = app.deviceMonitor.currentDevice {
                Text(device.displayName)
                    .foregroundStyle(Theme.textPrimary)
                    .fontWeight(.medium)
                if let media = device.media {
                    Text("·").foregroundStyle(Theme.textTertiary)
                    Text("\(media.type.rawValue), \(ByteFormat.string(media.capacityBytes))")
                        .foregroundStyle(Theme.textSecondary)
                    if !media.isWritable {
                        Text("(not writable)").foregroundStyle(.orange)
                    }
                } else {
                    Text("· no disc").foregroundStyle(Theme.textSecondary)
                }
            } else {
                Text("No optical drive connected").foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .fixedSize()
    }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
