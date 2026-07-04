import Foundation

/// Filesystems that can appear on the disc (KTD2).
public enum DiscFilesystem: String, Sendable, Equatable, CaseIterable {
    case udf = "UDF"
    case iso9660 = "ISO 9660"
    case joliet = "Joliet"
}

/// Framework-neutral description of the on-disc tree (resolves the U4 open
/// question: the builder emits neutral descriptors asserted by CI tests;
/// `DiscRecordingService` translates them into DRFolder/DRFile — KTD1 holds).
public indirect enum LayoutNode: Sendable, Equatable {
    /// A virtual folder on disc containing children.
    case folder(name: String, children: [LayoutNode])
    /// A file on disc streaming from a real on-disk source at burn time (KTD3).
    case file(name: String, sourceURL: URL)

    public var name: String {
        switch self {
        case .folder(let name, _): return name
        case .file(let name, _): return name
        }
    }
}

/// The complete burnable layout: root tree + which filesystems to generate.
public struct DiscLayout: Sendable, Equatable {
    public var volumeName: String
    public var root: [LayoutNode]
    public var filesystems: Set<DiscFilesystem>

    public init(volumeName: String, root: [LayoutNode], filesystems: Set<DiscFilesystem>) {
        self.volumeName = volumeName
        self.root = root
        self.filesystems = filesystems
    }
}

/// Maps a `Compilation` to a `DiscLayout` (U4).
public enum FilesystemLayoutBuilder {

    /// Filesystem selection is a pure function of the media type (KTD2):
    /// UDF always; CD additionally gets the ISO 9660/Joliet bridge (R4, R6).
    public static func filesystems(for mediaType: MediaType) -> Set<DiscFilesystem> {
        mediaType.isCD ? [.udf, .iso9660, .joliet] : [.udf]
    }

    /// Builds the on-disc tree, mirroring the compilation's hierarchy and
    /// names exactly (R3).
    public static func makeLayout(from compilation: Compilation, mediaType: MediaType) -> DiscLayout {
        DiscLayout(
            volumeName: compilation.volumeName,
            root: compilation.items.map(node(from:)),
            filesystems: filesystems(for: mediaType)
        )
    }

    private static func node(from item: CompilationItem) -> LayoutNode {
        switch item.kind {
        case .file:
            return .file(name: item.name, sourceURL: item.sourceURL)
        case .folder(let children):
            return .folder(name: item.name, children: children.map(node(from:)))
        }
    }
}
