import XCTest
@testable import AntiFishCore

final class ContainerLocatorTests: XCTestCase {
    func testDefaultRootIsTheWhatsAppGroupContainer() {
        let root = ContainerLocator.defaultRoot.path
        XCTAssertTrue(root.hasSuffix("/Library/Group Containers/group.net.whatsapp.WhatsApp.shared"))
    }

    func testNotInstalledWhenChatStorageMissing() throws {
        let root = try TestEnv.tempDir()
        let locator = ContainerLocator(root: root)
        XCTAssertFalse(locator.isInstalled)
        XCTAssertFalse(locator.hasFullDiskAccess)
    }

    func testInstalledAndReadableWhenChatStorageExists() throws {
        let root = try TestEnv.tempDir()
        try Data("x".utf8).write(to: root.appendingPathComponent("ChatStorage.sqlite"))
        let locator = ContainerLocator(root: root)
        XCTAssertTrue(locator.isInstalled)
        XCTAssertTrue(locator.hasFullDiskAccess)
        XCTAssertEqual(locator.contactsURL.lastPathComponent, "ContactsV2.sqlite")
        XCTAssertEqual(locator.mediaRoot.path, root.appendingPathComponent("Message/Media").path)
    }

    func testMediaURLJoinsRelativePath() throws {
        let root = try TestEnv.tempDir()
        let url = ContainerLocator(root: root).mediaURL(relativePath: "Message/Media/111@lid/a/b/n1.opus")
        XCTAssertEqual(url.path, root.appendingPathComponent("Message/Media/111@lid/a/b/n1.opus").path)
    }
}
