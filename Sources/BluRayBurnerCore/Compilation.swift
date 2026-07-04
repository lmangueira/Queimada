import Foundation

/// One dragged-in file or folder, holding the URL the user granted access to.
public struct CompilationItem: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case file(sizeBytes: Int64)
        case folder(children: [CompilationItem])
    }

    public var id: UUID
    /// Name as it will appear on disc — preserved byte-for-byte (R3).
    public var name: String
    /// The real on-disk location the engine streams from at burn time (KTD3).
    public var sourceURL: URL
    public var kind: Kind

    public init(id: UUID = UUID(), name: String, sourceURL: URL, kind: Kind) {
        self.id = id
        self.name = name
        self.sourceURL = sourceURL
        self.kind = kind
    }

    public var sizeBytes: Int64 {
        switch kind {
        case .file(let size): return size
        case .folder(let children): return children.reduce(0) { $0 + $1.sizeBytes }
        }
    }
}

/// Capacity state of the assembled set vs. the target media (R12).
public enum CapacityState: Sendable, Equatable {
    case noMedia
    case underCapacity(freeBytes: Int64)
    case exact
    case overCapacity(overBy: Int64)

    /// The burn is allowed only when media is present and the set fits.
    public var allowsBurn: Bool {
        switch self {
        case .underCapacity, .exact: return true
        case .noMedia, .overCapacity: return false
        }
    }
}

/// The user-assembled set of items to burn.
public struct Compilation: Sendable, Equatable {
    public var volumeName: String
    public private(set) var items: [CompilationItem]

    public init(volumeName: String = "Data Disc", items: [CompilationItem] = []) {
        self.volumeName = volumeName
        self.items = items
    }

    public var isEmpty: Bool { items.isEmpty }

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    /// Adds an item at the top level. A duplicate top-level name is resolved
    /// deterministically by appending " 2", " 3", ... (first free suffix).
    public mutating func add(_ item: CompilationItem) {
        var item = item
        if items.contains(where: { $0.name == item.name }) {
            var counter = 2
            while items.contains(where: { $0.name == "\(item.name) \(counter)" }) {
                counter += 1
            }
            item.name = "\(item.name) \(counter)"
        }
        items.append(item)
    }

    public mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Pure capacity check (R12): total vs. the target media's capacity.
    public func capacityState(for media: DiscMedia?) -> CapacityState {
        guard let media else { return .noMedia }
        let free = media.capacityBytes - totalBytes
        if free > 0 { return .underCapacity(freeBytes: free) }
        if free == 0 { return .exact }
        return .overCapacity(overBy: -free)
    }

    /// Every real file URL referenced by the compilation — the set the app
    /// must hold access to for the entire burn (KTD3/KTD4).
    public var allSourceURLs: [URL] {
        func collect(_ item: CompilationItem) -> [URL] {
            switch item.kind {
            case .file: return [item.sourceURL]
            case .folder(let children): return [item.sourceURL] + children.flatMap(collect)
            }
        }
        return items.flatMap(collect)
    }
}
