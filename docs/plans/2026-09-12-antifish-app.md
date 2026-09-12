# AntiFish App Implementation Plan (Plan 2 of 3)

**Goal:** The resident macOS app from spec section 9: onboarding, voice-note feed with verdicts and detail, contacts, settings, menu bar, red-only notifications, live watching with backfill, verified frame-perfect with the intentful-ui loop.
**Architecture:** A SwiftUI app target `AntiFish` (XcodeGen) depending on the local package `AntiFishCore` from Plan 1. One `@MainActor @Observable AppModel` owns the `Coordinator`, `VoiceEngine`, `AppDatabase` and `ContainerWatcher`, drives a phase state machine (WhatsApp → Full Disk Access → setup choices → enrolling → ready) and projects core records into view rows. Views are thin. UI tests are XCUITest against this Mac's real data (decision in spec section 11).
**Tech Stack:** Swift 6.3, SwiftUI (`NavigationSplitView`, `MenuBarExtra`, `@Observable`), AVFoundation playback, `UserNotifications`, `ServiceManagement`, XcodeGen 2.45, XCUITest, intentful-ui harness (ffmpeg, cliclick, frame_diff.py).
**Depends on:** Plan 1 green (`AntiFishCore` API as specified there).

Conventions: as in Plan 1. App code lives under `AntiFish/`; the scheme is `AntiFish`; `make build` puts the Debug app at `build/Build/Products/Debug/AntiFish.app`. Every SwiftUI change is finished only when the intentful-ui loop (Task 10) reports SMOOTH for the affected transition.

---

### Task 0: App target, Makefile targets, entitlements

**Files:**
- Create: `project.yml`
- Create: `AntiFish/App/AntiFishApp.swift`
- Create: `AntiFish/App/AntiFish.entitlements`, `AntiFish/App/AntiFish-Debug.entitlements`
- Create: `AntiFishUITests/LaunchTests.swift`
- Modify: `Makefile`

- [ ] **Step 1: Write the failing test**
`AntiFishUITests/LaunchTests.swift`:
```swift
import XCTest

final class LaunchTests: XCTestCase {
    func testAppLaunchesAndShowsAWindow() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["antifish.rootMarker"].waitForExistence(timeout: 10))
    }
}
```

- [ ] **Step 2: Scaffold so the test compiles, run it, watch it fail**

`project.yml`:
```yaml
name: AntiFish
options:
  bundleIdPrefix: com.magnetismstudios
  deploymentTarget:
    macOS: "15.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    MACOSX_DEPLOYMENT_TARGET: "15.0"
    DEVELOPMENT_TEAM: W4464244GE
packages:
  AntiFishCore:
    path: AntiFishCore
targets:
  AntiFish:
    type: application
    platform: macOS
    sources:
      - path: AntiFish
        excludes:
          - "Resources/Models"
      - path: AntiFish/Resources/Models
        type: folder
        buildPhase: resources
    dependencies:
      - package: AntiFishCore
        product: AntiFishCore
    info:
      path: AntiFish/App/Info.plist
      properties:
        CFBundleName: AntiFish
        CFBundleDisplayName: AntiFish
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        LSMinimumSystemVersion: "15.0"
        LSApplicationCategoryType: public.app-category.utilities
        NSHumanReadableCopyright: "Copyright © 2026 Magnetism Studios."
    settings:
      base:
        INFOPLIST_FILE: AntiFish/App/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        ENABLE_HARDENED_RUNTIME: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.magnetismstudios.antifish.mac
      configs:
        Debug:
          CODE_SIGN_STYLE: Automatic
          CODE_SIGN_IDENTITY: "Apple Development"
          CODE_SIGN_ENTITLEMENTS: AntiFish/App/AntiFish-Debug.entitlements
        Release:
          CODE_SIGN_STYLE: Manual
          CODE_SIGN_IDENTITY: "Developer ID Application"
          CODE_SIGN_ENTITLEMENTS: AntiFish/App/AntiFish.entitlements
  AntiFishUITests:
    type: bundle.ui-testing
    platform: macOS
    sources:
      - AntiFishUITests
    dependencies:
      - target: AntiFish
    settings:
      base:
        TEST_TARGET_NAME: AntiFish
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.magnetismstudios.antifish.uitests
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_IDENTITY: "Apple Development"
schemes:
  AntiFish:
    build:
      targets:
        AntiFish: all
        AntiFishUITests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - AntiFishUITests
    archive:
      config: Release
```

Both entitlements files (identical content; Xcode adds `get-task-allow` to Debug itself):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <false/>
</dict>
</plist>
```

`AntiFish/App/AntiFishApp.swift` (deliberately without the marker so the test fails first):
```swift
import SwiftUI

@main
struct AntiFishApp: App {
    var body: some Scene {
        WindowGroup("AntiFish") {
            Text("AntiFish")
        }
    }
}
```

Makefile additions (Plan 1's targets stay; `test` remains the unit suite):
```make
APP_NAME    := AntiFish.app
BUILT_APP   := build/Build/Products/Debug/$(APP_NAME)
INSTALLED   := /Applications/$(APP_NAME)

.PHONY: project build install run test-ui

project:
	xcodegen generate

build: project models
	find build -name "._*" -type f -delete 2>/dev/null || true
	xcodebuild -project AntiFish.xcodeproj -scheme AntiFish -configuration Debug \
	  -destination 'platform=macOS' -derivedDataPath build -allowProvisioningUpdates build

# TCC keys Full Disk Access to bundle ID + team, so rebuilds keep the grant. Do not rename either.
install: build
	rm -rf "$(INSTALLED)"
	cp -R "$(BUILT_APP)" "$(INSTALLED)"

run: install
	pkill -f "$(APP_NAME)/Contents/MacOS/AntiFish" 2>/dev/null || true
	sleep 1
	open "$(INSTALLED)"

test-ui: project models
	find build -name "._*" -type f -delete 2>/dev/null || true
	ANTIFISH_REAL_WA=1 xcodebuild -project AntiFish.xcodeproj -scheme AntiFish -configuration Debug \
	  -destination 'platform=macOS' -derivedDataPath build -allowProvisioningUpdates test
```

Run: `make test-ui`
Expected: the project generates, the app builds and launches, `LaunchTests.testAppLaunchesAndShowsAWindow` FAILS on the `antifish.rootMarker` assertion.

- [ ] **Step 3: Minimal implementation**
Change the body of `AntiFishApp.swift` to:
```swift
        WindowGroup("AntiFish") {
            Text("AntiFish").accessibilityIdentifier("antifish.rootMarker")
        }
```

- [ ] **Step 4: Run test to verify it passes**
Run: `make test-ui` → `Executed 1 test, with 0 failures`. Also `make build` → `** BUILD SUCCEEDED **` and `ls build/Build/Products/Debug/AntiFish.app/Contents/Resources/Models` lists both `.onnx` files.

- [ ] **Step 5: Commit**
```bash
git add project.yml Makefile AntiFish AntiFishUITests
git commit -m "chore(app): XcodeGen app target, UI test target, build/install/run targets

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 1: Core additions for the UI (identity lookup, pin, blacklist, mark genuine, top-3 comparisons)

**Files:**
- Modify: `AntiFishCore/Sources/AntiFishCore/Store/AppDatabase.swift` (migration v2 + helpers)
- Modify: `AntiFishCore/Sources/AntiFishCore/Store/Records.swift` (`topComparisonsJSON`)
- Modify: `AntiFishCore/Sources/AntiFishCore/Pipeline/Coordinator.swift`
- Modify: `AntiFishCore/Sources/AntiFishCore/WhatsApp/NameResolver.swift` (public initializer on `ResolvedIdentity`)
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/AppDatabaseUITests.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/CoordinatorActionsTests.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Integration/CoordinatorActionsIntegrationTests.swift`

- [ ] **Step 1: Write the failing tests**

`Unit/AppDatabaseUITests.swift`:
```swift
import XCTest
@testable import AntiFishCore

final class AppDatabaseUITests: XCTestCase {
    private let when = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testPinAndBlacklistFlags() throws {
        let db = try AppDatabase(url: nil)
        try db.saveContacts([ContactRecord(jid: "a@lid", displayName: "Abdul", isSaved: true, pinned: false, blacklisted: false, avatarPath: nil)])
        try db.setPinned(jid: "a@lid", true)
        try db.setBlacklisted(jid: "a@lid", true)
        let c = try XCTUnwrap(try db.contact(jid: "a@lid"))
        XCTAssertTrue(c.pinned); XCTAssertTrue(c.blacklisted)
        XCTAssertNil(try db.contact(jid: "zz@lid"))
        XCTAssertThrowsError(try db.setPinned(jid: "zz@lid", true))
    }

    func testTopComparisonsRoundTrip() throws {
        let db = try AppDatabase(url: nil)
        let note = VoiceNoteRecord(messagePK: 5, chatJID: "a@lid", senderJID: "a@lid", isFromMe: false, date: when, durationSeconds: 4, relativeMediaPath: "Message/Media/a@lid/1/2/x.opus", chatIsGroup: false)
        let verdict = Verdict(kind: .unclear, colour: .amber, comparedJID: "a@lid", score: 0.3, best: Comparison(jid: "k@lid", score: 0.31), reason: "borderline", explanation: "x")
        let top = [Comparison(jid: "k@lid", score: 0.31), Comparison(jid: "a@lid", score: 0.3)]
        try db.saveVerdict(VerdictRecord(note: note, verdict: verdict, speechSeconds: 3, computedAt: when, modelVersion: "m", topComparisons: top))
        XCTAssertEqual(try db.verdict(messagePK: 5)?.topComparisons, top)
        try db.saveVerdict(VerdictRecord(note: note, verdict: verdict, speechSeconds: 3, computedAt: when, modelVersion: "m"))
        XCTAssertEqual(try db.verdict(messagePK: 5)?.topComparisons, [])
    }

    func testOverrideVerdictAsImpostor() throws {
        let db = try AppDatabase(url: nil)
        let note = VoiceNoteRecord(messagePK: 6, chatJID: "x@lid", senderJID: "x@lid", isFromMe: false, date: when, durationSeconds: 4, relativeMediaPath: "p", chatIsGroup: false)
        try db.saveVerdict(VerdictRecord(note: note, verdict: Verdict(kind: .unknownVoice, colour: .grey, comparedJID: nil, score: nil, best: nil, reason: nil, explanation: "x"), speechSeconds: 3, computedAt: when, modelVersion: "m"))
        try db.overrideVerdict(messagePK: 6, kind: .impersonationSuspected, colour: .red, reason: "userReported", explanation: "You reported this sender.")
        let v = try XCTUnwrap(try db.verdict(messagePK: 6))
        XCTAssertEqual(v.kind, "impersonationSuspected"); XCTAssertEqual(v.colour, "red"); XCTAssertEqual(v.reason, "userReported")
    }
}
```

`Unit/CoordinatorActionsTests.swift` (fixture container under a temp root; needs models only to construct the engine):
```swift
import XCTest
@testable import AntiFishCore

final class CoordinatorActionsTests: XCTestCase {
    private func make() throws -> (Coordinator, AppDatabase) {
        try TestEnv.skipUnlessModels()
        let pair = try FixtureDB.standardPair()
        let locator = ContainerLocator(root: pair.chat.deletingLastPathComponent())
        let db = try AppDatabase(url: nil)
        let engine = try VoiceEngine(models: ModelPaths(directory: TestEnv.modelsDir))
        return (Coordinator(config: CoordinatorConfig(locator: locator, models: ModelPaths(directory: TestEnv.modelsDir)), db: db, engine: engine), db)
    }

    func testIdentityUsesTheFixtureTables() async throws {
        let (coordinator, _) = try make()
        let id = try await coordinator.identity(for: "111@lid")
        XCTAssertEqual(id.displayName, "Abdul Test"); XCTAssertTrue(id.isSavedContact)
        XCTAssertEqual(try await coordinator.identity(for: "200@g.us").displayName, "Family")
    }

    func testReportImpostorBlacklistsAndFlagsRed() async throws {
        let (coordinator, db) = try make()
        try db.saveContacts([ContactRecord(jid: "333@lid", displayName: "Abdul", isSaved: false, pinned: false, blacklisted: false, avatarPath: nil)])
        try db.saveFingerprints([Fingerprint(jid: "333@lid", centroid: [1, 0], noteCount: 3, speechSeconds: 40, lastNoteDate: Date(), modelVersion: "m")])
        let note = VoiceNoteRecord(messagePK: 1002, chatJID: "333@lid", senderJID: "333@lid", isFromMe: false, date: Date(), durationSeconds: 5, relativeMediaPath: "p", chatIsGroup: false)
        try db.saveVerdict(VerdictRecord(note: note, verdict: Verdict(kind: .unknownVoice, colour: .grey, comparedJID: nil, score: nil, best: nil, reason: nil, explanation: "x"), speechSeconds: 4, computedAt: Date(), modelVersion: "m"))
        try await coordinator.reportImpostor(messagePK: 1002)
        XCTAssertEqual(try db.contact(jid: "333@lid")?.blacklisted, true)
        XCTAssertTrue(try db.fingerprints().isEmpty)
        XCTAssertEqual(try db.verdict(messagePK: 1002)?.colour, "red")
    }

    func testSetPinnedAndProtectedList() async throws {
        let (coordinator, db) = try make()
        try db.saveContacts([ContactRecord(jid: "111@lid", displayName: "Abdul Test", isSaved: true, pinned: false, blacklisted: false, avatarPath: nil)])
        try db.saveFingerprints([Fingerprint(jid: "111@lid", centroid: [1, 0], noteCount: 3, speechSeconds: 40, lastNoteDate: Date(), modelVersion: "m")])
        try await coordinator.setPinned(jid: "111@lid", true)
        XCTAssertEqual(try await coordinator.protectedJIDs(), ["111@lid"])
    }
}
```

`Integration/CoordinatorActionsIntegrationTests.swift`:
```swift
import XCTest
@testable import AntiFishCore

final class CoordinatorActionsIntegrationTests: XCTestCase {
    func testMarkGenuineAppendsTheNoteToEnrollment() async throws {
        try TestEnv.skipUnlessRealWA(); try TestEnv.skipUnlessModels()
        let config = CoordinatorConfig(locator: ContainerLocator(), models: ModelPaths(directory: TestEnv.modelsDir))
        let db = try AppDatabase(url: nil)
        let coordinator = Coordinator(config: config, db: db, engine: try VoiceEngine(models: config.models, numThreads: 4))
        let fingerprints = try await coordinator.enrollAll()
        let jid = try XCTUnwrap(fingerprints.first?.jid)
        let store = try ChatStore.open(url: config.locator.chatStorageURL)
        let notes = try VoiceNoteQuery.fetch(store).filter { $0.senderJID == jid && !$0.isFromMe && $0.durationSeconds >= 3 }
        let enrolledPKs = Set(try db.enrollmentNotes(jid: jid).map(\.messagePK))
        let candidate = try XCTUnwrap(notes.first { !enrolledPKs.contains($0.messagePK) } ?? notes.first)
        _ = try await coordinator.verify(candidate)
        let before = try db.enrollmentNotes(jid: jid).count
        try await coordinator.markGenuine(messagePK: candidate.messagePK)
        let after = try db.enrollmentNotes(jid: jid)
        XCTAssertTrue(after.contains { $0.messagePK == candidate.messagePK })
        XCTAssertLessThanOrEqual(after.count, 30)
        XCTAssertGreaterThanOrEqual(after.count, min(30, before))
        XCTAssertEqual(try db.verdict(messagePK: candidate.messagePK)?.kind, "verified")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**
Run: `make test` → compile errors: `has no member 'setPinned'`, `extra argument 'topComparisons'`, `has no member 'identity'`.

- [ ] **Step 3: Implement**

`Store/Records.swift` — add to `VerdictRecord`:
```swift
    public var topComparisonsJSON: String?

    public var topComparisons: [Comparison] {
        guard let json = topComparisonsJSON, let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([Comparison].self, from: data) else { return [] }
        return list
    }
```
and change the initializer signature to
`public init(note: VoiceNoteRecord, verdict: Verdict, speechSeconds: Double, computedAt: Date, modelVersion: String, topComparisons: [Comparison] = [])`
with, at the end of its body:
```swift
        topComparisonsJSON = topComparisons.isEmpty ? nil
            : String(decoding: (try? JSONEncoder().encode(topComparisons)) ?? Data(), as: UTF8.self)
```

`Store/AppDatabase.swift` — register a second migration after `v1`:
```swift
        migrator.registerMigration("v2-topComparisons") { db in
            try db.alter(table: "verdict") { t in t.add(column: "topComparisonsJSON", .text) }
        }
```
and add:
```swift
    public func contact(jid: String) throws -> ContactRecord? {
        try queue.read { db in try ContactRecord.fetchOne(db, key: jid) }
    }
    public func setPinned(jid: String, _ pinned: Bool) throws {
        try queue.write { db in
            guard var c = try ContactRecord.fetchOne(db, key: jid) else { throw DatabaseError(message: "no contact \(jid)") }
            c.pinned = pinned; try c.update(db)
        }
    }
    public func setBlacklisted(jid: String, _ blacklisted: Bool) throws {
        try queue.write { db in
            guard var c = try ContactRecord.fetchOne(db, key: jid) else { throw DatabaseError(message: "no contact \(jid)") }
            c.blacklisted = blacklisted; try c.update(db)
        }
    }
    public func overrideVerdict(messagePK: Int64, kind: VerdictKind, colour: VerdictColour, reason: String, explanation: String) throws {
        try queue.write { db in
            guard var v = try VerdictRecord.fetchOne(db, key: messagePK) else { throw DatabaseError(message: "no verdict \(messagePK)") }
            v.kind = kind.rawValue; v.colour = colour.rawValue; v.reason = reason; v.explanation = explanation
            try v.update(db)
        }
    }
```

`WhatsApp/NameResolver.swift` — add to `ResolvedIdentity` (the app builds fallback identities itself):
```swift
    public init(jid: String, displayName: String, isSavedContact: Bool, pushName: String?, avatarPath: String?) {
        self.jid = jid; self.displayName = displayName; self.isSavedContact = isSavedContact
        self.pushName = pushName; self.avatarPath = avatarPath
    }
```

`Pipeline/Coordinator.swift` — in `verify`, compute `topComparisons` and pass it to `VerdictRecord`:
```swift
        // (declare before the do/catch) var top: [Comparison] = []
        // (inside the do, after `comparisons` is built) top = Array(comparisons.sorted { $0.score > $1.score }.prefix(3))
        let record = VerdictRecord(note: note, verdict: verdict, speechSeconds: speech, computedAt: now,
                                   modelVersion: engine.modelVersion, topComparisons: top)
```
and add these public methods:
```swift
    public func identity(for jid: String) throws -> ResolvedIdentity {
        if chat == nil { _ = try openStores() }
        return NameResolver.resolve(jid, tables: tables)
    }

    public func protectedJIDs() throws -> [String] {
        let pinned = try db.contacts().filter(\.pinned).map(\.jid)
        return Enroller.protectedJIDs(try db.fingerprints(), pinned: pinned, policy: config.policy)
    }

    public func setPinned(jid: String, _ pinned: Bool) throws {
        try db.setPinned(jid: jid, pinned)
    }

    /// "Report impostor": blacklist the sender, drop any fingerprint we had for them, pin the verdict red.
    public func reportImpostor(messagePK: Int64) throws {
        guard let verdict = try db.verdict(messagePK: messagePK) else { return }
        let jid = verdict.senderJID
        if try db.contact(jid: jid) == nil {
            let identity = try self.identity(for: jid)
            try db.saveContacts([ContactRecord(jid: jid, displayName: identity.displayName, isSaved: identity.isSavedContact,
                                               pinned: false, blacklisted: true, avatarPath: identity.avatarPath)])
        } else {
            try db.setBlacklisted(jid: jid, true)
        }
        try db.replaceEnrollment(jid: jid, notes: [])
        try db.saveFingerprints(try db.fingerprints().filter { $0.jid != jid })
        try db.overrideVerdict(messagePK: messagePK, kind: .impersonationSuspected, colour: .red,
                               reason: "userReported", explanation: "You reported this sender as an impostor.")
    }

    /// "This is really them": add the note to the sender's enrolment regardless of score and mark it verified.
    public func markGenuine(messagePK: Int64) async throws {
        guard let verdict = try db.verdict(messagePK: messagePK) else { return }
        let jid = verdict.senderJID
        let analysis = try await engine.analyze(url: config.locator.mediaURL(relativePath: verdict.relativeMediaPath))
        guard !analysis.embedding.isEmpty else { return }
        let candidate = EnrolledNote(jid: jid, messagePK: messagePK, embedding: analysis.embedding,
                                     speechSeconds: analysis.speechSeconds, date: verdict.date)
        var notes = try db.enrollmentNotes(jid: jid).filter { $0.messagePK != messagePK }
        notes.append(candidate)
        notes.sort { $0.date > $1.date }
        let kept = Array(notes.prefix(config.policy.maxNotes))
        try db.replaceEnrollment(jid: jid, notes: kept)
        var relaxed = config.policy
        relaxed.minNotes = 1; relaxed.minSpeechSeconds = 0
        let refreshed = Enroller.fingerprints(from: kept, policy: relaxed, modelVersion: engine.modelVersion)
        try db.saveFingerprints(try db.fingerprints().filter { $0.jid != jid } + refreshed)
        if try db.contact(jid: jid) == nil {
            let identity = try self.identity(for: jid)
            try db.saveContacts([ContactRecord(jid: jid, displayName: identity.displayName, isSaved: identity.isSavedContact,
                                               pinned: false, blacklisted: false, avatarPath: identity.avatarPath)])
        }
        try db.overrideVerdict(messagePK: messagePK, kind: .verified, colour: .green, reason: "userConfirmed",
                               explanation: "You confirmed this is really \(try identity(for: jid).displayName).")
    }
```

- [ ] **Step 4: Run tests to verify they pass**
Run: `make test` → `AppDatabaseUITests` (3) and `CoordinatorActionsTests` (3) pass; Plan 1 suites still green.
Run: `make test-integration` → `CoordinatorActionsIntegrationTests` passes.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): identity lookup, pin, report-impostor, mark-genuine, top-3 comparisons

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: AppModel (phase machine, projections, actions) + app unit-test target

**Files:**
- Create: `AntiFish/App/AppModel.swift`
- Create: `AntiFish/App/FeedItem.swift`
- Create: `AntiFish/App/Notifier.swift` (stub here; real implementation in Task 6)
- Create: `AntiFishTests/AppModelTests.swift`
- Modify: `project.yml` (add `AntiFishTests`), `Makefile` (`test-app`)

- [ ] **Step 1: Write the failing test**
`AntiFishTests/AppModelTests.swift`:
```swift
import XCTest
import AntiFishCore
@testable import AntiFish

@MainActor
final class AppModelTests: XCTestCase {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("antifish-app-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testEmptyRootNeedsWhatsApp() async throws {
        let model = AppModel(locator: ContainerLocator(root: try tempDir()), databaseURL: nil)
        await model.start()
        XCTAssertEqual(model.phase, .needsWhatsApp)
    }

    func testUnreadableChatStorageNeedsFullDiskAccess() async throws {
        let root = try tempDir()
        let db = root.appendingPathComponent("ChatStorage.sqlite")
        try Data("x".utf8).write(to: db)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: db.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: db.path) }
        let model = AppModel(locator: ContainerLocator(root: root), databaseURL: nil)
        await model.start()
        XCTAssertEqual(model.phase, .needsFullDiskAccess)
    }

    /// A readable container with no voice-note files: setup choices first, then ready with an empty feed.
    func testReadableContainerGoesThroughSetupToReady() async throws {
        let root = try tempDir()
        try Data("x".utf8).write(to: root.appendingPathComponent("ChatStorage.sqlite"))
        let model = AppModel(locator: ContainerLocator(root: root), databaseURL: nil)
        await model.start()
        XCTAssertEqual(model.phase, .setupChoices)
    }

    func testFeedItemColourAndKindDecode() {
        let record = VerdictRecord(
            note: VoiceNoteRecord(messagePK: 1, chatJID: "a@lid", senderJID: "a@lid", isFromMe: false, date: Date(), durationSeconds: 3, relativeMediaPath: "p", chatIsGroup: false),
            verdict: Verdict(kind: .takeoverSuspected, colour: .red, comparedJID: "a@lid", score: 0.1, best: nil, reason: nil, explanation: "x"),
            speechSeconds: 3, computedAt: Date(), modelVersion: "m")
        let item = FeedItem(record: record, senderName: "Abdul", chatName: nil, avatarURL: nil)
        XCTAssertEqual(item.kind, .takeoverSuspected); XCTAssertEqual(item.colour, .red); XCTAssertTrue(item.isRed)
        XCTAssertEqual(item.id, 1)
    }

    func testContactRowsSortProtectedFirstThenRecency() {
        let old = Date(timeIntervalSinceReferenceDate: 1), new = Date(timeIntervalSinceReferenceDate: 2)
        let rows = [
            ContactRow(jid: "e@lid", name: "E", isSaved: true, pinned: false, noteCount: 3, speechSeconds: 40, lastNoteDate: new, tier: .enrolled, avatarURL: nil),
            ContactRow(jid: "p1@lid", name: "P1", isSaved: true, pinned: false, noteCount: 3, speechSeconds: 40, lastNoteDate: old, tier: .protected, avatarURL: nil),
            ContactRow(jid: "n@lid", name: "N", isSaved: false, pinned: false, noteCount: 1, speechSeconds: 5, lastNoteDate: nil, tier: .needsVoice, avatarURL: nil),
            ContactRow(jid: "p2@lid", name: "P2", isSaved: true, pinned: false, noteCount: 3, speechSeconds: 40, lastNoteDate: new, tier: .protected, avatarURL: nil),
        ]
        XCTAssertEqual(AppModel.sorted(rows).map(\.jid), ["p2@lid", "p1@lid", "e@lid", "n@lid"])
    }
}
```

`project.yml` — add a target and include it in the scheme:
```yaml
  AntiFishTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - AntiFishTests
    dependencies:
      - target: AntiFish
    settings:
      base:
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/AntiFish.app/Contents/MacOS/AntiFish"
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.magnetismstudios.antifish.tests
```
In `schemes.AntiFish.build.targets` add `AntiFishTests: [test]`; in `schemes.AntiFish.test.targets` list `AntiFishTests` before `AntiFishUITests`.

Makefile addition:
```make
.PHONY: test-app
test-app: project models
	xcodebuild -project AntiFish.xcodeproj -scheme AntiFish -configuration Debug -destination 'platform=macOS' \
	  -derivedDataPath build -allowProvisioningUpdates test -only-testing:AntiFishTests
```
Run: `make test-app` → compile error `cannot find 'AppModel' in scope`.

- [ ] **Step 2: Implement**

`AntiFish/App/FeedItem.swift`:
```swift
import AntiFishCore
import Foundation

struct FeedItem: Identifiable, Hashable, Sendable {
    let record: VerdictRecord
    let senderName: String
    let chatName: String?
    let avatarURL: URL?

    var id: Int64 { record.messagePK }
    var colour: VerdictColour { VerdictColour(rawValue: record.colour) ?? .grey }
    var kind: VerdictKind { VerdictKind(rawValue: record.kind) ?? .unverifiable }
    var isRed: Bool { colour == .red }
    var day: Date { Calendar.current.startOfDay(for: record.date) }
}

struct ContactRow: Identifiable, Hashable, Sendable {
    enum Tier: Int, Sendable { case protected = 0, enrolled = 1, needsVoice = 2 }
    let jid: String
    let name: String
    let isSaved: Bool
    let pinned: Bool
    let noteCount: Int
    let speechSeconds: Double
    let lastNoteDate: Date?
    let tier: Tier
    let avatarURL: URL?
    var id: String { jid }
}

enum AppPhase: Equatable, Sendable {
    case starting, needsWhatsApp, needsFullDiskAccess, setupChoices
    case enrolling(done: Int, total: Int)
    case ready
}
```

`AntiFish/App/Notifier.swift` (stub; Task 6 replaces it):
```swift
import Foundation

@MainActor
final class Notifier {
    func requestAuthorization() async -> Bool { false }
    func notifyRed(_ item: FeedItem) {}
}
```

`AntiFish/App/AppModel.swift`:
```swift
import AntiFishCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var phase: AppPhase = .starting
    var feed: [FeedItem] = []
    var contacts: [ContactRow] = []
    var protectedJIDs: [String] = []
    var banner: String?
    var statusLine = "Starting…"
    var isPaused = false
    var isProcessing = false
    var calibration: CalibrationResult?
    var lastRed: FeedItem?
    var selectedItemID: Int64?

    let locator: ContainerLocator
    let notifier = Notifier()
    private let databaseURL: URL?
    private let modelsDirectory: URL
    private(set) var coordinator: Coordinator?
    private var db: AppDatabase?
    private var watcher: ContainerWatcher?
    private var eventTask: Task<Void, Never>?
    private var pendingPass = false
    private var identities: [String: ResolvedIdentity] = [:]

    init(locator: ContainerLocator = AppModel.defaultLocator,
         databaseURL: URL? = AppModel.defaultDatabaseURL,
         modelsDirectory: URL = AppModel.defaultModelsDirectory) {
        self.locator = locator
        self.databaseURL = databaseURL
        self.modelsDirectory = modelsDirectory
    }

    // Environment overrides let UI tests point the app at a fixture container and a throwaway database.
    static var defaultLocator: ContainerLocator {
        if let root = ProcessInfo.processInfo.environment["ANTIFISH_CONTAINER_ROOT"] {
            return ContainerLocator(root: URL(fileURLWithPath: root))
        }
        return ContainerLocator()
    }
    static var defaultDatabaseURL: URL? {
        if let path = ProcessInfo.processInfo.environment["ANTIFISH_DB_PATH"] { return URL(fileURLWithPath: path) }
        return AppDatabase.defaultURL()
    }
    static var defaultModelsDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["ANTIFISH_MODELS_DIR"] { return URL(fileURLWithPath: path) }
        return Bundle.main.resourceURL!.appendingPathComponent("Models")
    }

    // MARK: Phase machine

    func start() async {
        guard locator.isInstalled else { phase = .needsWhatsApp; statusLine = "WhatsApp Desktop not found"; return }
        guard locator.hasFullDiskAccess else { phase = .needsFullDiskAccess; statusLine = "Waiting for Full Disk Access"; return }
        do {
            let db = try self.db ?? AppDatabase(url: databaseURL)
            self.db = db
            if coordinator == nil {
                let models = ModelPaths(directory: modelsDirectory)
                let engine = try VoiceEngine(models: models, numThreads: 4)
                let coordinator = Coordinator(config: CoordinatorConfig(locator: locator, models: models), db: db, engine: engine)
                self.coordinator = coordinator
                eventTask = Task { [weak self] in
                    for await event in coordinator.events { await self?.handle(event) }
                }
            }
            if try db.setting("onboardingDone") != "1" { phase = .setupChoices; statusLine = "Finish setup"; return }
            if try db.fingerprints().isEmpty, let coordinator {
                phase = .enrolling(done: 0, total: 0); statusLine = "Building fingerprints"
                try await coordinator.enrollAll()
            }
            phase = .ready
            try await refresh()
            startWatching()
            schedulePass()
        } catch {
            banner = "AntiFish couldn't start: \(error.localizedDescription)"
            statusLine = "Error"
        }
    }

    func completeSetup() async {
        try? db?.setSetting("onboardingDone", "1")
        await start()
    }

    func rebuildFingerprints() async {
        guard let db, let coordinator else { return }
        phase = .enrolling(done: 0, total: 0)
        do {
            for jid in Set(try db.allEnrollmentNotes().map(\.jid)) { try db.replaceEnrollment(jid: jid, notes: []) }
            try db.saveFingerprints([])
            try await coordinator.enrollAll()
            phase = .ready
            try await refresh()
        } catch {
            banner = "Rebuild failed: \(error.localizedDescription)"
            phase = .ready
        }
    }

    private func handle(_ event: CoordinatorEvent) async {
        switch event {
        case .enrollmentProgress(let done, let total):
            if case .enrolling = phase { phase = .enrolling(done: done, total: total) }
        case .enrollmentFinished(let count, let protected):
            protectedJIDs = protected
            statusLine = "Watching · \(protected.count) protected · \(count) enrolled"
        case .verdict(let record):
            try? await refreshFeed()
            if let item = feed.first(where: { $0.id == record.messagePK }), item.isRed {
                lastRed = item
                notifier.notifyRed(item)
            }
        case .error(let message):
            banner = message
        }
    }

    // MARK: Projections

    func refresh() async throws {
        try await refreshFeed()
        try await refreshContacts()
        calibration = try db?.calibration()
    }

    private func identity(_ jid: String) async -> ResolvedIdentity {
        if let hit = identities[jid] { return hit }
        let resolved = (try? await coordinator?.identity(for: jid))
            ?? ResolvedIdentity(jid: jid, displayName: NameResolver.fallbackName(for: jid), isSavedContact: false, pushName: nil, avatarPath: nil)
        identities[jid] = resolved
        return resolved
    }

    func refreshFeed() async throws {
        guard let db else { return }
        var items: [FeedItem] = []
        for record in try db.verdicts(limit: 500) {
            let sender = await identity(record.senderJID)
            let chat = record.chatIsGroup ? await identity(record.chatJID).displayName : nil
            let avatar = sender.avatarPath.map { locator.mediaURL(relativePath: $0) }
                .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            items.append(FeedItem(record: record, senderName: sender.displayName, chatName: chat, avatarURL: avatar))
        }
        feed = items
    }

    func refreshContacts() async throws {
        guard let db, let coordinator else { return }
        let fingerprints = Dictionary(try db.fingerprints().map { ($0.jid, $0) }, uniquingKeysWith: { a, _ in a })
        let protected = try await coordinator.protectedJIDs()
        protectedJIDs = protected
        var rows: [ContactRow] = []
        for contact in try db.contacts() where !contact.blacklisted {
            let fp = fingerprints[contact.jid]
            let tier: ContactRow.Tier = protected.contains(contact.jid) ? .protected : (fp != nil ? .enrolled : .needsVoice)
            rows.append(ContactRow(jid: contact.jid, name: contact.displayName, isSaved: contact.isSaved, pinned: contact.pinned,
                                   noteCount: fp?.noteCount ?? 0, speechSeconds: fp?.speechSeconds ?? 0,
                                   lastNoteDate: fp?.lastNoteDate, tier: tier,
                                   avatarURL: contact.avatarPath.map { locator.mediaURL(relativePath: $0) }))
        }
        contacts = Self.sorted(rows)
        if !isPaused { statusLine = "Watching · \(protected.count) protected · \(fingerprints.count) enrolled" }
    }

    static func sorted(_ rows: [ContactRow]) -> [ContactRow] {
        rows.sorted { a, b in
            if a.tier != b.tier { return a.tier.rawValue < b.tier.rawValue }
            return (a.lastNoteDate ?? .distantPast) > (b.lastNoteDate ?? .distantPast)
        }
    }

    // MARK: Watching

    private func startWatching() {
        guard watcher == nil else { return }
        let watcher = ContainerWatcher(root: locator.root) { [weak self] in
            Task { @MainActor in self?.schedulePass() }
        }
        watcher.start()
        self.watcher = watcher
    }

    /// Runs one `processNew` pass; coalesces bursts into at most one queued follow-up pass.
    func schedulePass() {
        guard !isPaused, let coordinator else { return }
        if isProcessing { pendingPass = true; return }
        isProcessing = true
        Task { [weak self] in
            do { _ = try await coordinator.processNew() } catch { await MainActor.run { self?.banner = error.localizedDescription } }
            guard let self else { return }
            try? await self.refresh()
            self.isProcessing = false
            if self.pendingPass { self.pendingPass = false; self.schedulePass() }
        }
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        statusLine = paused ? "Paused" : statusLine
        if !paused { schedulePass() }
    }

    // MARK: Actions

    func markGenuine(_ item: FeedItem) async {
        try? await coordinator?.markGenuine(messagePK: item.id)
        try? await refresh()
    }

    func reportImpostor(_ item: FeedItem) async {
        try? await coordinator?.reportImpostor(messagePK: item.id)
        try? await refresh()
    }

    func togglePin(_ row: ContactRow) async {
        try? await coordinator?.setPinned(jid: row.jid, !row.pinned)
        try? await refreshContacts()
    }

    func remove(_ row: ContactRow) async {
        guard let db else { return }
        try? db.setBlacklisted(jid: row.jid, true)
        try? db.saveFingerprints((try? db.fingerprints())?.filter { $0.jid != row.jid } ?? [])
        try? await refreshContacts()
    }

    func recalibrate() {
        guard let db else { return }
        let result = Calibrator.calibrate(notes: (try? db.allEnrollmentNotes()) ?? [])
        try? db.saveCalibration(result)
        calibration = result
    }

    func mediaURL(for item: FeedItem) -> URL {
        locator.mediaURL(relativePath: item.record.relativeMediaPath)
    }
}
```

- [ ] **Step 3: Run tests to verify they pass**
Run: `make test-app` → `AppModelTests` 5 tests pass.

- [ ] **Step 4: Commit**
```bash
git add project.yml Makefile AntiFish AntiFishTests
git commit -m "feat(app): AppModel phase machine, feed/contact projections, actions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Onboarding (WhatsApp → Full Disk Access → setup choices → enrolling)

**Files:**
- Create: `AntiFish/Features/Onboarding/OnboardingView.swift`
- Create: `AntiFish/Features/Onboarding/PermissionProbe.swift`
- Create: `AntiFish/Features/Onboarding/LoginItem.swift`
- Create: `AntiFish/App/RootView.swift`
- Modify: `AntiFish/App/AntiFishApp.swift`
- Test: `AntiFishUITests/OnboardingTests.swift`

- [ ] **Step 1: Write the failing test**
```swift
import XCTest

final class OnboardingTests: XCTestCase {
    private func launch(root: URL) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ANTIFISH_CONTAINER_ROOT"] = root.path
        app.launchEnvironment["ANTIFISH_DB_PATH"] = root.appendingPathComponent("app.sqlite").path
        app.launch()
        return app
    }
    private func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("antifish-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testMissingWhatsAppShowsInstallStep() throws {
        let app = launch(root: try tempRoot())
        XCTAssertTrue(app.staticTexts["onboarding.needsWhatsApp"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["onboarding.checkAgain"].exists)
    }

    func testFullDiskAccessStepAdvancesWhenReadable() throws {
        let root = try tempRoot()
        let db = root.appendingPathComponent("ChatStorage.sqlite")
        try Data("x".utf8).write(to: db)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: db.path)
        let app = launch(root: root)
        XCTAssertTrue(app.staticTexts["onboarding.needsFDA"].waitForExistence(timeout: 10))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: db.path)
        XCTAssertTrue(app.staticTexts["onboarding.setup"].waitForExistence(timeout: 10))
        app.buttons["onboarding.continue"].click()
        XCTAssertTrue(app.staticTexts["antifish.ready"].waitForExistence(timeout: 30))
    }
}
```
Run: `make test-ui` → `OnboardingTests` fail on the first `waitForExistence`.

- [ ] **Step 2: Implement**

`PermissionProbe.swift`:
```swift
import AntiFishCore
import AppKit

enum PermissionProbe {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    static func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    /// Re-probes every 1.2 s (the grant takes effect without a relaunch) until readable or cancelled.
    static func waitUntilReadable(_ locator: ContainerLocator) async {
        while !Task.isCancelled, !locator.hasFullDiskAccess {
            try? await Task.sleep(for: .seconds(1.2))
        }
    }
}
```

`LoginItem.swift`:
```swift
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("LoginItem: \(error.localizedDescription)")
        }
    }
}
```

`OnboardingView.swift`:
```swift
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var notificationsOn = true
    @State private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.tint)
            Text("AntiFish").font(.largeTitle.weight(.semibold))
            Group {
                switch model.phase {
                case .needsWhatsApp: needsWhatsApp
                case .needsFullDiskAccess: needsFullDiskAccess
                case .setupChoices: setupChoices
                case .enrolling(let done, let total): enrolling(done: done, total: total)
                default: ProgressView()
                }
            }
            .frame(maxWidth: 460)
        }
        .padding(48)
        .frame(minWidth: 600, minHeight: 480)
    }

    private var needsWhatsApp: some View {
        StepCard(title: "WhatsApp Desktop not found", identifier: "onboarding.needsWhatsApp",
                 body: "Install WhatsApp for Mac and link it to your phone. AntiFish reads voice notes from WhatsApp's local storage on this Mac and never sends them anywhere.") {
            Button("Check again") { Task { await model.start() } }
                .accessibilityIdentifier("onboarding.checkAgain")
                .keyboardShortcut(.defaultAction)
        }
    }

    private var needsFullDiskAccess: some View {
        StepCard(title: "Allow Full Disk Access", identifier: "onboarding.needsFDA",
                 body: "macOS keeps WhatsApp's files private to WhatsApp. Turn on AntiFish under System Settings → Privacy & Security → Full Disk Access. This screen advances by itself once access is granted.") {
            Button("Open System Settings") { PermissionProbe.openFullDiskAccessSettings() }
                .keyboardShortcut(.defaultAction)
        }
        .task {
            await PermissionProbe.waitUntilReadable(model.locator)
            await model.start()
        }
    }

    private var setupChoices: some View {
        StepCard(title: "Two choices", identifier: "onboarding.setup",
                 body: "AntiFish runs quietly in the menu bar. Verified notes never interrupt you; only a suspected impersonation does.") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Notify me when a voice note looks like an impersonation", isOn: $notificationsOn)
                Toggle("Launch AntiFish at login", isOn: $launchAtLogin)
                HStack {
                    Spacer()
                    Button("Continue") {
                        Task {
                            if notificationsOn { _ = await model.notifier.requestAuthorization() }
                            LoginItem.set(enabled: launchAtLogin)
                            await model.completeSetup()
                        }
                    }
                    .accessibilityIdentifier("onboarding.continue")
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func enrolling(done: Int, total: Int) -> some View {
        StepCard(title: "Building voice fingerprints", identifier: "onboarding.enrolling",
                 body: "Listening to the voice notes already on this Mac. This runs once and takes a few minutes.") {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: total > 0 ? Double(done) / Double(total) : nil)
                Text(total > 0 ? "\(done) of \(total) notes" : "Preparing…").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct StepCard<Actions: View>: View {
    let title: String
    let identifier: String
    let body_: String
    @ViewBuilder let actions: Actions

    init(title: String, identifier: String, body: String, @ViewBuilder actions: () -> Actions) {
        self.title = title; self.identifier = identifier; self.body_ = body; self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.weight(.semibold)).accessibilityIdentifier(identifier)
            Text(body_).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
```

`RootView.swift` (the `.ready` branch is replaced by `MainView` in Task 4):
```swift
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.phase == .ready {
                Text("Ready").accessibilityIdentifier("antifish.ready")
            } else {
                OnboardingView()
            }
        }
        .task { await model.start() }
    }
}
```

`AntiFishApp.swift`:
```swift
import SwiftUI

@main
struct AntiFishApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("AntiFish") {
            RootView()
                .environment(model)
                .accessibilityIdentifier("antifish.rootMarker")
        }
        .defaultSize(width: 900, height: 620)
    }
}
```
Adjust `LaunchTests` from Task 0 to look for `app.otherElements["antifish.rootMarker"]` or, simpler, keep the identifier on a hidden `Text` inside `RootView`: add `.overlay(alignment: .topLeading) { Text("").accessibilityIdentifier("antifish.rootMarker").frame(width: 0, height: 0) }` to `RootView`'s `Group`.

- [ ] **Step 3: Run tests to verify they pass**
Run: `make test-ui` → `LaunchTests` and `OnboardingTests` pass (the second onboarding test builds an in-memory-like temp DB; the fixture container has no notes so enrolment finishes immediately).

- [ ] **Step 4: Frame-verify** (after Task 10 installs the harness, re-run for this transition): the Full Disk Access → setup card swap must report SMOOTH.

- [ ] **Step 5: Commit**
```bash
git add AntiFish AntiFishUITests
git commit -m "feat(app): onboarding flow with Full Disk Access polling and setup choices

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Feed window (list, verdict pill, detail pane, playback)

**Files:**
- Create: `AntiFish/Features/Feed/MainView.swift`, `FeedList.swift`, `FeedRow.swift`, `VerdictPill.swift`, `DetailPane.swift`, `ScoreBar.swift`, `NotePlayer.swift`, `Avatar.swift`, `HeaderBar.swift`
- Modify: `AntiFish/App/RootView.swift` (`.ready` → `MainView`), `AntiFish/App/AppModel.swift` (`name(for:)`)
- Test: `AntiFishUITests/FeedTests.swift`

- [ ] **Step 1: Write the failing test** (real data; waits through first-run enrolment if the app database is empty)
```swift
import XCTest

final class FeedTests: XCTestCase {
    func testFeedShowsRowsAndDetail() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["feed.list"].waitForExistence(timeout: 600))
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'feed.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 120))
        row.click()
        XCTAssertTrue(app.descendants(matching: .any)["detail.pane"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["verdict.pill"].firstMatch.exists)
        XCTAssertTrue(app.buttons["detail.genuine"].exists)
        XCTAssertTrue(app.buttons["detail.impostor"].exists)
    }
}
```
Run: `make test-ui` → fails: `feed.list` never appears (RootView still shows the "Ready" text).

- [ ] **Step 2: Implement**

`AppModel.swift` addition:
```swift
    func name(for jid: String) -> String {
        contacts.first { $0.jid == jid }?.name ?? identities[jid]?.displayName ?? NameResolver.fallbackName(for: jid)
    }
```

`Avatar.swift`:
```swift
import AppKit
import SwiftUI

struct Avatar: View {
    let url: URL?
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(.tint.opacity(0.18))
                    Text(initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.tint)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
```

`VerdictPill.swift`:
```swift
import AntiFishCore
import SwiftUI

struct VerdictPill: View {
    let kind: VerdictKind
    let colour: VerdictColour

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
            .accessibilityIdentifier("verdict.pill")
            .accessibilityLabel(title)
    }

    var title: String {
        switch kind {
        case .verified: "Verified"
        case .takeoverSuspected: "Possible takeover"
        case .impersonationSuspected: "Possible impersonation"
        case .matchesUnsavedNumber: "Known voice, new number"
        case .unknownVoice: "Unknown voice"
        case .unverifiable: "Unverified"
        case .unclear: "Unclear"
        }
    }

    private var symbol: String {
        switch kind {
        case .verified: "checkmark.seal.fill"
        case .takeoverSuspected, .impersonationSuspected: "exclamationmark.triangle.fill"
        case .matchesUnsavedNumber: "person.crop.circle.badge.questionmark"
        case .unknownVoice: "person.fill.questionmark"
        case .unverifiable: "questionmark.circle"
        case .unclear: "circle.dotted"
        }
    }

    private var tint: Color {
        switch colour {
        case .green: .green
        case .red: .red
        case .amber: .orange
        case .grey: Color.secondary
        }
    }
}
```

`FeedRow.swift`:
```swift
import SwiftUI

struct FeedRow: View {
    let item: FeedItem

    var body: some View {
        HStack(spacing: 12) {
            Avatar(url: item.avatarURL, name: item.senderName, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.senderName).font(.body.weight(.semibold)).lineLimit(1)
                    if let chat = item.chatName {
                        Text("in \(chat)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(item.record.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    VerdictPill(kind: item.kind, colour: item.colour)
                    Text(Duration.seconds(item.record.durationSeconds).formatted(.time(pattern: .minuteSecond)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(item.record.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
```

`FeedList.swift`:
```swift
import SwiftUI

struct FeedList: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Int64?

    private var groups: [(day: Date, items: [FeedItem])] {
        Dictionary(grouping: model.feed, by: \.day)
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, items: $0.value) }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(groups, id: \.day) { group in
                Section(group.day.formatted(date: .abbreviated, time: .omitted)) {
                    ForEach(group.items) { item in
                        FeedRow(item: item)
                            .tag(item.id)
                            .accessibilityIdentifier("feed.row.\(item.id)")
                    }
                }
            }
        }
        .accessibilityIdentifier("feed.list")
        .overlay {
            if model.feed.isEmpty {
                ContentUnavailableView("No voice notes yet", systemImage: "waveform",
                                       description: Text("Incoming voice notes appear here with a verdict."))
            }
        }
        .animation(.snappy(duration: 0.25), value: model.feed.map(\.id))
    }
}
```

`NotePlayer.swift`:
```swift
import AVFoundation
import Observation

@MainActor
@Observable
final class NotePlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private(set) var isPlaying = false
    private(set) var currentURL: URL?

    func toggle(url: URL) {
        if isPlaying, currentURL == url { player?.pause(); isPlaying = false; return }
        if currentURL != url {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            currentURL = url
        }
        player?.play()
        isPlaying = player?.isPlaying ?? false
    }

    func stop() {
        player?.stop()
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}
```

`ScoreBar.swift`:
```swift
import AntiFishCore
import SwiftUI

struct ScoreBar: View {
    let score: Float
    let thresholds: Thresholds

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Similarity \(score, format: .number.precision(.fractionLength(2)))").font(.callout.weight(.medium))
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 8)
                    Capsule().fill(.red.opacity(0.25)).frame(width: w * CGFloat(clamp(thresholds.reject)), height: 8)
                    Capsule().fill(.green.opacity(0.25))
                        .frame(width: w * CGFloat(1 - clamp(thresholds.match)), height: 8)
                        .offset(x: w * CGFloat(clamp(thresholds.match)))
                    Circle().fill(.primary).frame(width: 14, height: 14)
                        .offset(x: w * CGFloat(clamp(score)) - 7)
                        .animation(.spring(duration: 0.35), value: score)
                }
                .frame(height: 14)
            }
            .frame(height: 14)
            HStack {
                Text("mismatch ≤ \(thresholds.reject, format: .number.precision(.fractionLength(2)))")
                Spacer()
                Text(thresholds.calibrated ? "calibrated on your contacts" : "default thresholds")
                Spacer()
                Text("match ≥ \(thresholds.match, format: .number.precision(.fractionLength(2)))")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func clamp(_ v: Float) -> Float { min(max(v, 0), 1) }
}
```

`DetailPane.swift`:
```swift
import AntiFishCore
import SwiftUI

struct DetailPane: View {
    @Environment(AppModel.self) private var model
    @State private var player = NotePlayer()
    let item: FeedItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Avatar(url: item.avatarURL, name: item.senderName, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.senderName).font(.title2.weight(.semibold))
                        Text(subtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        player.toggle(url: model.mediaURL(for: item))
                    } label: {
                        Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("detail.play")
                }

                VStack(alignment: .leading, spacing: 10) {
                    VerdictPill(kind: item.kind, colour: item.colour)
                    Text(item.record.explanation).font(.body).fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let score = item.record.score {
                    ScoreBar(score: Float(score), thresholds: model.calibration?.thresholds ?? Thresholds())
                }

                if !item.record.topComparisons.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Closest fingerprints").font(.callout.weight(.medium))
                        ForEach(item.record.topComparisons, id: \.jid) { c in
                            HStack {
                                Text(model.name(for: c.jid))
                                Spacer()
                                Text(c.score, format: .number.precision(.fractionLength(2))).monospacedDigit()
                            }
                            .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Button("This is really them") { Task { await model.markGenuine(item) } }
                        .accessibilityIdentifier("detail.genuine")
                    Button("Report impostor", role: .destructive) { Task { await model.reportImpostor(item) } }
                        .accessibilityIdentifier("detail.impostor")
                }

                Text("Speech \(item.record.speechSeconds, format: .number.precision(.fractionLength(1))) s · \(item.record.modelVersion)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(24)
        }
        .accessibilityIdentifier("detail.pane")
        .onChange(of: item.id) { player.stop() }
        .onDisappear { player.stop() }
    }

    private var subtitle: String {
        var parts = [item.record.date.formatted(date: .abbreviated, time: .shortened)]
        if let chat = item.chatName { parts.append("in \(chat)") }
        return parts.joined(separator: " · ")
    }
}
```

`HeaderBar.swift`:
```swift
import SwiftUI

struct HeaderBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(model.isPaused ? .orange : (model.lastRed == nil ? .green : .red)).frame(width: 8, height: 8)
                Text(model.statusLine).font(.callout)
                if model.isProcessing { ProgressView().controlSize(.small); Text("analysing…").font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .accessibilityIdentifier("header.status")
            if let banner = model.banner {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(banner).lineLimit(2)
                    Spacer()
                    Button("Dismiss") { model.banner = nil }.buttonStyle(.borderless)
                }
                .font(.callout).padding(.horizontal, 16).padding(.vertical, 8)
                .background(.yellow.opacity(0.18))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(.bar)
        .animation(.snappy(duration: 0.25), value: model.banner)
    }
}
```

`MainView.swift`:
```swift
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            FeedList(selection: $model.selectedItemID)
                .navigationSplitViewColumnWidth(min: 340, ideal: 420)
        } detail: {
            if let item = model.feed.first(where: { $0.id == model.selectedItemID }) {
                DetailPane(item: item)
                    .id(item.id)
                    .transition(.opacity.combined(with: .offset(x: 12)))
            } else {
                ContentUnavailableView("Select a voice note", systemImage: "waveform.badge.magnifyingglass",
                                       description: Text("The verdict, similarity score and actions show here."))
            }
        }
        .animation(.snappy(duration: 0.25), value: model.selectedItemID)
        .safeAreaInset(edge: .top, spacing: 0) { HeaderBar() }
        .toolbar {
            ToolbarItem {
                Button { openWindow(id: "contacts") } label: { Label("Contacts", systemImage: "person.2") }
                    .accessibilityIdentifier("main.contacts")
            }
            ToolbarItem {
                Button { model.setPaused(!model.isPaused) } label: {
                    Label(model.isPaused ? "Resume" : "Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                }
                .accessibilityIdentifier("main.pause")
            }
        }
    }
}
```

`RootView.swift` — replace the `.ready` branch with `MainView()`; keep the hidden `antifish.rootMarker` text.

- [ ] **Step 3: Run tests to verify they pass**
Run: `make test-ui` → `FeedTests` passes (first run may spend minutes in enrolment; the 600 s wait covers it).

- [ ] **Step 4: Frame-verify** (Task 10 harness): row selection → detail pane transition and the banner slide must report SMOOTH.

- [ ] **Step 5: Commit**
```bash
git add AntiFish AntiFishUITests
git commit -m "feat(app): voice-note feed with verdict pills, detail pane, playback and score bar

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Contacts window

**Files:**
- Create: `AntiFish/Features/Contacts/ContactsView.swift`, `ContactRowView.swift`
- Modify: `AntiFish/App/AntiFishApp.swift` (add the `contacts` window scene)
- Test: `AntiFishUITests/ContactsTests.swift`

- [ ] **Step 1: Write the failing test**
```swift
import XCTest

final class ContactsTests: XCTestCase {
    func testContactsWindowListsProtectedContacts() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["feed.list"].waitForExistence(timeout: 600))
        app.buttons["main.contacts"].click()
        XCTAssertTrue(app.descendants(matching: .any)["contacts.list"].waitForExistence(timeout: 10))
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'contacts.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Protected ·'")).firstMatch.exists)
    }
}
```
Run: `make test-ui` → fails: `main.contacts` opens nothing.

- [ ] **Step 2: Implement**

`ContactRowView.swift`:
```swift
import SwiftUI

struct ContactRowView: View {
    @Environment(AppModel.self) private var model
    let row: ContactRow

    var body: some View {
        HStack(spacing: 12) {
            Avatar(url: row.avatarURL, name: row.name, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name).font(.body.weight(.medium))
                    if !row.isSaved { Text("not in your contacts").font(.caption).foregroundStyle(.secondary) }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if row.tier != .needsVoice {
                Button { Task { await model.togglePin(row) } } label: {
                    Image(systemName: row.pinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.borderless)
                .help(row.pinned ? "Unpin" : "Pin as protected")
                .accessibilityIdentifier("contacts.pin.\(row.jid)")
            }
            Button(role: .destructive) { Task { await model.remove(row) } } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove and stop enrolling")
            .accessibilityIdentifier("contacts.remove.\(row.jid)")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contacts.row.\(row.jid)")
    }

    private var detail: String {
        guard row.tier != .needsVoice else { return "\(row.noteCount) notes so far" }
        let last = row.lastNoteDate?.formatted(date: .abbreviated, time: .omitted) ?? "—"
        return "\(row.noteCount) notes · \(Int(row.speechSeconds)) s of speech · last \(last)"
    }
}
```

`ContactsView.swift`:
```swift
import SwiftUI

struct ContactsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            section("Protected", .protected, footer: "Notification-eligible. Pin someone to keep them here.")
            section("Enrolled", .enrolled, footer: nil)
            section("Needs more voice", .needsVoice, footer: "Fewer than 3 notes or under 30 s of speech on this Mac so far.")
        }
        .accessibilityIdentifier("contacts.list")
        .frame(minWidth: 560, minHeight: 440)
        .animation(.snappy(duration: 0.25), value: model.contacts.map(\.id))
        .task { try? await model.refreshContacts() }
    }

    @ViewBuilder
    private func section(_ title: String, _ tier: ContactRow.Tier, footer: String?) -> some View {
        let rows = model.contacts.filter { $0.tier == tier }
        Section {
            ForEach(rows) { ContactRowView(row: $0) }
        } header: {
            Text("\(title) · \(rows.count)")
        } footer: {
            if let footer { Text(footer).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
```

`AntiFishApp.swift` — add after the `WindowGroup`:
```swift
        Window("Contacts", id: "contacts") {
            ContactsView().environment(model)
        }
        .defaultSize(width: 620, height: 520)
```

- [ ] **Step 3: Run tests to verify they pass**
Run: `make test-ui` → `ContactsTests` passes.

- [ ] **Step 4: Frame-verify** (Task 10): pin/unpin moving a row between sections must report SMOOTH.

- [ ] **Step 5: Commit**
```bash
git add AntiFish AntiFishUITests
git commit -m "feat(app): contacts window with protected, enrolled and needs-more-voice tiers

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Menu bar extra, notifications (red only), notification click-through

**Files:**
- Modify: `AntiFish/App/Notifier.swift` (replace the stub)
- Create: `AntiFish/App/AppDelegate.swift`
- Create: `AntiFish/Features/MenuBar/MenuBarView.swift`
- Modify: `AntiFish/App/AntiFishApp.swift`, `AntiFish/App/RootView.swift`
- Test: `AntiFishTests/NotifierTests.swift`, `AntiFishUITests/MenuBarTests.swift`

- [ ] **Step 1: Write the failing tests**
`AntiFishTests/NotifierTests.swift`:
```swift
import XCTest
import AntiFishCore
@testable import AntiFish

@MainActor
final class NotifierTests: XCTestCase {
    private func item(kind: VerdictKind, colour: VerdictColour) -> FeedItem {
        let note = VoiceNoteRecord(messagePK: 42, chatJID: "x@lid", senderJID: "x@lid", isFromMe: false, date: Date(), durationSeconds: 5, relativeMediaPath: "p", chatIsGroup: false)
        let verdict = Verdict(kind: kind, colour: colour, comparedJID: "a@lid", score: 0.1, best: nil, reason: nil, explanation: "Profile name says Abdul, but the voice does not match Abdul's fingerprint.")
        return FeedItem(record: VerdictRecord(note: note, verdict: verdict, speechSeconds: 4, computedAt: Date(), modelVersion: "m"), senderName: "Abdul (unsaved)", chatName: nil, avatarURL: nil)
    }

    func testImpersonationContent() {
        let content = Notifier.content(for: item(kind: .impersonationSuspected, colour: .red))
        XCTAssertEqual(content.title, "Possible impersonation")
        XCTAssertTrue(content.body.hasPrefix("Abdul (unsaved): "))
        XCTAssertEqual(content.userInfo["messagePK"] as? Int64, 42)
    }

    func testTakeoverTitle() {
        XCTAssertEqual(Notifier.content(for: item(kind: .takeoverSuspected, colour: .red)).title, "Possible account takeover")
    }

    func testOnlyRedVerdictsNotify() {
        XCTAssertTrue(Notifier.shouldNotify(item(kind: .impersonationSuspected, colour: .red)))
        XCTAssertFalse(Notifier.shouldNotify(item(kind: .verified, colour: .green)))
        XCTAssertFalse(Notifier.shouldNotify(item(kind: .matchesUnsavedNumber, colour: .amber)))
    }
}
```
`AntiFishUITests/MenuBarTests.swift`:
```swift
import XCTest

final class MenuBarTests: XCTestCase {
    func testMenuBarExtraOpensPopover() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["feed.list"].waitForExistence(timeout: 600))
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        statusItem.click()
        XCTAssertTrue(app.buttons["menubar.open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["menubar.quit"].exists)
    }
}
```
Run: `make test-app` → compile error `type 'Notifier' has no member 'content'`; `make test-ui` → no status item.

- [ ] **Step 2: Implement**

`Notifier.swift`:
```swift
import Foundation
import UserNotifications

@MainActor
final class Notifier {
    private let center = UNUserNotificationCenter.current()
    private(set) var isAuthorized = false

    func requestAuthorization() async -> Bool {
        do { isAuthorized = try await center.requestAuthorization(options: [.alert, .sound]) }
        catch { isAuthorized = false }
        return isAuthorized
    }

    func refreshAuthorization() async {
        isAuthorized = await center.notificationSettings().authorizationStatus == .authorized
    }

    static func shouldNotify(_ item: FeedItem) -> Bool { item.isRed }

    static func content(for item: FeedItem) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = item.kind == .takeoverSuspected ? "Possible account takeover" : "Possible impersonation"
        content.body = "\(item.senderName): \(item.record.explanation)"
        content.sound = .default
        content.userInfo = ["messagePK": item.id]
        return content
    }

    /// Spec section 9: only red verdicts interrupt the user.
    func notifyRed(_ item: FeedItem) {
        guard Self.shouldNotify(item) else { return }
        center.add(UNNotificationRequest(identifier: "verdict-\(item.id)", content: Self.content(for: item), trigger: nil))
    }
}
```

`AppDelegate.swift` (routes a notification click to the verdict):
```swift
import AppKit
import UserNotifications

extension Notification.Name {
    static let antifishOpenVerdict = Notification.Name("antifish.openVerdict")
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let pk = response.notification.request.content.userInfo["messagePK"] as? Int64 else { return }
        await MainActor.run {
            NSApp.activate()
            NotificationCenter.default.post(name: .antifishOpenVerdict, object: nil, userInfo: ["messagePK": pk])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
```

`MenuBarView.swift`:
```swift
import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(model.statusLine).font(.callout.weight(.medium)).lineLimit(1)
                Spacer()
            }
            Divider()
            if model.feed.isEmpty {
                Text("No voice notes yet").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.feed.prefix(3)) { item in
                Button {
                    model.selectedItemID = item.id
                    openMain()
                } label: {
                    HStack(spacing: 8) {
                        VerdictPill(kind: item.kind, colour: item.colour)
                        Text(item.senderName).lineLimit(1)
                        Spacer()
                        Text(item.record.date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            Divider()
            HStack {
                Button("Open AntiFish") { openMain() }.accessibilityIdentifier("menubar.open")
                Spacer()
                Button(model.isPaused ? "Resume" : "Pause") { model.setPaused(!model.isPaused) }
                    .accessibilityIdentifier("menubar.pause")
                Button("Quit") { NSApp.terminate(nil) }.accessibilityIdentifier("menubar.quit")
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 340)
    }

    private var dot: Color { model.isPaused ? .orange : (model.lastRed == nil ? .green : .red) }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
```

`AntiFishApp.swift` (complete):
```swift
import SwiftUI

@main
struct AntiFishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("AntiFish", id: "main") {
            RootView().environment(model)
        }
        .defaultSize(width: 900, height: 620)

        Window("Contacts", id: "contacts") {
            ContactsView().environment(model)
        }
        .defaultSize(width: 620, height: 520)

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            Image(systemName: model.lastRed == nil ? "waveform.badge.magnifyingglass" : "waveform.badge.exclamationmark")
                .accessibilityIdentifier("antifish.menubar")
        }
        .menuBarExtraStyle(.window)
    }
}
```

`RootView.swift` — add to the outer `Group`:
```swift
        .onReceive(NotificationCenter.default.publisher(for: .antifishOpenVerdict)) { note in
            if let pk = note.userInfo?["messagePK"] as? Int64 { model.selectedItemID = pk }
        }
```

- [ ] **Step 3: Run tests to verify they pass**
Run: `make test-app` → `NotifierTests` 3 tests pass. Run: `make test-ui` → `MenuBarTests` passes.

- [ ] **Step 4: Frame-verify** (Task 10): the menu bar popover open/close must report SMOOTH.

- [ ] **Step 5: Commit**
```bash
git add AntiFish AntiFishTests AntiFishUITests
git commit -m "feat(app): menu bar extra, red-only notifications with click-through

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Re-link detection and history status

**Files:**
- Modify: `AntiFish/App/AppModel.swift`
- Test: `AntiFishTests/AppModelRelinkTests.swift`

- [ ] **Step 1: Write the failing test**
```swift
import XCTest
import AntiFishCore
@testable import AntiFish

@MainActor
final class AppModelRelinkTests: XCTestCase {
    func testChangedContainerCreationDateFlagsRebuild() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("antifish-relink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("ChatStorage.sqlite"))
        let dbURL = root.appendingPathComponent("app.sqlite")
        let db = try AppDatabase(url: dbURL)
        try db.setSetting("onboardingDone", "1")
        try db.setSetting("containerCreated", "1")   // a long time ago
        try db.saveFingerprints([Fingerprint(jid: "a@lid", centroid: [1, 0], noteCount: 3, speechSeconds: 40, lastNoteDate: Date(), modelVersion: "m")])
        let model = AppModel(locator: ContainerLocator(root: root), databaseURL: dbURL)
        await model.start()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(model.needsRebuild)
        XCTAssertNotNil(model.banner)
        XCTAssertNotEqual(try db.setting("containerCreated"), "1")
    }

    func testFreshInstallDoesNotFlagRebuild() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("antifish-fresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("ChatStorage.sqlite"))
        let dbURL = root.appendingPathComponent("app.sqlite")
        try AppDatabase(url: dbURL).setSetting("onboardingDone", "1")
        let model = AppModel(locator: ContainerLocator(root: root), databaseURL: dbURL)
        await model.start()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(model.needsRebuild)
    }
}
```
Run: `make test-app` → compile error `has no member 'needsRebuild'`.

- [ ] **Step 2: Implement**
In `AppModel`: add `var needsRebuild = false` and this method, called in `start()` right after `self.db = db`:
```swift
    /// A re-linked WhatsApp gets a new ChatStorage.sqlite; old fingerprints still apply, but the
    /// user is told so they can rebuild (section 10).
    private func checkRelink(_ db: AppDatabase) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: locator.chatStorageURL.path)
        let created = (attributes[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0
        if let stored = try db.setting("containerCreated"), let previous = Double(stored),
           abs(previous - created) > 1, !(try db.fingerprints().isEmpty) {
            needsRebuild = true
            banner = "WhatsApp was re-linked on this Mac. Fingerprints may be stale — rebuild them from Settings."
        }
        try db.setSetting("containerCreated", String(created))
    }
```
and in `rebuildFingerprints()` set `needsRebuild = false; banner = nil` on success. In `schedulePass()` set `statusLine = "Analysing voice notes…"` while `isProcessing` and restore it through `refreshContacts()` afterwards (already the case).

- [ ] **Step 3: Run tests to verify they pass**
Run: `make test-app` → `AppModelRelinkTests` 2 tests pass; earlier `AppModelTests` still pass.

- [ ] **Step 4: Commit**
```bash
git add AntiFish AntiFishTests
git commit -m "feat(app): detect WhatsApp re-link and offer fingerprint rebuild

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Settings → Calibration, General, Privacy

**Files:**
- Create: `AntiFish/Features/Settings/SettingsView.swift`
- Modify: `AntiFish/App/AntiFishApp.swift` (add the `Settings` scene)
- Test: `AntiFishUITests/SettingsTests.swift`

- [ ] **Step 1: Write the failing test**
```swift
import XCTest

final class SettingsTests: XCTestCase {
    func testSettingsShowsCalibration() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["feed.list"].waitForExistence(timeout: 600))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["settings.form"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settings.recalibrate"].exists)
        XCTAssertTrue(app.buttons["settings.rebuild"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'threshold' OR label CONTAINS 'threshold'")).firstMatch.exists)
    }
}
```
Run: `make test-ui` → fails: ⌘, opens nothing.

- [ ] **Step 2: Implement**
`SettingsView.swift`:
```swift
import AntiFishCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var notificationsAuthorized = false

    var body: some View {
        Form {
            Section("Calibration") {
                if let c = model.calibration {
                    LabeledContent("Status", value: c.thresholds.calibrated
                                   ? "Calibrated on \(c.contactCount) contacts"
                                   : "Default thresholds — needs 5 or more enrolled contacts")
                    LabeledContent("Match threshold", value: fmt(c.thresholds.match))
                    LabeledContent("Mismatch threshold", value: fmt(c.thresholds.reject))
                    LabeledContent("Genuine median", value: fmt(c.genuineMedian))
                    LabeledContent("Impostor median", value: fmt(c.impostorMedian))
                    LabeledContent("Last calibrated", value: c.calibratedAt.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("Not calibrated yet.").foregroundStyle(.secondary)
                }
                HStack {
                    Button("Recalibrate") { model.recalibrate() }.accessibilityIdentifier("settings.recalibrate")
                    Button(model.needsRebuild ? "Rebuild fingerprints (recommended)" : "Rebuild fingerprints") {
                        Task { await model.rebuildFingerprints() }
                    }
                    .accessibilityIdentifier("settings.rebuild")
                    .tint(model.needsRebuild ? .orange : nil)
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in LoginItem.set(enabled: enabled) }
                LabeledContent("Notifications", value: notificationsAuthorized
                               ? "On — only for possible impersonations"
                               : "Off — enable AntiFish in System Settings → Notifications")
            }
            Section("Privacy") {
                Text("Everything runs on this Mac. AntiFish reads WhatsApp's local voice notes, keeps fingerprints in ~/Library/Application Support/AntiFish, and never uses the network.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .accessibilityIdentifier("settings.form")
        .task {
            await model.notifier.refreshAuthorization()
            notificationsAuthorized = model.notifier.isAuthorized
        }
    }

    private func fmt(_ v: Float) -> String { v.formatted(.number.precision(.fractionLength(2))) }
}
```
`AntiFishApp.swift` — add:
```swift
        Settings {
            SettingsView().environment(model)
        }
```

- [ ] **Step 3: Run tests to verify they pass**
Run: `make test-ui` → `SettingsTests` passes.

- [ ] **Step 4: Commit**
```bash
git add AntiFish AntiFishUITests
git commit -m "feat(app): settings with calibration details, rebuild, login item and notification status

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: intentful-ui loop — every transition measured SMOOTH

**Files:**
- Create (by the installer): `verify/`, `scripts/doctor.sh`, `prompts/`
- Create: `verify/drive_mac.sh`
- Modify: `Makefile` (loop targets), `testing.md`

- [ ] **Step 1: Install the harness and the missing tool**
```bash
bash /Users/burhankhatri/.claude/skills/intentful-ui/scripts/install.sh .
brew install cliclick
python3 -m pip install -r verify/requirements.txt
```
Expected: `+ verify`, `+ scripts/doctor.sh`, `+ prompts`, `skip (exists): Makefile`; `cliclick` on PATH. Grant the terminal **Screen Recording** and **Accessibility** in System Settings → Privacy & Security (ffmpeg records the screen; osascript pins the window; cliclick injects clicks).

- [ ] **Step 2: Failing check** — the grader has nothing to grade yet
Run: `make diff`
Expected: `make: *** No rule to make target 'diff'`.

- [ ] **Step 3: Merge the loop into the Makefile**
```make
# ── intentful-ui perception loop (harness lives in verify/, installed from the skill) ──
CAPTURE      ?= build/capture
FPS          ?= 60
DURATION     ?= 14
SCREEN_INDEX ?= 1

.PHONY: doctor record-mac diff loop-mac
doctor:
	@bash scripts/doctor.sh

record-mac: build
	APP_NAME=AntiFish DERIVED=build OUT=$(CAPTURE) DURATION=$(DURATION) FPS=$(FPS) SCREEN_INDEX=$(SCREEN_INDEX) \
	  bash verify/record_mac.sh

diff:
	python3 verify/frame_diff.py $(CAPTURE)/frames --fps $(FPS) --out $(CAPTURE)/flagged

# build -> launch + pin window at (120,120) -> record while verify/drive_mac.sh clicks -> grade frames
loop-mac: record-mac diff
	@echo "SMOOTH ✓  ($(CAPTURE)/frames graded; flagged frames, if any, in $(CAPTURE)/flagged)"
```

- [ ] **Step 4: Calibrate click coordinates, then write the drive script**
The recorder pins the main window's top-left to (120, 120). With the default 900×620 window: title bar + unified toolbar ≈ 80 px, header bar ≈ 36 px, first section header ≈ 28 px, rows ≈ 52 px, sidebar ≈ 420 px wide. Confirm before recording:
```bash
make build && open build/Build/Products/Debug/AntiFish.app && sleep 3
osascript -e 'tell application "System Events" to tell process "AntiFish" to set position of window 1 to {120, 120}'
screencapture -x build/capture/layout.png && open build/capture/layout.png
```
Adjust the numbers below to what the screenshot shows (row centres, the Contacts toolbar button). Then `verify/drive_mac.sh`:
```bash
#!/usr/bin/env bash
# Drives AntiFish while verify/record_mac.sh records. Coordinates are screen-absolute with the
# window pinned at (120,120); re-check them with the screencapture step whenever the layout changes.
set -euo pipefail
ROW1_X=320; ROW1_Y=290; ROW2_Y=342          # first two feed rows (sidebar centre)
CONTACTS_X=960; CONTACTS_Y=174               # "Contacts" toolbar button
sleep 1.5
cliclick c:$ROW1_X,$ROW1_Y      # select row 1 -> detail pane slides in
sleep 1.5
cliclick c:$ROW1_X,$ROW2_Y      # select row 2 -> detail swaps
sleep 1.5
cliclick c:$CONTACTS_X,$CONTACTS_Y   # open Contacts window
sleep 2
cliclick kd:cmd t:w ku:cmd      # close it
sleep 1.5
cliclick c:$ROW1_X,$ROW1_Y      # back to row 1
sleep 1.5
```
`chmod +x verify/drive_mac.sh`.

- [ ] **Step 5: Run the loop until SMOOTH**
Run: `make loop-mac`
Expected on success: `frame_diff.py` exits 0 and prints its SMOOTH summary. On JANK: inspect `build/capture/flagged/*.png` (use `python3 verify/crop_zoom.py <frame>` to magnify), fix the animation (typical fixes: give the detail pane a stable `.id`, avoid layout jumps by fixing heights, use `.snappy` springs with matching durations, remove implicit animations on lists that re-sort), rebuild, re-run. Repeat for the onboarding card swap (Task 3), banner slide (Task 4), contacts pin move (Task 5) and menu bar popover (Task 6) by adding the corresponding clicks to the drive script one transition at a time.

- [ ] **Step 6: Aesthetics pass**
Read `prompts/02-aesthetics.md`, do the polish pass with attention entirely on spacing, type scale, motion and empty states, then re-run `make loop-mac` until SMOOTH again. Keep the native macOS look; no custom chrome (spec section 9).

- [ ] **Step 7: Commit**
```bash
git add Makefile verify scripts/doctor.sh prompts testing.md
git commit -m "chore(ui): intentful-ui frame-verification loop for AntiFish transitions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: Full verification, testing docs, hand-off to Plan 3

**Files:**
- Modify: `testing.md`, `README.md`

- [ ] **Step 1: testing.md additions**
```markdown
## App suites

| Suite | Command | Needs |
| --- | --- | --- |
| App unit (`AntiFishTests`) | `make test-app` | `make models`; no WhatsApp data (fixture containers under temp dirs) |
| E2E (`AntiFishUITests`) | `make test-ui` | WhatsApp linked, Full Disk Access granted to the app (see below), `make models` |
| Frame verification | `make loop-mac` | Screen Recording + Accessibility for the terminal, `cliclick`, Pillow |

Full Disk Access for the app under test: run `make install` once, add `/Applications/AntiFish.app` under
System Settings → Privacy & Security → Full Disk Access, then relaunch. TCC keys the grant to the bundle ID
and team, so the Debug build under `build/` inherits it. The onboarding E2E tests do not need it (they use
fixture containers); the feed, contacts, menu bar and settings tests do.

First E2E run on a machine with an empty app database spends a few minutes enrolling; the tests wait up to 600 s.
```

- [ ] **Step 2: Full verification run (paste the summary lines into the commit body)**
```bash
make test               # Plan 1 unit suites still green
make test-app           # AppModelTests, AppModelRelinkTests, NotifierTests
make test-ui            # LaunchTests, OnboardingTests, FeedTests, ContactsTests, MenuBarTests, SettingsTests
make loop-mac           # SMOOTH
make run                # manual: menu bar item present, feed populated, a red verdict (if any in history) shows a notification only when it arrives live
```
Expected: 0 failures in every suite; `loop-mac` exits 0.

- [ ] **Step 3: README** — add under "Try it":
```markdown
- App: `make run` (installs to /Applications and launches). First launch walks through Full Disk Access, then builds fingerprints once.
```

- [ ] **Step 4: Commit**
```bash
git add testing.md README.md
git commit -m "docs: app test suites, FDA note for E2E, Plan 2 verified green

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Plan self-review

- **Spec coverage (section 9).** Feed window with grouping by day, row contents, verdict pill, explanation, detail pane with score bar against both thresholds, top-3 comparisons, enrolment quality (Contacts window), the two local-only actions → Tasks 1, 4. Contacts window with three tiers, pin/unpin/remove → Task 5. Onboarding three steps + "Building fingerprints" progress → Task 3. Menu bar with status dot, last three verdicts, Open/Pause/Quit → Task 6. Notification text and red-only rule → Task 6 (`Notifier.shouldNotify`). Launch at login → Tasks 3 and 8. Live watching, backfill, re-link detection (section 10) → Tasks 2 and 7. Calibration surface (section 8.3) → Task 8. intentful-ui loop → Task 9. Not in this plan: signing/notarization, the privacy hook, the decode probe (Plan 3).
- **Placeholder scan.** None; the only interim element is the "Ready" text in Task 3, explicitly replaced in Task 4.
- **Consistency with Plan 1.** Uses `Coordinator.enrollAll/processNew/verify/events`, `AppDatabase.verdicts(limit:)/contacts()/fingerprints()/calibration()/setting/setSetting/saveFingerprints/replaceEnrollment/allEnrollmentNotes/setBlacklisted`, `Calibrator.calibrate(notes:)`, `ContainerWatcher(root:handler:)`, `ContainerLocator(root:)`, `ModelPaths(directory:)`, `VoiceEngine(models:numThreads:)`, `NameResolver.fallbackName(for:)`, `VerdictKind`/`VerdictColour`/`Thresholds`/`CalibrationResult` exactly as Plan 1 declares them; the additions (`identity(for:)`, `protectedJIDs()`, `setPinned`, `reportImpostor`, `markGenuine`, `topComparisons`, `overrideVerdict`, `contact(jid:)`, `ResolvedIdentity.init`) are all introduced in Task 1 before use.
- **Known risks to watch during execution.** (1) XCUITest on macOS: SwiftUI `List` rows expose identifiers through their content; the tests query `descendants(matching: .any)` with a prefix predicate for that reason. If `app.statusItems` does not surface the `MenuBarExtra`, fall back to `XCUIApplication(bundleIdentifier: "com.apple.controlcenter")` is NOT correct — instead query `app.menuBarItems` and, failing that, drive the popover with `cliclick` in the intentful loop and keep the XCUITest to the window content. (2) `Text(...).accessibilityIdentifier` on a zero-size overlay may be pruned; if `LaunchTests` cannot find `antifish.rootMarker`, put the identifier on the `NavigationSplitView` instead. (3) The E2E suites need Full Disk Access for the app once per machine (documented in Task 10). (4) `MenuBarExtra` labels do not accept accessibility identifiers on every macOS version; the identifier there is best-effort and no test depends on it. (5) Linking `AntiFishCore` (static sherpa-onnx + onnxruntime) into the app target: if `xcodebuild` reports duplicate symbols with the test host, switch the package product to `sherpa-onnx-shared`.
- **Hand-off.** Plan 3 (`docs/plans/2026-09-12-antifish-release.md`) starts from this state: scheme `AntiFish`, entitlements at `AntiFish/App/`, `AppModel.start()` with `banner`, `make models`/`build`/`install` present.
