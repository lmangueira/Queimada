import Testing
import Foundation
@testable import BluRayBurnerCore

/// Mock access manager asserting start/stop bracketing (U6, KTD3/KTD4).
final class SpyFileAccess: FileAccessManaging, @unchecked Sendable {
    final class SpyToken: FileAccessToken, @unchecked Sendable {
        let onRelease: () -> Void
        init(onRelease: @escaping () -> Void) { self.onRelease = onRelease }
        func release() { onRelease() }
    }

    private let lock = NSLock()
    private(set) var beginCount = 0
    private(set) var releaseCount = 0
    private(set) var lastURLs: [URL] = []

    func beginAccess(to urls: [URL]) -> FileAccessToken {
        lock.lock(); defer { lock.unlock() }
        beginCount += 1
        lastURLs = urls
        return SpyToken { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.releaseCount += 1
            self.lock.unlock()
        }
    }
}

/// U6: full burn state machine against the mock (R9, KTD5, cancel).
@MainActor
@Suite struct BurnViewModelTests {

    let service = MockDiscBurningService()
    let access = SpyFileAccess()
    let vm: BurnViewModel

    let device = makeDevice(media: makeMedia(.bdR, capacity: 25_000_000_000))

    var compilation: Compilation {
        var c = Compilation(volumeName: "TEST")
        c.add(makeFile("f.bin", size: 100))
        return c
    }

    init() {
        vm = BurnViewModel(service: service, fileAccess: access)
    }

    private func waitForTerminal(timeout: TimeInterval = 2) async throws {
        let reached = try await eventually(timeout: timeout) { vm.state.isTerminal }
        #expect(reached, "burn must reach a terminal state")
    }

    @Test func happyPathVerifyOff() async throws {
        service.scriptBurn(outcome: .success, progress: [
            BurnProgress(phase: .preparing, fractionComplete: 1),
            BurnProgress(phase: .writing, fractionComplete: 0.5),
            BurnProgress(phase: .writing, fractionComplete: 1),
        ])
        vm.startBurn(compilation: compilation, device: device, verifyAfterBurn: false)
        try await waitForTerminal()
        #expect(vm.state == .done)
        #expect(vm.overallProgress == 1.0)
        #expect(service.recordedBurns.count == 1)
        #expect(!service.recordedBurns[0].options.verifyAfterBurn)
        #expect(service.recordedBurns[0].options.finalize, "KTD5: MVP always finalizes")
    }

    @Test func happyPathVerifyOnPassesVerifyingPhase() async throws {
        service.scriptBurn(outcome: .success, progress: [
            BurnProgress(phase: .writing, fractionComplete: 1),
            BurnProgress(phase: .verifying, fractionComplete: 1),
        ])
        vm.startBurn(compilation: compilation, device: device, verifyAfterBurn: true)
        try await waitForTerminal()
        #expect(vm.state == .done)
        #expect(service.recordedBurns[0].options.verifyAfterBurn)
    }

    @Test func verifyMismatchIsFailureNeverSuccess() async throws {
        // Covers AE2 / R9.
        service.scriptBurn(
            outcome: .failure(.verificationFailed(reason: "sector mismatch at LBA 1234")),
            progress: [BurnProgress(phase: .verifying, fractionComplete: 0.7)]
        )
        vm.startBurn(compilation: compilation, device: device, verifyAfterBurn: true)
        try await waitForTerminal()
        #expect(vm.state == .failed(.verificationFailed(reason: "sector mismatch at LBA 1234")))
    }

    @Test func writeErrorMidBurnFails() async throws {
        service.scriptBurn(
            outcome: .failure(.writeFailed(reason: "engine error")),
            progress: [BurnProgress(phase: .writing, fractionComplete: 0.3)]
        )
        vm.startBurn(compilation: compilation, device: device, verifyAfterBurn: false)
        try await waitForTerminal()
        #expect(vm.state == .failed(.writeFailed(reason: "engine error")))
    }

    @Test func accessBracketingStartsBeforeBurnReleasesAfter() async throws {
        service.scriptBurn(outcome: .success)
        vm.startBurn(compilation: compilation, device: device, verifyAfterBurn: false)
        #expect(access.beginCount == 1, "access starts at burn start")
        #expect(access.lastURLs.map(\.path) == ["/src/f.bin"])
        try await waitForTerminal()
        let released = try await eventually { access.releaseCount == 1 }
        #expect(released, "released exactly once after completion")
    }

    @Test func accessReleasedOnFailureToo() async throws {
        service.scriptBurn(outcome: .failure(.writeFailed(reason: "x")))
        vm.startBurn(compilation: compilation, device: device, verifyAfterBurn: false)
        try await waitForTerminal()
        let released = try await eventually { access.releaseCount == 1 }
        #expect(released)
    }

    @Test func progressIsMonotonic() async throws {
        service.scriptBurn(outcome: .success, progress: [
            BurnProgress(phase: .writing, fractionComplete: 0.8),
            BurnProgress(phase: .writing, fractionComplete: 0.4),  // jitter
            BurnProgress(phase: .verifying, fractionComplete: 0.1),
        ])
        var observed: [Double] = []
        vm.startBurn(compilation: compilation, device: device, verifyAfterBurn: true)
        let deadline = Date().addingTimeInterval(2)
        while !vm.state.isTerminal, Date() < deadline {
            observed.append(vm.overallProgress)
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        observed.append(vm.overallProgress)
        #expect(observed == observed.sorted(), "progress never decreases")
        #expect(vm.state == .done)
    }

    @Test func cancelLeadsToFailedCancelled() async throws {
        // Burning → Failed(cancelled) transition (cancel affordance).
        service.scriptBurn(outcome: .success, progress: [
            BurnProgress(phase: .writing, fractionComplete: 0.1),
            BurnProgress(phase: .writing, fractionComplete: 0.2),
            BurnProgress(phase: .writing, fractionComplete: 0.3),
        ])
        vm.startBurn(compilation: compilation, device: device, verifyAfterBurn: false)
        vm.cancel()
        try await waitForTerminal()
        #expect(vm.state == .failed(.cancelled))
        let released = try await eventually { access.releaseCount == 1 }
        #expect(released, "access released after cancel")
    }

    @Test func noMediaFailsImmediately() {
        var noMediaDevice = device
        noMediaDevice.media = nil
        vm.startBurn(compilation: compilation, device: noMediaDevice, verifyAfterBurn: false)
        guard case .failed(.mediaUnavailable) = vm.state else {
            Issue.record("expected mediaUnavailable, got \(vm.state)")
            return
        }
    }

    @Test func resetReturnsToIdleFromTerminal() async throws {
        service.scriptBurn(outcome: .success)
        vm.startBurn(compilation: compilation, device: device, verifyAfterBurn: false)
        try await waitForTerminal()
        vm.reset()
        #expect(vm.state == .idle)
        #expect(vm.overallProgress == 0)
    }

    @Test func imageBurnRoutesToImageCall() async throws {
        service.scriptBurn(outcome: .success)
        let url = URL(fileURLWithPath: "/images/backup.iso")
        vm.startImageBurn(imageURL: url, device: device, verifyAfterBurn: true)
        try await waitForTerminal()
        #expect(vm.state == .done)
        #expect(service.recordedImageBurns.count == 1)
        #expect(service.recordedImageBurns[0].url == url)
        #expect(access.lastURLs == [url], "image file access held during burn")
    }
}
