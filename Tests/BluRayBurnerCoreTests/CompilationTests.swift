import Testing
import Foundation
@testable import BluRayBurnerCore

// MARK: - Shared helpers

func makeFile(_ name: String, size: Int64) -> CompilationItem {
    CompilationItem(name: name, sourceURL: URL(fileURLWithPath: "/src/\(name)"), kind: .file(sizeBytes: size))
}

func makeMedia(_ type: MediaType = .bdR, capacity: Int64, blank: Bool = true, writable: Bool = true) -> DiscMedia {
    DiscMedia(type: type, capacityBytes: capacity, isBlank: blank, isAppendable: false, isWritable: writable)
}

func makeDevice(media: DiscMedia?) -> OpticalDevice {
    OpticalDevice(
        id: "d1", displayName: "Test Burner",
        canWriteCD: true, canWriteDVD: true, canWriteBD: true, media: media
    )
}

/// Polls until `condition` is true or the timeout elapses (event propagation).
func eventually(
    timeout: TimeInterval = 2,
    _ condition: @MainActor () -> Bool
) async throws -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !(await MainActor.run(body: condition)) {
        if Date() > deadline { return false }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    return true
}

// MARK: - U4: compilation tree, size math, capacity (R3, R5, R12)

@Suite struct CompilationTests {

    @Test func emptyCompilationHasZeroSize() {
        let compilation = Compilation()
        #expect(compilation.isEmpty)
        #expect(compilation.totalBytes == 0)
    }

    @Test func nestedFoldersMirrorHierarchyAndNames() {
        // R3: names and hierarchy preserved byte-for-byte.
        let child = makeFile("Résumé —final (v2).pdf", size: 100)
        let folder = CompilationItem(
            name: "Docs 2026",
            sourceURL: URL(fileURLWithPath: "/src/Docs 2026"),
            kind: .folder(children: [child])
        )
        var compilation = Compilation()
        compilation.add(folder)

        let layout = FilesystemLayoutBuilder.makeLayout(from: compilation, mediaType: .bdR)
        guard case .folder(let name, let children) = layout.root[0] else {
            Issue.record("expected folder at root")
            return
        }
        #expect(name == "Docs 2026")
        #expect(children[0].name == "Résumé —final (v2).pdf")
    }

    @Test func fileLargerThan4GB() {
        // R5: >4 GB files supported; no 32-bit overflow.
        let big: Int64 = 20 * 1024 * 1024 * 1024
        var compilation = Compilation()
        compilation.add(makeFile("archive.tar", size: big))
        compilation.add(makeFile("side.txt", size: 1))
        #expect(compilation.totalBytes == big + 1)
    }

    @Test func capacityUnderExactOverBoundaries() {
        // R12 boundaries.
        var compilation = Compilation()
        compilation.add(makeFile("data.bin", size: 1000))

        #expect(compilation.capacityState(for: makeMedia(capacity: 1500)) == .underCapacity(freeBytes: 500))
        #expect(compilation.capacityState(for: makeMedia(capacity: 1000)) == .exact)
        #expect(compilation.capacityState(for: makeMedia(capacity: 900)) == .overCapacity(overBy: 100))
        #expect(compilation.capacityState(for: nil) == .noMedia)

        #expect(CapacityState.underCapacity(freeBytes: 500).allowsBurn)
        #expect(CapacityState.exact.allowsBurn)
        #expect(!CapacityState.overCapacity(overBy: 100).allowsBurn)
        #expect(!CapacityState.noMedia.allowsBurn)
    }

    @Test func duplicateTopLevelNamesResolvedDeterministically() {
        var compilation = Compilation()
        compilation.add(makeFile("report.pdf", size: 10))
        compilation.add(makeFile("report.pdf", size: 20))
        compilation.add(makeFile("report.pdf", size: 30))
        #expect(compilation.items.map(\.name) == ["report.pdf", "report.pdf 2", "report.pdf 3"])
    }

    @Test func removeUpdatesSize() {
        var compilation = Compilation()
        let doomed = makeFile("a.bin", size: 100)
        compilation.add(doomed)
        compilation.add(makeFile("b.bin", size: 50))
        compilation.remove(id: doomed.id)
        #expect(compilation.totalBytes == 50)
        #expect(compilation.items.count == 1)
    }

    @Test func removeFileNestedInsideFolderPrunesOnlyThatFile() {
        // Tree-view pruning: removing a file inside a dropped folder excludes
        // it from the burn set; siblings and the folder itself remain.
        let doomed = makeFile("skip-me.tmp", size: 400)
        let keep = makeFile("keep.dat", size: 100)
        let sub = CompilationItem(
            name: "sub",
            sourceURL: URL(fileURLWithPath: "/src/folder/sub"),
            kind: .folder(children: [doomed, keep])
        )
        let folder = CompilationItem(
            name: "folder",
            sourceURL: URL(fileURLWithPath: "/src/folder"),
            kind: .folder(children: [sub, makeFile("top.txt", size: 10)])
        )
        var compilation = Compilation()
        compilation.add(folder)
        #expect(compilation.totalBytes == 510)

        compilation.remove(id: doomed.id)

        #expect(compilation.totalBytes == 110, "only the pruned file's size disappears")
        #expect(compilation.items.count == 1, "folder still present")
        let paths = Set(compilation.allSourceURLs.map(\.path))
        #expect(!paths.contains("/src/skip-me.tmp"), "pruned file no longer referenced")
        #expect(paths.contains("/src/keep.dat"), "sibling survives")
    }

    @Test func removeNestedSubfolderRemovesItsSubtree() {
        let inner = makeFile("inner.dat", size: 30)
        let sub = CompilationItem(
            name: "sub",
            sourceURL: URL(fileURLWithPath: "/src/f/sub"),
            kind: .folder(children: [inner])
        )
        let folder = CompilationItem(
            name: "f",
            sourceURL: URL(fileURLWithPath: "/src/f"),
            kind: .folder(children: [sub, makeFile("stay.txt", size: 5)])
        )
        var compilation = Compilation()
        compilation.add(folder)

        compilation.remove(id: sub.id)

        #expect(compilation.totalBytes == 5)
        guard case .folder(_, _) = FilesystemLayoutBuilder.makeLayout(from: compilation, mediaType: .bdR).root[0] else {
            Issue.record("folder should remain in layout")
            return
        }
    }

    @Test func folderEmptiedByPruningStaysAsEmptyFolder() {
        let only = makeFile("only.dat", size: 7)
        let folder = CompilationItem(
            name: "will-be-empty",
            sourceURL: URL(fileURLWithPath: "/src/e"),
            kind: .folder(children: [only])
        )
        var compilation = Compilation()
        compilation.add(folder)
        compilation.remove(id: only.id)

        #expect(compilation.items.count == 1)
        #expect(compilation.items[0].children?.isEmpty == true)
        #expect(compilation.totalBytes == 0)
    }

    @Test func addIntoNestedFolderLandsThere() {
        // Split view: drops land in the selected virtual folder.
        let sub = CompilationItem(
            name: "sub", sourceURL: URL(fileURLWithPath: "/src/f/sub"), kind: .folder(children: [])
        )
        let folder = CompilationItem(
            name: "f", sourceURL: URL(fileURLWithPath: "/src/f"), kind: .folder(children: [sub])
        )
        var compilation = Compilation()
        compilation.add(folder)

        compilation.add(makeFile("dropped.dat", size: 42), into: sub.id)

        #expect(compilation.item(withID: sub.id)?.children?.map(\.name) == ["dropped.dat"])
        #expect(compilation.totalBytes == 42)
        #expect(compilation.items.count == 1, "nothing added at top level")
    }

    @Test func addIntoMissingFolderFallsBackToRoot() {
        var compilation = Compilation()
        compilation.add(makeFile("dropped.dat", size: 1), into: UUID())
        #expect(compilation.items.map(\.name) == ["dropped.dat"], "never silently dropped")
    }

    @Test func addIntoFolderResolvesDuplicateSiblingNames() {
        let folder = CompilationItem(
            name: "f", sourceURL: URL(fileURLWithPath: "/src/f"),
            kind: .folder(children: [makeFile("a.txt", size: 1)])
        )
        var compilation = Compilation()
        compilation.add(folder)
        compilation.add(makeFile("a.txt", size: 2), into: folder.id)
        #expect(compilation.item(withID: folder.id)?.children?.map(\.name) == ["a.txt", "a.txt 2"])
    }

    @Test func itemWithIDFindsAtAnyDepth() {
        let deep = makeFile("deep.dat", size: 3)
        let sub = CompilationItem(
            name: "sub", sourceURL: URL(fileURLWithPath: "/s"), kind: .folder(children: [deep])
        )
        var compilation = Compilation()
        compilation.add(CompilationItem(
            name: "top", sourceURL: URL(fileURLWithPath: "/t"), kind: .folder(children: [sub])
        ))
        #expect(compilation.item(withID: deep.id)?.name == "deep.dat")
        #expect(compilation.item(withID: UUID()) == nil)
    }

    @Test func childrenAccessorFollowsOutlineContract() {
        // OutlineGroup contract: folders → non-nil (empty ok), files → nil.
        #expect(makeFile("f.bin", size: 1).children == nil)
        let folder = CompilationItem(
            name: "d", sourceURL: URL(fileURLWithPath: "/d"), kind: .folder(children: [])
        )
        #expect(folder.children != nil)
        #expect(folder.children?.isEmpty == true)
    }

    @Test func allSourceURLsCollectsNestedFiles() {
        // KTD3/KTD4: every URL the burn must hold access to.
        let inner = makeFile("inner.dat", size: 5)
        let folder = CompilationItem(
            name: "F",
            sourceURL: URL(fileURLWithPath: "/src/F"),
            kind: .folder(children: [inner])
        )
        var compilation = Compilation()
        compilation.add(folder)
        compilation.add(makeFile("top.dat", size: 5))
        #expect(Set(compilation.allSourceURLs.map(\.path)) == ["/src/F", "/src/inner.dat", "/src/top.dat"])
    }
}

// MARK: - U4: filesystem selection (R4, R6, KTD2)

@Suite struct FilesystemLayoutBuilderTests {

    @Test func cdGetsUDFPlusISOJolietBridge() {
        #expect(FilesystemLayoutBuilder.filesystems(for: .cdR) == [.udf, .iso9660, .joliet])
        #expect(FilesystemLayoutBuilder.filesystems(for: .cdRW) == [.udf, .iso9660, .joliet])
    }

    @Test(arguments: [MediaType.dvdR, .dvdRW, .bdR, .bdRE])
    func dvdAndBDGetUDFOnly(type: MediaType) {
        #expect(FilesystemLayoutBuilder.filesystems(for: type) == [.udf])
    }

    @Test func layoutCarriesVolumeNameAndFilesystems() {
        var compilation = Compilation(volumeName: "BACKUP_2026")
        compilation.add(makeFile("a.bin", size: 1))
        let cdLayout = FilesystemLayoutBuilder.makeLayout(from: compilation, mediaType: .cdR)
        #expect(cdLayout.volumeName == "BACKUP_2026")
        #expect(cdLayout.filesystems == [.udf, .iso9660, .joliet])

        let bdLayout = FilesystemLayoutBuilder.makeLayout(from: compilation, mediaType: .bdR)
        #expect(bdLayout.filesystems == [.udf])
    }

    @Test func treeMirrorsCompilationExactly() {
        // R3: layout tree mirrors input; file nodes keep source URLs.
        let deep = CompilationItem(
            name: "deep.txt",
            sourceURL: URL(fileURLWithPath: "/src/x/deep.txt"),
            kind: .file(sizeBytes: 1)
        )
        let mid = CompilationItem(
            name: "mid",
            sourceURL: URL(fileURLWithPath: "/src/x"),
            kind: .folder(children: [deep])
        )
        var compilation = Compilation()
        compilation.add(mid)

        let layout = FilesystemLayoutBuilder.makeLayout(from: compilation, mediaType: .bdR)
        guard case .folder(let midName, let children) = layout.root[0],
              case .file(let deepName, let src) = children[0] else {
            Issue.record("layout shape mismatch")
            return
        }
        #expect(midName == "mid")
        #expect(deepName == "deep.txt")
        #expect(src.path == "/src/x/deep.txt")
    }
}
