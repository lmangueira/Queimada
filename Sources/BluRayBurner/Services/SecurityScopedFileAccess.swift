import Foundation
import BluRayBurnerCore

/// Sandboxed builds: hold security-scoped resource access for the whole burn
/// (KTD3/KTD4). The engine reads source files on demand at burn time, so
/// access starts before the burn and releases only on completion/failure.
final class SecurityScopedFileAccess: FileAccessManaging, @unchecked Sendable {

    func beginAccess(to urls: [URL]) -> FileAccessToken {
        // start... returns false when the URL carries no security scope
        // (e.g. drag-and-drop grants inside the same sandbox); only URLs that
        // actually started are stopped on release.
        let started = urls.filter { $0.startAccessingSecurityScopedResource() }
        return Token(started: started)
    }

    private final class Token: FileAccessToken, @unchecked Sendable {
        private let lock = NSLock()
        private var started: [URL]?

        init(started: [URL]) {
            self.started = started
        }

        func release() {
            lock.lock()
            let urls = started
            started = nil
            lock.unlock()
            urls?.forEach { $0.stopAccessingSecurityScopedResource() }
        }
    }
}
