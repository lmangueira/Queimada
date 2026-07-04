import SwiftUI
import BluRayBurnerCore

struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TabView {
            CompileView()
                .tabItem { Label("Burn Files", systemImage: "opticaldisc") }
            ImageBurnView()
                .tabItem { Label("Burn Image", systemImage: "doc.badge.gearshape") }
            EraseView()
                .tabItem { Label("Erase", systemImage: "eraser") }
        }
        .padding()
        .overlay(alignment: .bottom) { DeviceStatusBar() }
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
