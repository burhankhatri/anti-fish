import XCTest
@testable import AntiFishCore

final class NameResolverTests: XCTestCase {
    private func tables() throws -> NameTables {
        let pair = try FixtureDB.standardPair()
        return try NameTables.load(chat: try ChatStore(url: pair.chat), contacts: try ChatStore(url: pair.contacts))
    }

    func testAddressBookWinsAndMarksSaved() throws {
        let id = NameResolver.resolve("111@lid", tables: try tables())
        XCTAssertEqual(id.displayName, "Abdul Test")
        XCTAssertTrue(id.isSavedContact)
        XCTAssertEqual(id.pushName, "abdul")
        XCTAssertEqual(id.avatarPath, "Media/Profile/111-1.thumb")
    }

    func testSavedChatNameUsedWhenNotInAddressBook() throws {
        let id = NameResolver.resolve("200@g.us", tables: try tables())
        XCTAssertEqual(id.displayName, "Family")
        XCTAssertFalse(id.isSavedContact)
    }

    /// A phone-shaped chat name carries no information, so the push name wins instead.
    /// The push name is chosen by the sender, so it must never mark someone as a saved contact.
    func testPhoneShapedChatNameIsSkippedInFavourOfPushName() throws {
        let id = NameResolver.resolve("333@lid", tables: try tables())
        XCTAssertEqual(id.displayName, "Abdul")
        XCTAssertFalse(id.isSavedContact)
    }

    func testUnknownJIDFallsBackToMaskedDigits() {
        XCTAssertEqual(NameResolver.resolve("5551234567@lid", tables: NameTables()).displayName, "WA ····4567")
        XCTAssertEqual(NameResolver.fallbackName(for: "abc@lid"), "WhatsApp user")
        XCTAssertEqual(NameResolver.fallbackName(for: ""), "WhatsApp user")
    }

    func testPhoneShaped() {
        XCTAssertTrue(NameResolver.isPhoneShaped("+1 555 0100"))
        XCTAssertTrue(NameResolver.isPhoneShaped("(555) 010-0100"))
        XCTAssertFalse(NameResolver.isPhoneShaped("Abdul"))
        XCTAssertFalse(NameResolver.isPhoneShaped("Abdul 2"))
        XCTAssertFalse(NameResolver.isPhoneShaped(""))
    }

    func testAddressBookIsIndexedUnderBothJIDForms() throws {
        let t = try tables()
        XCTAssertEqual(t.addressBook["111@lid"], "Abdul Test")
        XCTAssertEqual(t.addressBook["15550111@s.whatsapp.net"], "Abdul Test")
    }

    func testMissingContactsDatabaseIsTolerated() throws {
        let pair = try FixtureDB.standardPair()
        let t = try NameTables.load(chat: try ChatStore(url: pair.chat), contacts: nil)
        XCTAssertTrue(t.addressBook.isEmpty)
        let id = NameResolver.resolve("111@lid", tables: t)
        XCTAssertEqual(id.displayName, "Abdul Test")  // falls through to the saved chat name
        XCTAssertFalse(id.isSavedContact)
    }
}
