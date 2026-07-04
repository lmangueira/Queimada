// U1 — Sandbox burn spike (throwaway, not shipped).
//
// Purpose: prove or disprove that a SANDBOXED app can burn a data disc with
// DiscRecording from files the user granted via BOTH acquisition paths:
//   (a) Finder drag-and-drop  — the path the shipping app uses (R2/U5)
//   (b) NSOpenPanel (Powerbox)
// including a dropped FOLDER whose children the out-of-process burn engine
// must read recursively.
//
// GO for the Mac App Store requires path (a) to pass (plan: U1 verification).
//
// Run it (assembled + sandbox-signed via Packaging/scripts/make-app.sh spike),
// insert a blank disc, drop a folder, press "Burn Test Disc", and read the
// log pane. Findings go to Spike/README.md.

import AppKit
import DiscRecording

final class SpikeController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let logView = NSTextView()
    private let dropZone = DropZoneView()
    private var acquired: [(url: URL, via: String)] = []
    private var burn: DRBurn?
    private var pollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildUI()
        log("Sandbox spike started.")
        log("Sandboxed: \(isSandboxed() ? "YES" : "NO — sign with Spike.entitlements to test the real question!")")
        log("Devices: \(deviceSummary())")
        log("1) Drop files/folders below AND/OR use 'Add via Open Panel…'")
        log("2) Insert a blank disc, then press 'Burn Test Disc'.")
    }

    private func isSandboxed() -> Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private func deviceSummary() -> String {
        let devices = (DRDevice.devices() as? [DRDevice]) ?? []
        guard !devices.isEmpty else { return "none attached" }
        return devices.map { device in
            let info = device.info() as NSDictionary? ?? [:]
            return (info[DRDeviceProductNameKey] as? String) ?? "unknown"
        }.joined(separator: ", ")
    }

    // MARK: - Acquisition paths

    func addDropped(urls: [URL]) {
        for url in urls {
            acquired.append((url, "drag-and-drop"))
            log("[drop] acquired: \(url.path)")
            logChildren(of: url)
        }
    }

    @objc func addViaOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                acquired.append((url, "open-panel"))
                log("[panel] acquired: \(url.path)")
                logChildren(of: url)
            }
        }
    }

    private func logChildren(of url: URL) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            let children = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            log("    folder with \(children.count) children (recursive access will be tested by the burn)")
        }
    }

    // MARK: - The actual experiment

    @objc func burnTestDisc() {
        guard !acquired.isEmpty else { return log("Nothing acquired yet — drop files first.") }
        let devices = (DRDevice.devices() as? [DRDevice]) ?? []
        guard let device = devices.first else { return log("FAIL-SETUP: no optical device attached.") }

        // Direct read check first: can *our process* read the bytes?
        for (url, via) in acquired {
            let started = url.startAccessingSecurityScopedResource()
            let readable = FileManager.default.isReadableFile(atPath: url.path)
            log("[\(via)] security-scope started=\(started) readable-in-process=\(readable): \(url.lastPathComponent)")
        }

        guard let root = DRFolder(name: "SPIKE_TEST") else { return log("FAIL: DRFolder create") }
        for (url, _) in acquired {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let object: DRFSObject? = isDir.boolValue
                ? DRFolder(path: url.path)   // real-folder reference: engine walks children itself
                : DRFile(path: url.path)
            guard let fsObject = object else { return log("FAIL: DRFSObject for \(url.path)") }
            root.addChild(fsObject)
        }

        var mask = DRFilesystemInclusionMask(DRFilesystemInclusionMaskUDF)
        mask |= DRFilesystemInclusionMask(DRFilesystemInclusionMaskISO9660)
        root.setExplicitFilesystemMask(mask)

        guard let newBurn = DRBurn(device: device) else { return log("FAIL: DRBurn create (device rejected)") }
        var properties = newBurn.properties() as? [AnyHashable: Any] ?? [:]
        properties[DRBurnVerifyDiscKey] = true
        properties[DRBurnAppendableKey] = false
        newBurn.setProperties(properties)
        burn = newBurn

        log("Starting REAL burn — this writes the disc in the drive.")
        newBurn.writeLayout(root)

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollStatus()
        }
    }

    private func pollStatus() {
        guard let burn else { return }
        let status = burn.status() as NSDictionary? ?? [:]
        let state = status[DRStatusStateKey] as? String ?? "?"
        let percent = (status[DRStatusPercentCompleteKey] as? Double) ?? 0
        log("burn state=\(state) \(Int(percent * 100))%")

        if state == DRStatusStateDone {
            pollTimer?.invalidate()
            log("=== RESULT: GO — sandboxed burn + verify SUCCEEDED. Record entitlement set in Spike/README.md ===")
        } else if state == DRStatusStateFailed {
            pollTimer?.invalidate()
            let errorInfo = status[DRErrorStatusKey] as? NSDictionary
            let message = errorInfo?[DRErrorStatusErrorStringKey] as? String ?? "unknown error"
            log("=== RESULT: burn FAILED: \(message) ===")
            log("If the failure is a file-permission/read error on a dropped file → NO-GO signal for sandboxed MAS.")
            log("If it's a media/laser error → inconclusive, retry with fresh media.")
        }
    }

    // MARK: - UI scaffolding

    private func buildUI() {
        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 640, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Sandbox Burn Spike (U1)"
        window.delegate = self

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        dropZone.onDrop = { [weak self] urls in self?.addDropped(urls: urls) }
        dropZone.translatesAutoresizingMaskIntoConstraints = false
        dropZone.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let panelButton = NSButton(title: "Add via Open Panel…", target: self, action: #selector(addViaOpenPanel))
        let burnButton = NSButton(title: "Burn Test Disc", target: self, action: #selector(burnTestDisc))
        burnButton.bezelColor = .controlAccentColor

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let scroll = NSScrollView()
        scroll.documentView = logView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        content.addArrangedSubview(dropZone)
        content.addArrangedSubview(panelButton)
        content.addArrangedSubview(burnButton)
        content.addArrangedSubview(scroll)

        dropZone.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32).isActive = true
        scroll.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32).isActive = true

        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func log(_ line: String) {
        let stamped = "[\(ISO8601DateFormatter().string(from: Date()))] \(line)\n"
        logView.string += stamped
        logView.scrollToEndOfDocument(nil)
        // Mirror to a findings file next to the app for easy collection.
        let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("spike-findings.log")
        if let data = stamped.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

/// Drag-and-drop target registering for file URLs (acquisition path a).
final class DropZoneView: NSView {
    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.secondaryLabelColor.cgColor
        layer?.cornerRadius = 8
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let text = "Drop files / folders here (drag-and-drop acquisition path)"
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 13),
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

let app = NSApplication.shared
let controller = SpikeController()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
