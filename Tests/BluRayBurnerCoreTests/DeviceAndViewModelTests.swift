import Testing
import Foundation
@testable import BluRayBurnerCore

/// U3: media mapping and live updates through the monitor.
@MainActor
@Suite struct DeviceMonitorTests {

    let service = MockDiscBurningService()

    @Test func blankBDRMapsThrough() async throws {
        let media = makeMedia(.bdR, capacity: 25_000_000_000)
        service.setDevices([makeDevice(media: media)])

        let monitor = DeviceMonitor(service: service)
        monitor.start()
        defer { monitor.stop() }
        #expect(try await eventually { monitor.currentMedia != nil })

        #expect(monitor.currentMedia?.type == .bdR)
        #expect(monitor.currentMedia?.capacityBytes == 25_000_000_000)
        #expect(monitor.currentMedia?.isBlank == true)
    }

    @Test func mediaRemovalClearsToNoMedia() async throws {
        let media = makeMedia(.dvdR, capacity: 4_700_000_000)
        service.setDevices([makeDevice(media: media)])

        let monitor = DeviceMonitor(service: service)
        monitor.start()
        defer { monitor.stop() }
        #expect(try await eventually { monitor.currentMedia != nil })

        service.setDevices([makeDevice(media: nil)])  // eject
        #expect(try await eventually { monitor.currentMedia == nil })
        #expect(monitor.devices.count == 1, "device still attached, media gone")
    }

    @Test func readOnlyMediaSurfacesNotWritable() async throws {
        let media = makeMedia(.bdR, capacity: 25_000_000_000, blank: false, writable: false)
        service.setDevices([makeDevice(media: media)])

        let monitor = DeviceMonitor(service: service)
        monitor.start()
        defer { monitor.stop() }
        #expect(try await eventually { monitor.currentMedia != nil })
        #expect(monitor.currentMedia?.isWritable == false)
    }

    @Test func bdRDLSurfacesAsBDRWithLargerCapacity() async throws {
        // Plan assumption: BD-R DL = .bdR with ~50 GB capacity.
        let media = makeMedia(.bdR, capacity: 50_050_629_632)
        service.setDevices([makeDevice(media: media)])

        let monitor = DeviceMonitor(service: service)
        monitor.start()
        defer { monitor.stop() }
        #expect(try await eventually { monitor.currentMedia != nil })
        #expect(monitor.currentMedia?.type == .bdR)
        #expect(monitor.currentMedia!.capacityBytes > 25_000_000_000)
    }
}

/// U5: compile screen gating.
@MainActor
@Suite struct CompileViewModelTests {

    let service = MockDiscBurningService()
    let monitor: DeviceMonitor
    let vm: CompileViewModel

    init() {
        monitor = DeviceMonitor(service: service)
        monitor.start()
        vm = CompileViewModel(deviceMonitor: monitor)
    }

    private func setMedia(_ media: DiscMedia?) async throws {
        service.setDevices([makeDevice(media: media)])
        let propagated = try await eventually { monitor.currentMedia == media }
        #expect(propagated, "media change must propagate to the monitor")
    }

    @Test func emptyCompilationGates() {
        #expect(vm.burnGate == .emptyCompilation)
        #expect(!vm.canBurn)
        monitor.stop()
    }

    @Test func dropAddsAndRemoveUpdates() async throws {
        try await setMedia(makeMedia(.bdR, capacity: 1000))
        let a = makeFile("a.bin", size: 400)
        vm.add(a)
        vm.add(makeFile("b.bin", size: 300))
        #expect(vm.compilation.totalBytes == 700)
        #expect(vm.canBurn)

        vm.remove(id: a.id)
        #expect(vm.compilation.totalBytes == 300)
        #expect(vm.capacityState == .underCapacity(freeBytes: 700))
        monitor.stop()
    }

    @Test func overCapacityDisablesBurnWithOverage() async throws {
        try await setMedia(makeMedia(.cdR, capacity: 700))
        vm.add(makeFile("big.bin", size: 900))
        #expect(vm.burnGate == .overCapacity(overBy: 200))
        #expect(!vm.canBurn)
        monitor.stop()
    }

    @Test func noWritableMediaDisablesWithReason() async throws {
        vm.add(makeFile("a.bin", size: 10))
        #expect(vm.burnGate == .noWritableMedia)

        try await setMedia(makeMedia(.bdR, capacity: 1000, blank: false, writable: false))
        #expect(vm.burnGate == .noWritableMedia)
        #expect(!vm.canBurn)
        monitor.stop()
    }

    @Test func verifyToggleDefaultsOnAndFlows() {
        // Default on per plan assumption (archival users).
        #expect(vm.verifyAfterBurn)
        vm.verifyAfterBurn = false
        #expect(!vm.verifyAfterBurn)
        monitor.stop()
    }

    // MARK: Split-view selection (disc overview)

    @Test func dropsLandInSelectedFolder() {
        let folder = CompilationItem(
            name: "photos", sourceURL: URL(fileURLWithPath: "/p"), kind: .folder(children: [])
        )
        vm.add(folder)  // at root
        vm.selectedFolderID = folder.id
        vm.add(makeFile("img.jpg", size: 9))

        #expect(vm.compilation.item(withID: folder.id)?.children?.map(\.name) == ["img.jpg"])
        #expect(vm.visibleItems.map(\.name) == ["img.jpg"], "detail pane shows the folder's contents")
        #expect(vm.selectedFolderName == "photos")
        monitor.stop()
    }

    @Test func folderTreeProjectsFoldersOnly() {
        let sub = CompilationItem(
            name: "sub", sourceURL: URL(fileURLWithPath: "/f/sub"), kind: .folder(children: [])
        )
        let folder = CompilationItem(
            name: "f", sourceURL: URL(fileURLWithPath: "/f"),
            kind: .folder(children: [sub, makeFile("noise.txt", size: 1)])
        )
        vm.add(folder)
        vm.add(makeFile("root-noise.bin", size: 1))

        let tree = vm.folderTree
        #expect(tree.map(\.name) == ["f"], "files never appear in the sidebar")
        #expect(tree[0].children?.map(\.name) == ["sub"])
        #expect(tree[0].children?[0].children == nil, "leaf folder has no disclosure")
        monitor.stop()
    }

    @Test func removingSelectedFolderSnapsSelectionToRoot() {
        let folder = CompilationItem(
            name: "doomed", sourceURL: URL(fileURLWithPath: "/d"), kind: .folder(children: [])
        )
        vm.add(folder)
        vm.selectedFolderID = folder.id
        vm.remove(id: folder.id)

        #expect(vm.selectedFolderID == CompileViewModel.rootID)
        #expect(vm.effectiveSelection == CompileViewModel.rootID)
        #expect(vm.selectedFolderName == vm.compilation.volumeName)
        monitor.stop()
    }

    @Test func selectingFileIDResolvesToRoot() {
        // Only folders are selectable containers; a stale/file id resolves to root.
        let file = makeFile("f.bin", size: 1)
        vm.add(file)
        vm.selectedFolderID = file.id
        #expect(vm.effectiveSelection == CompileViewModel.rootID)
        #expect(vm.visibleItems.map(\.name) == ["f.bin"])
        monitor.stop()
    }

    @Test func addIntoTargetsSpecificFolderRegardlessOfSelection() {
        // Sidebar drops pin their destination at drop time.
        let folder = CompilationItem(
            name: "docs", sourceURL: URL(fileURLWithPath: "/docs"), kind: .folder(children: [])
        )
        vm.add(folder)
        vm.selectedFolderID = CompileViewModel.rootID  // selection stays at root

        vm.add(makeFile("inside.txt", size: 1), into: folder.id)
        vm.add(makeFile("at-root.txt", size: 1), into: CompileViewModel.rootID)

        #expect(vm.compilation.item(withID: folder.id)?.children?.map(\.name) == ["inside.txt"])
        #expect(vm.compilation.items.map(\.name) == ["docs", "at-root.txt"])
        monitor.stop()
    }

    @Test func addIntoPrunedFolderFallsBackToRoot() {
        let folder = CompilationItem(
            name: "gone", sourceURL: URL(fileURLWithPath: "/gone"), kind: .folder(children: [])
        )
        vm.add(folder)
        vm.remove(id: folder.id)  // pruned while a drop was enumerating

        vm.add(makeFile("orphan.txt", size: 1), into: folder.id)
        #expect(vm.compilation.items.map(\.name) == ["orphan.txt"], "never silently dropped")
        monitor.stop()
    }
}

/// Sidebar tree arrow-key navigation (up/down move, right expand/descend,
/// left collapse/ascend) — the logic behind the keyboard handlers.
@MainActor
@Suite struct SidebarKeyboardNavTests {
    let monitor: DeviceMonitor
    let vm: CompileViewModel

    init() {
        monitor = DeviceMonitor(service: MockDiscBurningService())
        vm = CompileViewModel(deviceMonitor: monitor)
    }

    /// root → A[A1, A2], B  (A has subfolders; A1/A2/B are leaf folders).
    @discardableResult
    private func seed() -> (a: UUID, a1: UUID, a2: UUID, b: UUID) {
        let a1 = CompilationItem(name: "A1", sourceURL: URL(fileURLWithPath: "/A/A1"),
                                 kind: .folder(children: [makeFile("f1", size: 1)]))
        let a2 = CompilationItem(name: "A2", sourceURL: URL(fileURLWithPath: "/A/A2"),
                                 kind: .folder(children: [makeFile("f2", size: 1)]))
        let a = CompilationItem(name: "A", sourceURL: URL(fileURLWithPath: "/A"),
                                kind: .folder(children: [a1, a2]))
        let b = CompilationItem(name: "B", sourceURL: URL(fileURLWithPath: "/B"),
                                kind: .folder(children: [makeFile("f3", size: 1)]))
        vm.add(a)
        vm.add(b)
        return (a.id, a1.id, a2.id, b.id)
    }

    @Test func downAndUpMoveThroughVisibleRows() {
        let ids = seed()
        #expect(vm.effectiveSelection == CompileViewModel.rootID)
        vm.selectNextRow(); #expect(vm.selectedFolderID == ids.a)
        vm.selectNextRow(); #expect(vm.selectedFolderID == ids.a1)
        vm.selectNextRow(); #expect(vm.selectedFolderID == ids.a2)
        vm.selectNextRow(); #expect(vm.selectedFolderID == ids.b)
        vm.selectNextRow(); #expect(vm.selectedFolderID == ids.b, "stays put at the last row")
        vm.selectPreviousRow(); #expect(vm.selectedFolderID == ids.a2)
    }

    @Test func downSkipsHiddenChildrenOfCollapsedFolder() {
        let ids = seed()
        vm.collapse(ids.a)                 // A1/A2 hidden
        vm.selectedFolderID = ids.a
        vm.selectNextRow()                 // should skip straight to B
        #expect(vm.selectedFolderID == ids.b)
    }

    @Test func rightExpandsThenDescendsIntoFirstChild() {
        let ids = seed()
        vm.collapse(ids.a)
        vm.selectedFolderID = ids.a
        vm.expandOrDescendRow()            // right → expand, selection unchanged
        #expect(!vm.collapsedFolderIDs.contains(ids.a))
        #expect(vm.selectedFolderID == ids.a)
        vm.expandOrDescendRow()            // right → descend to first child
        #expect(vm.selectedFolderID == ids.a1)
    }

    @Test func leftCollapsesThenAscendsToParent() {
        let ids = seed()
        vm.selectedFolderID = ids.a        // expanded by default
        vm.collapseOrAscendRow()           // left → collapse
        #expect(vm.collapsedFolderIDs.contains(ids.a))
        #expect(vm.selectedFolderID == ids.a)
        vm.collapseOrAscendRow()           // left → ascend to root
        #expect(vm.selectedFolderID == CompileViewModel.rootID)
    }

    @Test func leftFromLeafAscendsToParent() {
        let ids = seed()
        vm.selectedFolderID = ids.a1
        vm.collapseOrAscendRow()
        #expect(vm.selectedFolderID == ids.a)
    }

    @Test func rightOnLeafFolderDoesNothing() {
        let ids = seed()
        vm.selectedFolderID = ids.a2
        vm.expandOrDescendRow()
        #expect(vm.selectedFolderID == ids.a2)
    }
}

/// U7: erase gating and mode flow-through.
@MainActor
@Suite struct EraseViewModelTests {

    let service = MockDiscBurningService()
    let monitor: DeviceMonitor
    let vm: EraseViewModel

    init() {
        monitor = DeviceMonitor(service: service)
        monitor.start()
        vm = EraseViewModel(service: service, deviceMonitor: monitor)
    }

    private func setMedia(_ media: DiscMedia?) async throws {
        service.setDevices([makeDevice(media: media)])
        let propagated = try await eventually { monitor.currentMedia == media }
        #expect(propagated)
    }

    private func waitTerminal() async throws {
        let reached = try await eventually {
            if case .done = vm.state { return true }
            if case .failed = vm.state { return true }
            return false
        }
        #expect(reached, "erase must reach a terminal state")
    }

    @Test func eraseOfferedOnlyForRewritable() async throws {
        try await setMedia(makeMedia(.bdR, capacity: 25_000_000_000, blank: false))
        #expect(!vm.canErase, "BD-R (write-once) is not erasable")

        try await setMedia(makeMedia(.bdRE, capacity: 25_000_000_000, blank: false))
        #expect(vm.canErase)
        monitor.stop()
    }

    @Test func quickAndCompleteFlowThrough() async throws {
        try await setMedia(makeMedia(.cdRW, capacity: 700_000_000, blank: false))
        vm.erase(mode: .quick)
        try await waitTerminal()
        #expect(service.recordedErases.map(\.mode) == [.quick])
        #expect(vm.state == .done)

        vm.reset()
        vm.erase(mode: .complete)
        try await waitTerminal()
        #expect(service.recordedErases.map(\.mode) == [.quick, .complete])
        monitor.stop()
    }

    @Test func eraseFailureSurfacesReason() async throws {
        try await setMedia(makeMedia(.dvdRW, capacity: 4_700_000_000, blank: false))
        service.scriptErase(outcome: .failure(.eraseFailed(reason: "medium error")))
        vm.erase(mode: .quick)
        try await waitTerminal()
        #expect(vm.state == .failed(.eraseFailed(reason: "medium error")))
        monitor.stop()
    }
}

/// U8: image selection and validation gating.
@MainActor
@Suite struct ImageBurnViewModelTests {

    let service = MockDiscBurningService()
    let monitor: DeviceMonitor

    init() {
        monitor = DeviceMonitor(service: service)
        monitor.start()
    }

    private func setMedia(_ media: DiscMedia) async throws {
        service.setDevices([makeDevice(media: media)])
        let propagated = try await eventually { monitor.currentMedia == media }
        #expect(propagated)
    }

    @Test func unsupportedExtensionRejected() {
        let vm = ImageBurnViewModel(deviceMonitor: monitor, fileSizer: { _ in 100 })
        #expect(vm.select(imageAt: URL(fileURLWithPath: "/x/movie.mkv")) == .unsupportedType(ext: "mkv"))
        #expect(!vm.canBurn)
        monitor.stop()
    }

    @Test func supportedExtensionsAccepted() async throws {
        try await setMedia(makeMedia(.bdR, capacity: 25_000_000_000))
        let vm = ImageBurnViewModel(deviceMonitor: monitor, fileSizer: { _ in 1_000_000 })
        for ext in ["iso", "dmg", "img", "ISO"] {
            #expect(vm.select(imageAt: URL(fileURLWithPath: "/x/backup.\(ext)")) == .ok, "\(ext)")
        }
        #expect(vm.canBurn)
        monitor.stop()
    }

    @Test func imageLargerThanMediaBlocked() async throws {
        // R12 for images.
        try await setMedia(makeMedia(.dvdR, capacity: 4_700_000_000))
        let vm = ImageBurnViewModel(deviceMonitor: monitor, fileSizer: { _ in 5_000_000_000 })
        #expect(vm.select(imageAt: URL(fileURLWithPath: "/x/big.iso")) == .tooLarge(overBy: 300_000_000))
        #expect(!vm.canBurn)
        monitor.stop()
    }

    @Test func unreadableImageRejected() {
        let vm = ImageBurnViewModel(deviceMonitor: monitor, fileSizer: { _ in nil })
        #expect(vm.select(imageAt: URL(fileURLWithPath: "/x/ghost.iso")) == .unreadable)
        #expect(!vm.canBurn)
        monitor.stop()
    }
}
