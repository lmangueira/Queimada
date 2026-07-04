import SwiftUI
import BluRayBurnerCore

struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            // Back affordance for every screen past welcome (hidden mid-burn:
            // startOver() refuses while a burn/erase is running anyway).
            if app.screen != .welcome {
                HStack {
                    Button {
                        app.startOver()
                    } label: {
                        Label("Start Over", systemImage: "chevron.backward")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(!canGoBack)
                    Spacer()
                    Text(screenTitle).font(.headline).foregroundStyle(.secondary)
                    Spacer()
                    // Balance the leading button so the title stays centered.
                    Label("Start Over", systemImage: "chevron.backward").hidden()
                }
                .padding(.bottom, 8)
            }

            switch app.screen {
            case .welcome: WelcomeView()
            case .compile: CompileView()
            case .imageBurn: ImageBurnView()
            case .erase: EraseView()
            }
        }
        .padding()
        .overlay(alignment: .bottom) { DeviceStatusBar() }
        .animation(.default, value: app.screen)
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
        case .welcome: return ""
        case .compile: return "Data Disc"
        case .imageBurn: return "Write Disc Image"
        case .erase: return "Erase Disc"
        }
    }
}

/// Always-visible device status: a floating glass capsule (Liquid Glass
/// chrome layer — see docs/design/liquid-glass.md), never full-width chrome.
struct DeviceStatusBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: app.deviceMonitor.currentMedia == nil ? "opticaldiscdrive" : "opticaldiscdrive.fill")
                .foregroundStyle(.secondary)
            if let device = app.deviceMonitor.currentDevice {
                Text(device.displayName)
                if let media = device.media {
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(media.type.rawValue), \(ByteFormat.string(media.capacityBytes))")
                        .foregroundStyle(.secondary)
                    if !media.isWritable {
                        Text("(not writable)").foregroundStyle(.orange)
                    }
                } else {
                    Text("· no disc").foregroundStyle(.secondary)
                }
            } else {
                Text("No optical drive connected").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .adaptiveGlass(in: Capsule())
        .padding(.bottom, 8)
    }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
