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
    }
}
