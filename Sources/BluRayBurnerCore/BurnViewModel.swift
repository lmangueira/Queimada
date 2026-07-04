import Foundation
import Observation

/// Burn lifecycle states (HTD state diagram).
public enum BurnState: Sendable, Equatable {
    case idle
    case burning(BurnProgress)
    case done
    case failed(DiscOperationError)

    public var isTerminal: Bool {
        switch self {
        case .done, .failed: return true
        case .idle, .burning: return false
        }
    }
}

/// Drives a burn through the service, holding file access for the whole
/// operation and mapping progress into observable state (U6).
@MainActor
@Observable
public final class BurnViewModel {
    public private(set) var state: BurnState = .idle
    /// Monotonic overall progress for the UI (never decreases within a burn).
    public private(set) var overallProgress: Double = 0
    public private(set) var currentPhase: BurnPhase?

    private let service: DiscBurningService
    private let fileAccess: FileAccessManaging
    private var burnTask: Task<Void, Never>?

    public init(service: DiscBurningService, fileAccess: FileAccessManaging) {
        self.service = service
        self.fileAccess = fileAccess
    }

    /// Starts a compilation burn. MVP: finalized discs only (KTD5).
    public func startBurn(
        compilation: Compilation,
        device: OpticalDevice,
        verifyAfterBurn: Bool
    ) {
        guard !state.isTerminal, case .idle = state else { return }
        guard let media = device.media else {
            state = .failed(.mediaUnavailable(reason: "No media in the drive."))
            return
        }
        let layoutRoot = FilesystemLayoutBuilder.makeLayout(from: compilation, mediaType: media.type)
        let layout = LayoutNode.folder(name: layoutRoot.volumeName, children: layoutRoot.root)
        let options = BurnOptions(verifyAfterBurn: verifyAfterBurn, finalize: true)
        let sources = compilation.allSourceURLs

        run(sources: sources) { [service] progressHandler in
            try await service.burn(layout: layout, on: device, options: options, progress: progressHandler)
        }
    }

    /// Starts a verbatim disc-image burn (R11).
    public func startImageBurn(imageURL: URL, device: OpticalDevice, verifyAfterBurn: Bool) {
        guard case .idle = state else { return }
        let options = BurnOptions(verifyAfterBurn: verifyAfterBurn, finalize: true)
        run(sources: [imageURL]) { [service] progressHandler in
            try await service.burnImage(at: imageURL, on: device, options: options, progress: progressHandler)
        }
    }

    /// Cancel the in-flight burn (Burning → Failed(cancelled)).
    public func cancel() {
        guard case .burning = state else { return }
        Task { [service] in await service.cancelCurrentOperation() }
    }

    /// Acknowledge a terminal state (Done/Failed → Idle).
    public func reset() {
        guard state.isTerminal else { return }
        state = .idle
        overallProgress = 0
        currentPhase = nil
    }

    // MARK: - Internals

    private func run(
        sources: [URL],
        _ operation: @escaping @Sendable (@escaping @Sendable (BurnProgress) -> Void) async throws -> Void
    ) {
        state = .burning(BurnProgress(phase: .preparing, fractionComplete: 0))
        overallProgress = 0
        currentPhase = .preparing

        // Hold access to every source for the entire burn (KTD3/KTD4):
        // acquired before the engine starts, released only on completion/failure.
        let token = fileAccess.beginAccess(to: sources)

        burnTask = Task { [weak self] in
            do {
                try await operation { progress in
                    Task { @MainActor [weak self] in
                        self?.apply(progress)
                    }
                }
                token.release()
                await MainActor.run { [weak self] in
                    self?.overallProgress = 1.0
                    self?.state = .done
                }
            } catch let error as DiscOperationError {
                token.release()
                await MainActor.run { [weak self] in self?.state = .failed(error) }
            } catch {
                token.release()
                await MainActor.run { [weak self] in
                    self?.state = .failed(.writeFailed(reason: error.localizedDescription))
                }
            }
        }
    }

    private func apply(_ progress: BurnProgress) {
        guard case .burning = state else { return }
        currentPhase = progress.phase
        // Map phases into a monotonic overall fraction:
        // preparing 0–5%, writing 5–80% (or 5–95% w/o verify), verifying 80–98%, finishing →100%.
        let mapped: Double
        switch progress.phase {
        case .preparing: mapped = 0.05 * progress.fractionComplete
        case .writing: mapped = 0.05 + 0.75 * progress.fractionComplete
        case .verifying: mapped = 0.80 + 0.18 * progress.fractionComplete
        case .finishing: mapped = 0.98 + 0.02 * progress.fractionComplete
        }
        overallProgress = max(overallProgress, min(mapped, 1.0))
        state = .burning(progress)
    }
}
