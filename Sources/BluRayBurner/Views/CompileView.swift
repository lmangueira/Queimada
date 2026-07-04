import SwiftUI
import UniformTypeIdentifiers
import BluRayBurnerCore

/// Main screen: drag files in, watch capacity, burn (U5).
struct CompileView: View {
    @Environment(AppModel.self) private var app
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var compileVM = app.compileVM

        VStack(spacing: 12) {
            if case .idle = app.burnVM.state {
                compileArea
                CapacityBar(state: app.compileVM.capacityState, totalBytes: app.compileVM.compilation.totalBytes)

                HStack {
                    Toggle("Verify after burn", isOn: $compileVM.verifyAfterBurn)
                        .help("Read the disc back after writing and compare against the source (recommended for archival).")
                    Spacer()
                    burnButton
                }
            } else {
                BurnProgressView()
            }
        }
    }

    private var compileArea: some View {
        Group {
            if app.compileVM.compilation.isEmpty {
                ContentUnavailableView(
                    "Drag files or folders here",
                    systemImage: "square.and.arrow.down.on.square",
                    description: Text("Everything you drop is written exactly as-is — names, folders, and contents.")
                )
            } else {
                // Disc overview: virtual folder tree (sidebar) + contents of
                // the selected folder (detail) — how the disc will look.
                DiscTreeSplitView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(
            dropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
            style: StrokeStyle(lineWidth: 2, dash: [6])
        ))
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    // (row rendering lives in CompilationRow below)

    private var burnButton: some View {
        Button {
            guard let device = app.deviceMonitor.currentDevice else { return }
            app.burnVM.startBurn(
                compilation: app.compileVM.compilation,
                device: device,
                verifyAfterBurn: app.compileVM.verifyAfterBurn
            )
        } label: {
            Label("Burn Disc", systemImage: "flame")
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!app.compileVM.canBurn)
        .help(gateHelp)
    }

    private var gateHelp: String {
        switch app.compileVM.burnGate {
        case .ready: return "Write the assembled files to disc."
        case .emptyCompilation: return "Add files first."
        case .noWritableMedia: return "Insert a writable disc."
        case .overCapacity(let overBy): return "Set exceeds disc capacity by \(ByteFormat.string(overBy)). Remove some files."
        }
    }

    /// Resolve dropped file URLs and add them (folders enumerated recursively).
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if let item = CompilationItemFactory.make(from: url) {
                        app.compileVM.add(item)
                    }
                }
            }
        }
        return accepted
    }
}

/// Split disc overview: virtual folders on the left, selected folder's
/// contents on the right. Drops land in the selected folder.
struct DiscTreeSplitView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        // List selection requires an optional binding; nil snaps to root.
        let selection = Binding<UUID?>(
            get: { app.compileVM.selectedFolderID },
            set: { app.compileVM.selectedFolderID = $0 ?? CompileViewModel.rootID }
        )

        HSplitView {
            // Sidebar: the disc root + folders-only tree.
            List(selection: selection) {
                Label {
                    Text(app.compileVM.compilation.volumeName)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "opticaldisc")
                }
                .tag(Optional(CompileViewModel.rootID))

                OutlineGroup(app.compileVM.folderTree, children: \.children) { node in
                    Label(node.name, systemImage: "folder")
                        .tag(Optional(node.id))
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 150, idealWidth: 190, maxWidth: 320)

            // Detail: contents of the selected folder.
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: app.compileVM.effectiveSelection == CompileViewModel.rootID
                          ? "opticaldisc" : "folder.fill")
                        .foregroundStyle(.secondary)
                    Text(app.compileVM.selectedFolderName).font(.headline)
                    Spacer()
                    Text("Drops land here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()

                if app.compileVM.visibleItems.isEmpty {
                    ContentUnavailableView(
                        "Empty folder",
                        systemImage: "folder",
                        description: Text("Drop files here to add them to “\(app.compileVM.selectedFolderName)”.")
                    )
                } else {
                    List {
                        ForEach(app.compileVM.visibleItems) { item in
                            CompilationRow(item: item) {
                                app.compileVM.remove(id: item.id)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Click a folder to drill into it.
                                if item.children != nil {
                                    app.compileVM.selectedFolderID = item.id
                                }
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 260, maxWidth: .infinity)
        }
    }
}

/// One row of the compilation tree: icon, name, size/child summary, and a
/// remove control that prunes the item from the burn set only — nothing is
/// deleted from disk.
struct CompilationRow: View {
    let item: CompilationItem
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(item.children != nil ? Color.accentColor : .secondary)
            Text(item.name)
            if let count = item.children?.count {
                Text("\(count) item\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(ByteFormat.string(item.sizeBytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Remove from the burn set — the file on your disk is not touched.")
        }
    }

    private var icon: String {
        if let children = item.children {
            return children.isEmpty ? "folder" : "folder.fill"
        }
        return "doc"
    }
}

/// Builds a CompilationItem from a dropped URL, enumerating folders.
enum CompilationItemFactory {
    static func make(from url: URL) -> CompilationItem? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }

        if isDirectory.boolValue {
            let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
            return CompilationItem(
                name: url.lastPathComponent,
                sourceURL: url,
                kind: .folder(children: children.compactMap(make(from:)))
            )
        } else {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            return CompilationItem(name: url.lastPathComponent, sourceURL: url, kind: .file(sizeBytes: size))
        }
    }
}

/// Used vs. total capacity with over-capacity styling (U5).
struct CapacityBar: View {
    let state: CapacityState
    let totalBytes: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * fillFraction)
                }
            }
            .frame(height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var fillFraction: CGFloat {
        switch state {
        case .noMedia: return 0
        case .overCapacity: return 1
        case .exact: return 1
        case .underCapacity(let free):
            let capacity = totalBytes + free
            return capacity > 0 ? CGFloat(totalBytes) / CGFloat(capacity) : 0
        }
    }

    private var barColor: Color {
        switch state {
        case .overCapacity: return .red
        case .exact: return .orange
        case .underCapacity, .noMedia: return .accentColor
        }
    }

    private var label: String {
        switch state {
        case .noMedia:
            return totalBytes == 0 ? "No disc inserted" : "\(ByteFormat.string(totalBytes)) assembled — no disc inserted"
        case .underCapacity(let free):
            return "\(ByteFormat.string(totalBytes)) used · \(ByteFormat.string(free)) free"
        case .exact:
            return "\(ByteFormat.string(totalBytes)) — exactly at capacity"
        case .overCapacity(let overBy):
            return "Over capacity by \(ByteFormat.string(overBy))"
        }
    }
}
