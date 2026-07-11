import SwiftUI
import BluRayBurnerCore

/// Dev-only screenshot harness: when BRB_SNAPSHOT_DIR is set, walks the main
/// screens with sample data, writes each as a PNG (rendered straight from the
/// window's content view — no Screen Recording permission needed), and quits.
/// Inert in normal runs.
@MainActor
enum SnapshotDriver {
    static func runIfRequested(app: AppModel) async {
        guard let dir = ProcessInfo.processInfo.environment["BRB_SNAPSHOT_DIR"] else { return }
        try? await Task.sleep(for: .seconds(1))
        capture("welcome", to: dir)

        let tmp = URL(fileURLWithPath: "/tmp")
        app.compileVM.add(CompilationItem(
            name: "files_tails", sourceURL: tmp,
            kind: .folder(children: [
                CompilationItem(name: "readme.txt", sourceURL: tmp, kind: .file(sizeBytes: 12_288)),
                CompilationItem(name: "boot.img", sourceURL: tmp, kind: .file(sizeBytes: 44_040)),
            ])
        ))
        app.compileVM.add(CompilationItem(name: "notes.md", sourceURL: tmp, kind: .file(sizeBytes: 30_720)))
        app.screen = .compile
        try? await Task.sleep(for: .seconds(1))
        capture("compile", to: dir)

        app.screen = .erase
        try? await Task.sleep(for: .seconds(1))
        capture("erase", to: dir)

        NSApp.terminate(nil)
    }

    private static func capture(_ name: String, to dir: String) {
        guard let view = NSApp.windows.first?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
