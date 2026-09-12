import XCTest
@testable import AntiFishCore

final class SmokeTests: XCTestCase {
    func testPackageVersionIsSet() {
        XCTAssertEqual(AntiFishCore.version, "0.1.0")
    }
}
