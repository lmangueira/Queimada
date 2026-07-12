import SwiftUI
import UniformTypeIdentifiers
import BluRayBurnerCore

/// Main screen: drag files in, watch capacity, burn (U5).
/// Chrome (titlebar/footer) is owned by ContentView; this view fills the
/// body edge-to-edge per the design (sidebar | panel, capacity strip below).
struct CompileView: View {
    @Environment(AppModel.self) private var app
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if case .idle = app.burnVM.state {
                compileArea
                Hairline()
                CapacityBar(state: app.compileVM.capacityState, totalBytes: app.compileVM.compilation.totalBytes)
                    .padding(.init(top: 10, leading: 20, bottom: 12, trailing: 20))
            } else {
                BurnProgressView()
            }
        }
    }

    private var compileArea: some View {
        Group {
            if app.compileVM.compilation.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(dropTargeted ? Theme.accent : Theme.textSecondary)
                    Text("Drag files or folders here")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Everything you drop is written exactly as-is — names, folders, and contents.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Disc overview: virtual folder tree (sidebar) + contents of
                // the selected folder (detail) — how the disc will look.
                DiscTreeSplitView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
        .overlay(
            Rectangle()
                .strokeBorder(Theme.accent, lineWidth: 2)
                .opacity(dropTargeted ? 1 : 0)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    /// Resolve dropped file URLs and add them (folders enumerated recursively
    /// off the main thread via AppModel.addDataItems, so large drops don't
    /// freeze the UI).
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    app.addDataItems(urls: [url])
                }
            }
        }
        return accepted
    }
}

/// Footer controls for the compile screen (rendered inside ContentView's
/// footer bar): verify checkbox + the Burn button.
struct CompileFooterControls: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var compileVM = app.compileVM

        if case .idle = app.burnVM.state {
            Toggle("Verify Disc", isOn: $compileVM.verifyAfterBurn)
                .toggleStyle(QueimadaCheckboxStyle())
                .help("Read the disc back after writing and compare against the source (recommended for archival).")

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
            .buttonStyle(GradientButtonStyle(
                gradient: Theme.burnGradient,
                shadow: Color(hex: 0x84221C).opacity(0.4)
            ))
            .keyboardShortcut(.defaultAction)
            .disabled(!app.compileVM.canBurn)
            .help(gateHelp)
        }
    }

    private var gateHelp: String {
        switch app.compileVM.burnGate {
        case .ready: return "Write the assembled files to disc."
        case .emptyCompilation: return "Add files first."
        case .noWritableMedia: return "Insert a writable disc."
        case .overCapacity(let overBy): return "Set exceeds disc capacity by \(ByteFormat.string(overBy)). Remove some files."
        }
    }
}

/// Split disc overview: virtual folders on the left, selected folder's
/// contents on the right. Drops land in the selected folder.
struct DiscTreeSplitView: View {
    @Environment(AppModel.self) private var app
    @FocusState private var sidebarFocused: Bool

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 170, idealWidth: 230, maxWidth: 320)
            detail
                .frame(minWidth: 260, maxWidth: .infinity)
        }
    }

    // Sidebar: the disc root + folders-only tree. The tree renders as a flat
    // depth-first list inside a LazyVStack so huge compilations only build
    // and lay out the visible rows (critical during screen transitions).
    // Focusable so arrow keys navigate the tree (up/down = move, right =
    // expand/descend, left = collapse/ascend); selection scrolls into view.
    private var sidebar: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    sidebarHeader
                    rootRow.id(CompileViewModel.rootID)
                    ForEach(app.compileVM.folderRows) { row in
                        folderRow(row).id(row.id)
                    }
                }
                .padding(.init(top: 12, leading: 10, bottom: 12, trailing: 10))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($sidebarFocused)
            .onMoveCommand { direction in
                switch direction {
                case .up: app.compileVM.selectPreviousRow()
                case .down: app.compileVM.selectNextRow()
                case .left: app.compileVM.collapseOrAscendRow()
                case .right: app.compileVM.expandOrDescendRow()
                default: break
                }
            }
            .onChange(of: app.compileVM.effectiveSelection) { _, id in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear { sidebarFocused = true }
        }
        .frame(maxHeight: .infinity)
        .background(Theme.windowBg)
    }

    private var sidebarHeader: some View {
        Text("SOURCE")
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Theme.textTertiary)
            .padding(.init(top: 4, leading: 8, bottom: 3, trailing: 8))
    }

    private var rootRow: some View {
        SidebarRow(
            icon: "opticaldisc",
            iconColor: Theme.accent,
            label: app.compileVM.compilation.volumeName,
            emphasized: true,
            selected: app.compileVM.effectiveSelection == CompileViewModel.rootID,
            indent: 0
        ) {
            app.compileVM.selectedFolderID = CompileViewModel.rootID
            sidebarFocused = true
        }
    }

    private func folderRow(_ row: FolderRow) -> some View {
        SidebarRow(
            icon: "folder.fill",
            iconColor: Theme.gold,
            label: row.name,
            emphasized: false,
            selected: app.compileVM.effectiveSelection == row.id,
            indent: row.depth + 1,
            expanded: row.hasChildren ? row.isExpanded : nil,
            onToggle: row.hasChildren ? {
                app.compileVM.toggleExpansion(row.id)
                sidebarFocused = true
            } : nil
        ) {
            // Selecting a folder also reveals its subfolders — clicking a folder
            // should always show what's inside it. Collapse is via the chevron.
            app.compileVM.selectedFolderID = row.id
            if row.hasChildren { app.compileVM.expand(row.id) }
            sidebarFocused = true
        }
    }

    // Detail: contents of the selected folder.
    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(app.compileVM.selectedFolderName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Drops land here")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.init(top: 14, leading: 20, bottom: 14, trailing: 20))
            Hairline()

            if app.compileVM.visibleItems.isEmpty {
                // Compact empty state — a folder pane, not a full-screen
                // placeholder.
                VStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Drop files here to add them to “\(app.compileVM.selectedFolderName)”.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
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
                    .padding(.init(top: 10, leading: 12, bottom: 10, trailing: 12))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.panelBg)
    }
}

/// One sidebar row: selection tint per the design (cyan wash + rounded 6).
/// Rows that represent a folder with subfolders carry a disclosure chevron
/// that toggles expansion independently of selecting the row.
private struct SidebarRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let emphasized: Bool
    let selected: Bool
    let indent: Int
    /// nil = no chevron (disc root or a folder without subfolders); the slot is
    /// still reserved so icons stay aligned. Otherwise the chevron reflects the
    /// expanded state and taps call `onToggle`.
    var expanded: Bool? = nil
    var onToggle: (() -> Void)? = nil
    let onSelect: () -> Void

    var body: some View {
        // Chevron and row content are sibling buttons — never nested — so a tap
        // on one never triggers the other (toggle vs. select stay distinct).
        HStack(spacing: 7) {
            disclosure
            Button(action: onSelect) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(iconColor)
                    Text(label)
                        .font(.system(size: 13, weight: emphasized ? .medium : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.leading, 8 + CGFloat(indent) * 12)
        .padding(.trailing, 8)
        .background(
            selected ? Theme.accent.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }

    @ViewBuilder
    private var disclosure: some View {
        if let expanded {
            Button {
                onToggle?()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: expanded)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 16, height: 16)
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
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(item.children != nil ? Theme.gold : Theme.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if let count = item.children?.count {
                    Text("\(count) item\(count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Text(ByteFormat.string(item.sizeBytes))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
            Button(role: .destructive, action: onRemove) {
                Circle()
                    .fill(Theme.clay)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(hex: 0xFFF2E8))
                    )
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Remove from the burn set — the file on your disk is not touched.")
        }
        .padding(.init(top: 8, leading: 10, bottom: 8, trailing: 10))
        .background(Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: max(geo.size.width * fillFraction, totalBytes > 0 ? 5 : 0))
                }
            }
            .frame(height: 6)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
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
        case .underCapacity, .noMedia: return Theme.accent
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
