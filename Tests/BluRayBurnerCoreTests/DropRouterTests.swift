import Testing
import Foundation
@testable import BluRayBurnerCore

/// Welcome-screen drop routing: when does the image question fire?
@Suite struct DropRouterTests {

    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/drop/\(name)") }

    @Test func emptyDropRoutesNowhere() {
        #expect(DropRouter.decide(urls: []) == nil)
    }

    @Test(arguments: ["backup.iso", "disk.img", "installer.dmg", "UPPER.ISO"])
    func singleDiscImageAsksTheQuestion(name: String) {
        #expect(DropRouter.decide(urls: [url(name)]) == .askImageOrData(imageURL: url(name)))
    }

    @Test func singleRegularFileGoesToDataDisc() {
        #expect(DropRouter.decide(urls: [url("photo.jpg")]) == .dataItems([url("photo.jpg")]))
    }

    @Test func multipleImagesGoToDataDisc() {
        // "Archive several ISOs onto one Blu-ray" — no question asked.
        let urls = [url("a.iso"), url("b.iso")]
        #expect(DropRouter.decide(urls: urls) == .dataItems(urls))
    }

    @Test func imageMixedWithFilesGoesToDataDisc() {
        let urls = [url("a.iso"), url("notes.txt")]
        #expect(DropRouter.decide(urls: urls) == .dataItems(urls))
    }

    @Test func folderGoesToDataDisc() {
        // Folders have no image extension; routed as data.
        let folder = URL(fileURLWithPath: "/drop/my-folder")
        #expect(DropRouter.decide(urls: [folder]) == .dataItems([folder]))
    }

    @Test func isoNamedFolderStillAsks() {
        // Edge: a *folder* named like an image can't be distinguished by
        // extension alone at routing time; the image screen's validation
        // (unreadable file size) catches it right after. Routing by
        // extension is the documented behavior.
        #expect(DropRouter.decide(urls: [url("weird.iso")]) == .askImageOrData(imageURL: url("weird.iso")))
    }
}
