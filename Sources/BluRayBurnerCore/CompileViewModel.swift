import Foundation
import Observation

/// Why the burn button is disabled — always surfaced with a reason (U5).
public enum BurnGate: Sendable, Equatable {
    case ready
    case emptyCompilation
    case noWritableMedia
    case overCapacity(overBy: Int64)
}

/// Folders-only projection of the compilation tree for the sidebar
/// (the "how the disc will look" overview). IDs match the compilation items.
public struct FolderNode: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    /// nil when the folder has no subfolders (no disclosure triangle).
    public var children: [FolderNode]?

    public init(id: UUID, name: String, children: [FolderNode]?) {
        self.id = id
        self.name = name
        self.children = children
    }
}

/// One visible row of the flattened sidebar tree (depth-first order). Only
/// rows whose ancestors are all expanded appear.
public struct FolderRow: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var depth: Int
    /// True when this folder contains subfolders (shows a disclosure triangle).
    public var hasChildren: Bool
    /// Triangle state; only meaningful when `hasChildren`.
    public var isExpanded: Bool

    public init(id: UUID, name: String, depth: Int, hasChildren: Bool, isExpanded: Bool) {
        self.id = id
        self.name = name
        self.depth = depth
        self.hasChildren = hasChildren
        self.isExpanded = isExpanded
    }
}

/// Drives the main compile screen: drop, remove, capacity, options (U5).
@MainActor
@Observable
public final class CompileViewModel {
    /// Sidebar selection sentinel for the disc root.
    public static let rootID = UUID()

    public private(set) var compilation = Compilation()
    public var verifyAfterBurn = true  // default on: archival users (plan assumption)

    /// Currently selected virtual folder (sidebar). Root by default; falls
    /// back to root automatically if the selected folder is pruned.
    public var selectedFolderID: UUID = CompileViewModel.rootID

    /// Folders the user has collapsed in the sidebar. Tracking the collapsed
    /// set (rather than the expanded set) keeps everything expanded by default,
    /// including folders added later.
    public var collapsedFolderIDs: Set<UUID> = []

    private let deviceMonitor: DeviceMonitor

    public init(deviceMonitor: DeviceMonitor) {
        self.deviceMonitor = deviceMonitor
    }

    // MARK: - Split-view projections

    /// Resolved selection: the sentinel root, or a folder that still exists.
    public var effectiveSelection: UUID {
        if selectedFolderID == Self.rootID { return Self.rootID }
        return compilation.item(withID: selectedFolderID)?.children != nil
            ? selectedFolderID
            : Self.rootID
    }

    /// Sidebar tree: folders only, disc root excluded (rendered separately).
    public var folderTree: [FolderNode] {
        Self.folderNodes(from: compilation.items)
    }

    /// Sidebar rows: the folder tree flattened depth-first, honoring collapse
    /// state (descendants of a collapsed folder are omitted). Flat so the view
    /// can render it lazily — a nested tree defeats LazyVStack, because each
    /// root's entire subtree materializes as a single lazy element.
    public var folderRows: [FolderRow] {
        var rows: [FolderRow] = []
        func walk(_ nodes: [FolderNode], depth: Int) {
            for node in nodes {
                let hasChildren = node.children != nil
                let expanded = hasChildren && !collapsedFolderIDs.contains(node.id)
                rows.append(FolderRow(id: node.id, name: node.name, depth: depth,
                                      hasChildren: hasChildren, isExpanded: expanded))
                if expanded, let children = node.children {
                    walk(children, depth: depth + 1)
                }
            }
        }
        walk(folderTree, depth: 0)
        return rows
    }

    /// Toggle a folder's sidebar expansion (the disclosure chevron).
    public func toggleExpansion(_ id: UUID) {
        if collapsedFolderIDs.contains(id) {
            collapsedFolderIDs.remove(id)
        } else {
            collapsedFolderIDs.insert(id)
        }
    }

    /// Expand a folder — used when selecting it, so clicking a folder always
    /// reveals its subfolders (collapse is done explicitly via the chevron).
    public func expand(_ id: UUID) {
        collapsedFolderIDs.remove(id)
    }

    /// Collapse a folder (hide its subfolders in the sidebar).
    public func collapse(_ id: UUID) {
        collapsedFolderIDs.insert(id)
    }

    // MARK: - Keyboard navigation (sidebar tree)

    /// Disc root + visible folder rows, in display order, for arrow-key nav.
    /// Root is depth 0 and always "expanded"; folders sit at depth + 1.
    private var navigableRows: [(id: UUID, depth: Int, hasChildren: Bool, expanded: Bool)] {
        var rows: [(id: UUID, depth: Int, hasChildren: Bool, expanded: Bool)] = [
            (id: Self.rootID, depth: 0, hasChildren: !folderTree.isEmpty, expanded: true)
        ]
        for r in folderRows {
            rows.append((id: r.id, depth: r.depth + 1, hasChildren: r.hasChildren, expanded: r.isExpanded))
        }
        return rows
    }

    /// Down arrow: select the next visible row.
    public func selectNextRow() {
        let rows = navigableRows
        guard let i = rows.firstIndex(where: { $0.id == effectiveSelection }) else {
            selectedFolderID = rows.first?.id ?? Self.rootID
            return
        }
        if i + 1 < rows.count { selectedFolderID = rows[i + 1].id }
    }

    /// Up arrow: select the previous visible row.
    public func selectPreviousRow() {
        let rows = navigableRows
        guard let i = rows.firstIndex(where: { $0.id == effectiveSelection }) else {
            selectedFolderID = rows.first?.id ?? Self.rootID
            return
        }
        if i > 0 { selectedFolderID = rows[i - 1].id }
    }

    /// Right arrow: expand a collapsed folder, or descend into the first child
    /// of one that's already expanded.
    public func expandOrDescendRow() {
        let rows = navigableRows
        guard let i = rows.firstIndex(where: { $0.id == effectiveSelection }) else { return }
        let row = rows[i]
        if row.hasChildren && !row.expanded {
            expand(row.id)
        } else if row.hasChildren, i + 1 < rows.count {
            selectedFolderID = rows[i + 1].id
        }
    }

    /// Left arrow: collapse an expanded folder, or move up to its parent.
    public func collapseOrAscendRow() {
        let rows = navigableRows
        guard let i = rows.firstIndex(where: { $0.id == effectiveSelection }) else { return }
        let row = rows[i]
        if row.hasChildren && row.expanded && row.id != Self.rootID {
            collapse(row.id)
        } else if let parent = (0..<i).last(where: { rows[$0].depth < row.depth }) {
            selectedFolderID = rows[parent].id
        }
    }

    /// Contents of the selected folder for the right-hand pane.
    public var visibleItems: [CompilationItem] {
        if effectiveSelection == Self.rootID { return compilation.items }
        return compilation.item(withID: effectiveSelection)?.children ?? compilation.items
    }

    /// Title for the right-hand pane (volume name at root).
    public var selectedFolderName: String {
        if effectiveSelection == Self.rootID { return compilation.volumeName }
        return compilation.item(withID: effectiveSelection)?.name ?? compilation.volumeName
    }

    private static func folderNodes(from items: [CompilationItem]) -> [FolderNode] {
        items.compactMap { item in
            guard let children = item.children else { return nil }
            let subfolders = folderNodes(from: children)
            return FolderNode(id: item.id, name: item.name, children: subfolders.isEmpty ? nil : subfolders)
        }
    }

    public var media: DiscMedia? { deviceMonitor.currentMedia }

    public var capacityState: CapacityState {
        compilation.capacityState(for: media)
    }

    /// Single gating decision for the burn button (U5 test scenarios).
    public var burnGate: BurnGate {
        if compilation.isEmpty { return .emptyCompilation }
        guard let media, media.isWritable else { return .noWritableMedia }
        switch compilation.capacityState(for: media) {
        case .overCapacity(let overBy): return .overCapacity(overBy: overBy)
        case .noMedia: return .noWritableMedia
        case .underCapacity, .exact: return .ready
        }
    }

    public var canBurn: Bool { burnGate == .ready }

    /// Adds into the currently selected virtual folder (root when at root).
    public func add(_ item: CompilationItem) {
        let target = effectiveSelection
        compilation.add(item, into: target == Self.rootID ? nil : target)
    }

    public func remove(id: UUID) {
        compilation.remove(id: id)
        // If the selected folder (or an ancestor) was pruned, snap to root.
        if effectiveSelection != selectedFolderID {
            selectedFolderID = Self.rootID
        }
    }

    public func setVolumeName(_ name: String) {
        compilation.volumeName = name
    }

    /// Start over: empty compilation, selection back at the disc root.
    public func clear() {
        compilation = Compilation()
        selectedFolderID = Self.rootID
        collapsedFolderIDs = []
    }
}
