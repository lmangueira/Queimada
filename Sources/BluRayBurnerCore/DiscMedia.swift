import Foundation

/// The kind of writable optical media in the drive.
/// BD-R DL carries no dedicated framework constant; it surfaces as `.bdR`
/// with a larger capacity (plan assumption, validated in the runbook).
public enum MediaType: String, Sendable, Equatable, CaseIterable {
    case cdR = "CD-R"
    case cdRW = "CD-RW"
    case dvdR = "DVD±R"
    case dvdRW = "DVD±RW"
    case bdR = "BD-R"
    case bdRE = "BD-RE"

    /// CD media additionally gets the ISO 9660/Joliet bridge (R6).
    public var isCD: Bool { self == .cdR || self == .cdRW }

    public var isRewritable: Bool { self == .cdRW || self == .dvdRW || self == .bdRE }
}

/// A snapshot of the media currently in a drive.
public struct DiscMedia: Sendable, Equatable {
    public var type: MediaType
    public var capacityBytes: Int64
    public var isBlank: Bool
    public var isAppendable: Bool
    public var isWritable: Bool

    public init(type: MediaType, capacityBytes: Int64, isBlank: Bool, isAppendable: Bool, isWritable: Bool) {
        self.type = type
        self.capacityBytes = capacityBytes
        self.isBlank = isBlank
        self.isAppendable = isAppendable
        self.isWritable = isWritable
    }
}

/// A connected optical burner.
public struct OpticalDevice: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var canWriteCD: Bool
    public var canWriteDVD: Bool
    public var canWriteBD: Bool
    /// Media currently inserted, if any.
    public var media: DiscMedia?

    public init(id: String, displayName: String, canWriteCD: Bool, canWriteDVD: Bool, canWriteBD: Bool, media: DiscMedia?) {
        self.id = id
        self.displayName = displayName
        self.canWriteCD = canWriteCD
        self.canWriteDVD = canWriteDVD
        self.canWriteBD = canWriteBD
        self.media = media
    }
}
