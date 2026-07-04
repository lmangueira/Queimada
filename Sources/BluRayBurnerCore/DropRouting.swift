import Foundation

/// Disc-image formats the app can write verbatim (R11).
public enum DiscImageFormats {
    public static let extensions: Set<String> = ["iso", "dmg", "img"]

    public static func isDiscImage(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

/// What to do with a fresh drop on the welcome screen.
public enum DropDecision: Equatable, Sendable {
    /// Exactly one disc image was dropped — ask the user: write its
    /// *contents* to disc, or add it as a plain file on a data disc?
    case askImageOrData(imageURL: URL)
    /// Regular files/folders (or several items, images included) — data disc.
    case dataItems([URL])
}

/// Routes a welcome-screen drop. Pure function — unit-tested in core.
public enum DropRouter {
    public static func decide(urls: [URL]) -> DropDecision? {
        guard !urls.isEmpty else { return nil }
        // Only a SINGLE dropped image triggers the question. Several images
        // (or an image mixed with other files) means the user is assembling
        // a data disc that *contains* images — e.g. archiving several ISOs
        // onto one Blu-ray.
        if urls.count == 1, DiscImageFormats.isDiscImage(urls[0]) {
            return .askImageOrData(imageURL: urls[0])
        }
        return .dataItems(urls)
    }
}
