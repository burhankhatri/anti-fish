import XCTest
@testable import AntiFishCore

final class ChatStoreIntegrationTests: XCTestCase {
    func testLiveChatStorageOpensWhileWhatsAppRuns() throws {
        try TestEnv.skipUnlessRealWA()
        let store = try ChatStore.open(url: ContainerLocator().chatStorageURL)
        let messages = try store.db.scalarInt("SELECT COUNT(*) FROM ZWAMESSAGE") ?? 0
        XCTAssertGreaterThan(messages, 0)
        XCTAssertTrue(try store.tableExists("ZWAMEDIAITEM"))
        XCTAssertTrue(try store.tableExists("ZWAGROUPMEMBER"))
    }

    func testLiveContactsOpens() throws {
        try TestEnv.skipUnlessRealWA()
        let store = try ChatStore.open(url: ContainerLocator().contactsURL)
        XCTAssertTrue(try store.tableExists("ZWAADDRESSBOOKCONTACT"))
    }
}
