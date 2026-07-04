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

/// Always-visible bar showing the current drive and media.
struct DeviceStatusBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: app.deviceMonitor.currentMedia == nil ? "opticaldiscdrive" : "opticaldiscdrive.fill")
                .foregroundStyle(.secondary)
            if let device = app.deviceMonitor.currentDevice {
                Text(device.displayName)
                if let media = device.media {
                    Text("·")
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
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
