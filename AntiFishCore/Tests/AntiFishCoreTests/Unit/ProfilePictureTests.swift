import XCTest
@testable import AntiFishCore

/// Profile pictures are the one thing that stops a chat list looking like a spreadsheet, and every
/// avatar was falling back to initials. Two reasons: they live under `<container>/Media/Profile`
/// rather than under `Message/`, and the file on disk has `.thumb` appended to the stored path.
/// Of 21,727 rows in the table only 255 hold a path at all; the rest hold protobuf.
final class ProfilePictureTests: XCTestCase {
    func testProfilePicturesResolveFromTheContainerRootNotTheMessageFolder() throws {
        let root = try TestEnv.tempDir()
        let locator = ContainerLocator(root: root)
        let dir = root.appendingPathComponent("Media/Profile", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([1]).write(to: dir.appendingPathComponent("111-222.thumb"))

        let url = locator.profilePictureURL(relativePath: "Media/Profile/111-222")
        XCTAssertEqual(url?.lastPathComponent, "111-222.thumb")
    }

    func testAJpgIsUsedWhenThereIsNoThumbnail() throws {
        let root = try TestEnv.tempDir()
        let dir = root.appendingPathComponent("Media/Profile", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([1]).write(to: dir.appendingPathComponent("111-222.jpg"))

        XCTAssertEqual(ContainerLocator(root: root)
            .profilePictureURL(relativePath: "Media/Profile/111-222")?.lastPathComponent,
                       "111-222.jpg")
    }

    func testAPathWithNoFileGivesNothing() throws {
        let root = try TestEnv.tempDir()
        XCTAssertNil(ContainerLocator(root: root).profilePictureURL(relativePath: "Media/Profile/gone"))
    }

    /// Most rows in the table hold an encoded blob rather than a path. Treating those as paths
    /// meant every lookup missed.
    func testOnlyPathShapedValuesAreKept() throws {
        let pair = try FixtureDB.standardPair()
        let chat = try ChatStore(url: pair.chat)
        try chat.db.execute("""
            INSERT INTO ZWAPROFILEPICTUREITEM VALUES
              (2,'222@lid','ChsKFTE0NDM5ODY0NjQ3ODkwOjY1QGxpZBABGAEK'),
              (3,'333@lid','Media/Profile/333-1');
            """)
        let tables = try NameTables.load(chat: chat, contacts: nil)
        XCTAssertNil(tables.avatarPaths["222@lid"], "an encoded blob is not a path")
        XCTAssertEqual(tables.avatarPaths["333@lid"], "Media/Profile/333-1")
    }

    func testTheFixtureAvatarIsStillRead() throws {
        let pair = try FixtureDB.standardPair()
        let tables = try NameTables.load(chat: try ChatStore(url: pair.chat), contacts: nil)
        XCTAssertEqual(tables.avatarPaths["111@lid"], "Media/Profile/111-1")
    }
}
