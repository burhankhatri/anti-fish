import XCTest
@testable import AntiFishCore

final class NameResolverIntegrationTests: XCTestCase {
    func testLiveTablesNameMostVoiceNoteSenders() throws {
        try TestEnv.skipUnlessRealWA()
        let locator = ContainerLocator()
        let chat = try ChatStore.open(url: locator.chatStorageURL)
        let contacts = try? ChatStore.open(url: locator.contactsURL)
        let tables = try NameTables.load(chat: chat, contacts: contacts)
        XCTAssertGreaterThan(tables.addressBook.count, 0)
        XCTAssertGreaterThan(tables.pushNames.count, 0)

        let senders = Set(try VoiceNoteQuery.fetch(chat).filter { !$0.isFromMe }.map(\.senderJID))
        XCTAssertGreaterThan(senders.count, 0)
        let named = senders.filter { !NameResolver.resolve($0, tables: tables).displayName.hasPrefix("WA ") }
        XCTAssertGreaterThan(named.count, 0)
        // At least one voice-note sender should be a genuine saved contact.
        XCTAssertTrue(senders.contains { NameResolver.resolve($0, tables: tables).isSavedContact })
    }
}
