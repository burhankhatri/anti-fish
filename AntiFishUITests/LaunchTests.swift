import XCTest

final class LaunchTests: XCTestCase {
    func testAppLaunchesAndShowsAWindow() {
        let app = XCUIApplication()
        app.launchEnvironment["ANTIFISH_CONTAINER_ROOT"] = NSTemporaryDirectory() + "antifish-empty-\(UUID().uuidString)"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["onboarding.needsWhatsApp"].waitForExistence(timeout: 15),
                      "an empty container should land on the first onboarding step")
    }
}
