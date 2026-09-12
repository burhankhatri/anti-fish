# AntiFish Core + CLI Implementation Plan (Plan 1 of 3)

**Goal:** A tested Swift package that reads WhatsApp Desktop's voice notes, fingerprints senders, and produces verdicts, plus a CLI that exercises it end to end on real data.
**Architecture:** `AntiFishCore` (library) holds WhatsApp reading (GRDB, read-only on the live DB), audio decode (AVFoundation) and VAD/embedding (sherpa-onnx), enrolment/verification/calibration logic, the app's own GRDB store, an FSEvents watcher, and a `Coordinator` actor that ties them together. `antifish` (executable) is a thin command shell over the core. Plan 2 (SwiftUI app) and Plan 3 (signing, notarization, hooks) build on the API fixed here.
**Tech Stack:** Swift 6.3 (tools 6.0, strict concurrency), macOS 15+, GRDB.swift 7.11.1, sherpa-onnx 1.13.8 (SPM, static xcframework + onnxruntime 1.28.2), XCTest, Make.
**Spec:** `docs/specs/2026-09-12-voice-note-impersonation-design.md` (approved 2026-09-12).

Conventions for every task:
- Package root is `AntiFishCore/`. Run all `swift` commands with `--package-path AntiFishCore` from the repo root, or use the Makefile.
- Unit tests never touch the WhatsApp container. Integration tests are classes named `*IntegrationTests` and call `TestEnv.skipUnlessRealWA()`; model-dependent tests call `TestEnv.skipUnlessModels()`.
- Fake JIDs in fixtures are short (`111@lid`); never paste a real JID, name or path into the repo.
- Commit after every green task with a conventional message ending in `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

### Task 0: Package scaffold, Makefile, model fetch

**Files:**
- Create: `AntiFishCore/Package.swift`
- Create: `AntiFishCore/Sources/AntiFishCore/AntiFishCore.swift`
- Create: `AntiFishCore/Sources/antifish/main.swift`
- Create: `AntiFishCore/Tests/AntiFishCoreTests/Support/TestEnv.swift`
- Create: `AntiFishCore/Tests/AntiFishCoreTests/Unit/SmokeTests.swift`
- Create: `Makefile`
- Create: `CLAUDE.md`
- Create: `testing.md`

- [ ] **Step 1: Write the failing test**

`AntiFishCore/Tests/AntiFishCoreTests/Unit/SmokeTests.swift`:
```swift
import XCTest
@testable import AntiFishCore

final class SmokeTests: XCTestCase {
    func testPackageVersionIsSet() {
        XCTAssertEqual(AntiFishCore.version, "0.1.0")
    }
}
```

`AntiFishCore/Tests/AntiFishCoreTests/Support/TestEnv.swift`:
```swift
import Foundation
import XCTest
@testable import AntiFishCore

enum TestEnv {
    /// Models live in the app's resource folder (gitignored, fetched by `make models`) unless overridden.
    static var modelsDir: URL {
        if let p = ProcessInfo.processInfo.environment["ANTIFISH_MODELS_DIR"] {
            return URL(fileURLWithPath: p)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // AntiFishCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // AntiFishCore
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("AntiFish/Resources/Models")
    }
    static var speakerModelPath: String { modelsDir.appendingPathComponent("wespeaker_en_voxceleb_resnet34_LM.onnx").path }
    static var vadModelPath: String { modelsDir.appendingPathComponent("silero_vad.onnx").path }
    static var hasModels: Bool {
        FileManager.default.fileExists(atPath: speakerModelPath) && FileManager.default.fileExists(atPath: vadModelPath)
    }
    static var realWA: Bool {
        ProcessInfo.processInfo.environment["ANTIFISH_REAL_WA"] == "1" && ContainerLocator().isInstalled
    }
    static func skipUnlessModels() throws {
        try XCTSkipUnless(hasModels, "models missing at \(modelsDir.path): run `make models`")
    }
    static func skipUnlessRealWA() throws {
        try XCTSkipUnless(realWA, "set ANTIFISH_REAL_WA=1 on a Mac with WhatsApp Desktop linked")
    }
    static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("antifish-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

- [ ] **Step 2: Create the package so the test can be compiled, then verify it fails**

`AntiFishCore/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AntiFishCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AntiFishCore", targets: ["AntiFishCore"]),
        .executable(name: "antifish", targets: ["antifish"]),
    ],
    dependencies: [
        .package(url: "https://github.com/k2-fsa/sherpa-onnx.git", exact: "1.13.8"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "AntiFishCore",
            dependencies: [
                .product(name: "sherpa-onnx", package: "sherpa-onnx"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            linkerSettings: [.linkedLibrary("c++")]
        ),
        .executableTarget(name: "antifish", dependencies: ["AntiFishCore"]),
        .testTarget(name: "AntiFishCoreTests", dependencies: ["AntiFishCore"]),
    ]
)
```

`AntiFishCore/Sources/AntiFishCore/AntiFishCore.swift` (deliberately wrong so the test fails first):
```swift
public enum AntiFishCore {
    public static let version = "0.0.0"
}
```

`AntiFishCore/Sources/antifish/main.swift`:
```swift
import AntiFishCore
print("antifish \(AntiFishCore.version)")
```

Note: `ContainerLocator` referenced by `TestEnv` does not exist yet; add this stub now and replace it in Task 1:
`AntiFishCore/Sources/AntiFishCore/WhatsApp/ContainerLocator.swift`:
```swift
import Foundation
public struct ContainerLocator: Sendable {
    public init() {}
    public var isInstalled: Bool { false }
}
```

Run: `swift test --package-path AntiFishCore --skip IntegrationTests`
Expected: first run resolves packages (downloads the sherpa-onnx macOS xcframework and onnxruntime), builds, then `SmokeTests.testPackageVersionIsSet` FAILS with `XCTAssertEqual failed: ("0.0.0") is not equal to ("0.1.0")`.

- [ ] **Step 3: Minimal implementation**

Change `AntiFishCore.swift` to:
```swift
public enum AntiFishCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path AntiFishCore --skip IntegrationTests`
Expected: `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Makefile, docs, model fetch**

`Makefile`:
```make
PKG        := --package-path AntiFishCore
MODELS_DIR := AntiFish/Resources/Models
SILERO_URL := https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx
SILERO_SHA := 9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6
SPK_URL    := https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/wespeaker_en_voxceleb_resnet34_LM.onnx
SPK_SHA    := e9848563da86f263117134dfd7ad63c92355b37de492b55e325400c9d9c39012
export ANTIFISH_MODELS_DIR := $(CURDIR)/$(MODELS_DIR)

.PHONY: models build test test-integration cli clean

models: $(MODELS_DIR)/silero_vad.onnx $(MODELS_DIR)/wespeaker_en_voxceleb_resnet34_LM.onnx

$(MODELS_DIR)/silero_vad.onnx:
	mkdir -p $(MODELS_DIR)
	curl -L --fail -o $@ $(SILERO_URL)
	echo "$(SILERO_SHA)  $@" | shasum -a 256 -c -

$(MODELS_DIR)/wespeaker_en_voxceleb_resnet34_LM.onnx:
	mkdir -p $(MODELS_DIR)
	curl -L --fail -o $@ $(SPK_URL)
	echo "$(SPK_SHA)  $@" | shasum -a 256 -c -

build:
	swift build $(PKG)

# Unit tests: no WhatsApp data. Model-dependent unit tests skip themselves when models are absent.
test:
	swift test $(PKG) --skip IntegrationTests

# Integration tests: read this machine's live WhatsApp container. Nothing is written to the repo.
test-integration: models
	ANTIFISH_REAL_WA=1 swift test $(PKG) --filter IntegrationTests

cli: models
	swift run $(PKG) antifish $(ARGS)

clean:
	rm -rf AntiFishCore/.build
```

`testing.md`:
```markdown
# Testing AntiFish

| Suite | Command | Needs |
| --- | --- | --- |
| Unit | `make test` | nothing (model-dependent tests skip without `make models`) |
| Integration | `make test-integration` | WhatsApp Desktop linked on this Mac, Full Disk Access for the terminal, `make models` |
| CLI smoke | `make cli ARGS="status"` | same as integration |

Environment variables:
- `ANTIFISH_REAL_WA=1` — enables tests that read `~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared`.
- `ANTIFISH_MODELS_DIR` — directory holding `silero_vad.onnx` and `wespeaker_en_voxceleb_resnet34_LM.onnx` (the Makefile exports it).

Rules: tests write only under `NSTemporaryDirectory()`. Never commit audio, databases or real JIDs; `.gitignore` and the pre-commit hook (Plan 3) enforce this.
```

`CLAUDE.md` (project):
```markdown
# AntiFish

macOS app that flags WhatsApp voice notes whose voice does not match the apparent sender. Spec: `docs/specs/2026-09-12-voice-note-impersonation-design.md`. Plans: `docs/plans/`.

- Core logic lives in the Swift package `AntiFishCore/`; the app (Plan 2) only renders.
- `make test` (unit), `make test-integration` (real WhatsApp data, local only), `make models` (fetch ONNX models).
- Never commit anything from the WhatsApp container. Fixture JIDs are short fakes like `111@lid`.
- WhatsApp facts: voice notes are `ZMESSAGETYPE = 3`; media paths are container-relative; the live `ChatStorage.sqlite` is opened read-only, never copied.
- Follow the global CLAUDE.md workflow: failing test first, root cause before fixes, fresh verification before claiming done.
```

Run: `make models && make test`
Expected: both model files download with `OK` from shasum; unit tests pass.

- [ ] **Step 6: Commit**
```bash
git add AntiFishCore Makefile CLAUDE.md testing.md
git commit -m "chore: scaffold AntiFishCore package, Makefile, model fetch

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 1: ContainerLocator

**Files:**
- Modify: `AntiFishCore/Sources/AntiFishCore/WhatsApp/ContainerLocator.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/ContainerLocatorTests.swift`

- [ ] **Step 1: Write the failing test**
```swift
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
```

- [ ] **Step 2: Run test to verify it fails**
Run: `swift test --package-path AntiFishCore --filter ContainerLocatorTests`
Expected: compile error `extra argument 'root' in call` / `has no member 'defaultRoot'`.

- [ ] **Step 3: Write minimal implementation**
```swift
import Foundation

/// Locates WhatsApp Desktop's group container and the files inside it.
public struct ContainerLocator: Sendable {
    public let root: URL

    public init(root: URL = ContainerLocator.defaultRoot) {
        self.root = root
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared", isDirectory: true)
    }

    public var chatStorageURL: URL { root.appendingPathComponent("ChatStorage.sqlite") }
    public var contactsURL: URL { root.appendingPathComponent("ContactsV2.sqlite") }
    public var mediaRoot: URL { root.appendingPathComponent("Message/Media", isDirectory: true) }

    /// True when WhatsApp Desktop has ever been linked on this Mac.
    public var isInstalled: Bool {
        FileManager.default.fileExists(atPath: chatStorageURL.path)
    }

    /// Full Disk Access probe: TCC blocks the open() itself, so a 1-byte read is the truth.
    public var hasFullDiskAccess: Bool {
        guard let handle = try? FileHandle(forReadingFrom: chatStorageURL) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1)) != nil
    }

    public func mediaURL(relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**
Run: `swift test --package-path AntiFishCore --filter ContainerLocatorTests`
Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): locate WhatsApp group container and probe Full Disk Access

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Vector maths

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/Voice/Vector.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/VectorTests.swift`

- [ ] **Step 1: Write the failing test**
```swift
import XCTest
@testable import AntiFishCore

final class VectorTests: XCTestCase {
    func testCosineOfIdenticalVectorsIsOne() {
        XCTAssertEqual(Vector.cosine([1, 2, 3], [1, 2, 3]), 1, accuracy: 1e-6)
    }
    func testCosineOfOrthogonalVectorsIsZero() {
        XCTAssertEqual(Vector.cosine([1, 0], [0, 1]), 0, accuracy: 1e-6)
    }
    func testCosineOfZeroVectorIsZero() {
        XCTAssertEqual(Vector.cosine([0, 0], [1, 1]), 0)
    }
    func testNormalizedHasUnitLength() {
        let n = Vector.normalized([3, 4])
        XCTAssertEqual(n, [0.6, 0.8])
    }
    func testCentroidIsNormalizedMean() {
        let c = Vector.centroid([[1, 0], [0, 1]])
        XCTAssertEqual(c[0], c[1], accuracy: 1e-6)
        XCTAssertEqual(Vector.cosine(c, c), 1, accuracy: 1e-6)
    }
    func testCentroidOfNothingIsEmpty() {
        XCTAssertTrue(Vector.centroid([]).isEmpty)
    }
    func testDataRoundTrip() {
        let v: [Float] = [0.5, -1.25, 3]
        XCTAssertEqual(Vector.fromData(Vector.toData(v)), v)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `swift test --package-path AntiFishCore --filter VectorTests`
Expected: compile error `cannot find 'Vector' in scope`.

- [ ] **Step 3: Write minimal implementation**
```swift
import Foundation

/// Small float-vector helpers for 256-d speaker embeddings.
public enum Vector {
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    public static func normalized(_ v: [Float]) -> [Float] {
        let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    /// L2-normalised mean of the vectors. Empty input yields an empty vector.
    public static func centroid(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for v in vectors where v.count == first.count {
            for i in 0..<v.count { sum[i] += v[i] }
        }
        return normalized(sum.map { $0 / Float(vectors.count) })
    }

    public static func toData(_ v: [Float]) -> Data {
        v.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func fromData(_ d: Data) -> [Float] {
        let count = d.count / MemoryLayout<Float>.size
        return d.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(count))
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**
Run: `swift test --package-path AntiFishCore --filter VectorTests`
Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): vector maths for embeddings

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: ChatStore (read-only GRDB on WhatsApp's databases) + fixture DB

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/WhatsApp/ChatStore.swift`
- Create: `AntiFishCore/Tests/AntiFishCoreTests/Support/FixtureDB.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/ChatStoreTests.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Integration/ChatStoreIntegrationTests.swift`

- [ ] **Step 1: Write the fixture helper and the failing tests**

`AntiFishCore/Tests/AntiFishCoreTests/Support/FixtureDB.swift` — schema subset captured from WhatsApp Desktop 26.33 `sqlite_master`; rows are fakes:
```swift
import Foundation
import GRDB

enum FixtureDB {
    static let chatDDL = """
    CREATE TABLE ZWAMESSAGE (Z_PK INTEGER PRIMARY KEY, ZISFROMME INTEGER, ZMESSAGETYPE INTEGER, ZCHATSESSION INTEGER, ZGROUPMEMBER INTEGER, ZMEDIAITEM INTEGER, ZMESSAGEDATE TIMESTAMP, ZFROMJID VARCHAR, ZTOJID VARCHAR);
    CREATE TABLE ZWAMEDIAITEM (Z_PK INTEGER PRIMARY KEY, ZMOVIEDURATION INTEGER, ZMEDIALOCALPATH VARCHAR, ZMESSAGE INTEGER);
    CREATE TABLE ZWAGROUPMEMBER (Z_PK INTEGER PRIMARY KEY, ZMEMBERJID VARCHAR, ZCHATSESSION INTEGER);
    CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZCONTACTJID VARCHAR, ZPARTNERNAME VARCHAR, ZGROUPINFO INTEGER, ZCONTACTIDENTIFIER VARCHAR);
    CREATE TABLE ZWAPROFILEPUSHNAME (Z_PK INTEGER PRIMARY KEY, ZJID VARCHAR, ZPUSHNAME VARCHAR);
    CREATE TABLE ZWAPROFILEPICTUREITEM (Z_PK INTEGER PRIMARY KEY, ZJID VARCHAR, ZPATH VARCHAR);
    """

    static let contactsDDL = """
    CREATE TABLE ZWAADDRESSBOOKCONTACT (Z_PK INTEGER PRIMARY KEY, ZLID VARCHAR, ZPHONENUMBER VARCHAR, ZFULLNAME VARCHAR, ZGIVENNAME VARCHAR);
    """

    /// Creates a file-backed SQLite database at `url` with `ddl` applied.
    static func make(at url: URL, ddl: String) throws -> DatabaseQueue {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in try db.execute(sql: ddl) }
        return queue
    }

    /// Standard scenario. Session 1 = 1:1 chat with 111@lid (saved as "Abdul Test").
    /// Session 2 = group 200@g.us "Family" whose member 222@lid sends a note.
    /// Messages: 1000 incoming 1:1 note (file), 1001 incoming group note (file),
    /// 1002 incoming note without a file, 1003 outgoing note (file), 1004 a video.
    static func seedStandardChat(_ queue: DatabaseQueue) throws {
        try queue.write { db in
            try db.execute(sql: "INSERT INTO ZWACHATSESSION VALUES (1,'111@lid','Abdul Test',NULL,'111@s.whatsapp.net'),(2,'200@g.us','Family',5,NULL),(3,'333@lid','+1 555 0100',NULL,NULL)")
            try db.execute(sql: "INSERT INTO ZWAGROUPMEMBER VALUES (10,'222@lid',2)")
            try db.execute(sql: "INSERT INTO ZWAMEDIAITEM VALUES (100,12,'Message/Media/111@lid/a/b/n1.opus',1000),(101,8,'Message/Media/200@g.us/c/d/n2.opus',1001),(102,5,NULL,1002),(103,30,'Message/Media/111@lid/e/f/mine.opus',1003)")
            try db.execute(sql: """
                INSERT INTO ZWAMESSAGE (Z_PK,ZISFROMME,ZMESSAGETYPE,ZCHATSESSION,ZGROUPMEMBER,ZMEDIAITEM,ZMESSAGEDATE,ZFROMJID,ZTOJID) VALUES
                (1000,0,3,1,NULL,100,800000000,'111@lid',NULL),
                (1001,0,3,2,10,101,800000100,'200@g.us',NULL),
                (1002,0,3,1,NULL,102,800000200,'111@lid',NULL),
                (1003,1,3,1,NULL,103,800000300,NULL,'111@lid'),
                (1004,0,2,1,NULL,NULL,800000400,'111@lid',NULL)
                """)
            try db.execute(sql: "INSERT INTO ZWAPROFILEPUSHNAME VALUES (1,'111@lid','abdul'),(2,'222@lid','Karim'),(3,'333@lid','Abdul'),(4,'444@lid','Someone Else')")
            try db.execute(sql: "INSERT INTO ZWAPROFILEPICTUREITEM VALUES (1,'111@lid','Media/Profile/111-1.thumb')")
        }
    }

    static func seedStandardContacts(_ queue: DatabaseQueue) throws {
        try queue.write { db in
            try db.execute(sql: "INSERT INTO ZWAADDRESSBOOKCONTACT VALUES (1,'111@lid','+15550111','Abdul Test','Abdul'),(2,'222@lid','+15550222','Karim Test','Karim')")
        }
    }

    /// Builds both fixture databases in a fresh temp dir and returns their URLs.
    static func standardPair() throws -> (chat: URL, contacts: URL) {
        let dir = try TestEnv.tempDir()
        let chat = dir.appendingPathComponent("ChatStorage.sqlite")
        let contacts = dir.appendingPathComponent("ContactsV2.sqlite")
        try seedStandardChat(make(at: chat, ddl: chatDDL))
        try seedStandardContacts(make(at: contacts, ddl: contactsDDL))
        return (chat, contacts)
    }
}
```

`AntiFishCore/Tests/AntiFishCoreTests/Unit/ChatStoreTests.swift`:
```swift
import XCTest
import GRDB
@testable import AntiFishCore

final class ChatStoreTests: XCTestCase {
    func testMissingFileThrowsNotFound() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("nope.sqlite")
        XCTAssertThrowsError(try ChatStore(url: url)) { error in
            XCTAssertEqual(error as? ChatStoreError, .notFound(url.path))
        }
    }

    func testOpensFixtureReadOnly() throws {
        let pair = try FixtureDB.standardPair()
        let store = try ChatStore(url: pair.chat)
        let count = try store.queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ZWAMESSAGE") }
        XCTAssertEqual(count, 5)
        XCTAssertTrue(try store.tableExists("ZWAMEDIAITEM"))
        XCTAssertFalse(try store.tableExists("ZWANOPE"))
        XCTAssertThrowsError(try store.queue.write { db in try db.execute(sql: "CREATE TABLE t(x)") })
    }

    func testSnapshotCopiesDatabaseWithSidecars() throws {
        let pair = try FixtureDB.standardPair()
        let dir = try TestEnv.tempDir()
        let copy = try ChatStore.snapshot(of: pair.chat, into: dir)
        XCTAssertEqual(copy.lastPathComponent, "ChatStorage.sqlite")
        let store = try ChatStore(url: copy)
        let count = try store.queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ZWAMESSAGE") }
        XCTAssertEqual(count, 5)
    }

    func testOpenWithRetriesReturnsWorkingStore() throws {
        let pair = try FixtureDB.standardPair()
        let store = try ChatStore.open(url: pair.chat)
        XCTAssertEqual(store.url, pair.chat)
    }
}
```

`AntiFishCore/Tests/AntiFishCoreTests/Integration/ChatStoreIntegrationTests.swift`:
```swift
import XCTest
@testable import AntiFishCore

final class ChatStoreIntegrationTests: XCTestCase {
    func testLiveChatStorageOpensWhileWhatsAppRuns() throws {
        try TestEnv.skipUnlessRealWA()
        let locator = ContainerLocator()
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let messages = try store.queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ZWAMESSAGE") ?? 0 }
        XCTAssertGreaterThan(messages, 0)
        XCTAssertTrue(try store.tableExists("ZWAMEDIAITEM"))
    }

    func testLiveContactsOpens() throws {
        try TestEnv.skipUnlessRealWA()
        let store = try ChatStore.open(url: ContainerLocator().contactsURL)
        XCTAssertTrue(try store.tableExists("ZWAADDRESSBOOKCONTACT"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**
Run: `swift test --package-path AntiFishCore --filter ChatStoreTests`
Expected: compile error `cannot find 'ChatStore' in scope`.

- [ ] **Step 3: Write minimal implementation**
`AntiFishCore/Sources/AntiFishCore/WhatsApp/ChatStore.swift`:
```swift
import Foundation
import GRDB

public enum ChatStoreError: Error, Equatable {
    case notFound(String)
    case cannotOpen(String)
}

/// Read-only handle on one of WhatsApp Desktop's SQLite files.
/// WhatsApp keeps them in WAL mode, so a read-only open while WhatsApp runs is safe and sees the newest rows.
public struct ChatStore: Sendable {
    public let queue: DatabaseQueue
    public let url: URL

    public init(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ChatStoreError.notFound(url.path)
        }
        var config = Configuration()
        config.readonly = true
        config.busyMode = .timeout(2)
        config.label = "antifish.wa.\(url.lastPathComponent)"
        do {
            queue = try DatabaseQueue(path: url.path, configuration: config)
        } catch {
            throw ChatStoreError.cannotOpen("\(url.lastPathComponent): \(error)")
        }
        self.url = url
    }

    /// Opens with retries for transient lock errors, then falls back to a private snapshot copy.
    public static func open(url: URL, attempts: Int = 3,
                            snapshotDir: URL = FileManager.default.temporaryDirectory) throws -> ChatStore {
        var lastError: Error?
        for attempt in 0..<max(1, attempts) {
            do {
                let store = try ChatStore(url: url)
                _ = try store.queue.read { db in try Int.fetchOne(db, sql: "SELECT 1") }
                return store
            } catch let error as ChatStoreError {
                if case .notFound = error { throw error }
                lastError = error
            } catch {
                lastError = error
            }
            if attempt < attempts - 1 { Thread.sleep(forTimeInterval: 0.5) }
        }
        let copy = try snapshot(of: url, into: snapshotDir)
        do { return try ChatStore(url: copy) } catch { throw lastError ?? error }
    }

    /// Copies the database with its -wal and -shm sidecars. The sidecar names must stay
    /// `<name>-wal` / `<name>-shm` or SQLite silently ignores the newest rows.
    static func snapshot(of url: URL, into dir: URL) throws -> URL {
        let target = dir.appendingPathComponent("antifish-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let name = url.lastPathComponent
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.copyItem(at: source, to: target.appendingPathComponent(name + suffix))
        }
        return target.appendingPathComponent(name)
    }

    public func tableExists(_ name: String) throws -> Bool {
        try queue.read { db in try db.tableExists(name) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**
Run: `swift test --package-path AntiFishCore --filter ChatStoreTests` → `Executed 4 tests, with 0 failures`.
Run: `make test-integration` → `ChatStoreIntegrationTests` 2 tests pass (or skip with the documented message when `ANTIFISH_REAL_WA` is unset).

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): read-only GRDB access to WhatsApp databases with snapshot fallback

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: VoiceNoteQuery

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/WhatsApp/VoiceNoteQuery.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/VoiceNoteQueryTests.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Integration/VoiceNoteQueryIntegrationTests.swift`

- [ ] **Step 1: Write the failing tests**
```swift
import XCTest
@testable import AntiFishCore

final class VoiceNoteQueryTests: XCTestCase {
    private func store() throws -> ChatStore { try ChatStore(url: try FixtureDB.standardPair().chat) }

    func testReturnsOnlyType3RowsWithAFile() throws {
        let notes = try VoiceNoteQuery.fetch(store())
        XCTAssertEqual(notes.map(\.messagePK), [1000, 1001, 1003])
    }

    func testOneToOneIncomingNoteFields() throws {
        let note = try XCTUnwrap(try VoiceNoteQuery.fetch(store()).first)
        XCTAssertEqual(note.chatJID, "111@lid")
        XCTAssertEqual(note.senderJID, "111@lid")
        XCTAssertFalse(note.isFromMe)
        XCTAssertFalse(note.chatIsGroup)
        XCTAssertEqual(note.durationSeconds, 12)
        XCTAssertEqual(note.relativeMediaPath, "Message/Media/111@lid/a/b/n1.opus")
        XCTAssertEqual(note.date, Date(timeIntervalSinceReferenceDate: 800_000_000))
    }

    func testGroupNoteAttributesSenderToMember() throws {
        let note = try VoiceNoteQuery.fetch(store())[1]
        XCTAssertTrue(note.chatIsGroup)
        XCTAssertEqual(note.chatJID, "200@g.us")
        XCTAssertEqual(note.senderJID, "222@lid")
    }

    func testOutgoingNoteHasEmptySender() throws {
        let note = try VoiceNoteQuery.fetch(store())[2]
        XCTAssertTrue(note.isFromMe)
        XCTAssertEqual(note.senderJID, "")
        XCTAssertEqual(note.chatJID, "111@lid")
    }

    func testAfterPKIsIncremental() throws {
        XCTAssertEqual(try VoiceNoteQuery.fetch(store(), afterPK: 1000).map(\.messagePK), [1001, 1003])
        XCTAssertEqual(try VoiceNoteQuery.maxMessagePK(store()), 1004)
    }
}
```

```swift
import XCTest
@testable import AntiFishCore

final class VoiceNoteQueryIntegrationTests: XCTestCase {
    func testLiveQueryReturnsIncomingNotesWithFilesOnDisk() throws {
        try TestEnv.skipUnlessRealWA()
        let locator = ContainerLocator()
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let notes = try VoiceNoteQuery.fetch(store)
        XCTAssertGreaterThan(notes.count, 0)
        XCTAssertTrue(notes.allSatisfy { $0.relativeMediaPath.hasPrefix("Message/Media/") })
        let incomingOnDisk = notes.filter { !$0.isFromMe && FileManager.default.fileExists(atPath: locator.mediaURL(relativePath: $0.relativeMediaPath).path) }
        XCTAssertGreaterThan(incomingOnDisk.count, 0)
        XCTAssertTrue(incomingOnDisk.allSatisfy { !$0.senderJID.isEmpty })
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**
Run: `swift test --package-path AntiFishCore --filter VoiceNoteQueryTests`
Expected: compile error `cannot find 'VoiceNoteQuery' in scope`.

- [ ] **Step 3: Write minimal implementation**
```swift
import Foundation
import GRDB

/// One voice-note row from ChatStorage.sqlite. `senderJID` is the group member for group chats,
/// the chat JID for 1:1 chats, and empty for notes the user sent.
public struct VoiceNoteRecord: Sendable, Equatable, Hashable {
    public let messagePK: Int64
    public let chatJID: String
    public let senderJID: String
    public let isFromMe: Bool
    public let date: Date
    public let durationSeconds: Int
    public let relativeMediaPath: String
    public let chatIsGroup: Bool

    public init(messagePK: Int64, chatJID: String, senderJID: String, isFromMe: Bool, date: Date,
                durationSeconds: Int, relativeMediaPath: String, chatIsGroup: Bool) {
        self.messagePK = messagePK; self.chatJID = chatJID; self.senderJID = senderJID
        self.isFromMe = isFromMe; self.date = date; self.durationSeconds = durationSeconds
        self.relativeMediaPath = relativeMediaPath; self.chatIsGroup = chatIsGroup
    }
}

public enum VoiceNoteQuery {
    /// ZMESSAGETYPE 3 = voice note (2 is video). Only rows whose media has a local path are useful.
    static let sql = """
        SELECT m.Z_PK AS pk, m.ZFROMJID AS fromJID, m.ZTOJID AS toJID, m.ZISFROMME AS isFromMe,
               m.ZMESSAGEDATE AS date, mi.ZMOVIEDURATION AS duration, mi.ZMEDIALOCALPATH AS path,
               gm.ZMEMBERJID AS memberJID, s.ZCONTACTJID AS sessionJID,
               (s.ZGROUPINFO IS NOT NULL) AS isGroup
        FROM ZWAMESSAGE m
        JOIN ZWAMEDIAITEM mi ON mi.Z_PK = m.ZMEDIAITEM
        LEFT JOIN ZWAGROUPMEMBER gm ON gm.Z_PK = m.ZGROUPMEMBER
        LEFT JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
        WHERE m.ZMESSAGETYPE = 3 AND mi.ZMEDIALOCALPATH IS NOT NULL AND m.Z_PK > :afterPK
        ORDER BY m.Z_PK ASC
        """

    public static func fetch(_ store: ChatStore, afterPK: Int64 = 0) throws -> [VoiceNoteRecord] {
        try store.queue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: ["afterPK": afterPK]).map(record(from:))
        }
    }

    public static func maxMessagePK(_ store: ChatStore) throws -> Int64 {
        try store.queue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(Z_PK), 0) FROM ZWAMESSAGE") ?? 0
        }
    }

    static func record(from row: Row) -> VoiceNoteRecord {
        let isGroup: Bool = row["isGroup"] ?? false
        let isFromMe: Bool = row["isFromMe"] ?? false
        let fromJID: String? = row["fromJID"]
        let toJID: String? = row["toJID"]
        let memberJID: String? = row["memberJID"]
        let sessionJID: String? = row["sessionJID"]
        let chatJID = sessionJID ?? fromJID ?? toJID ?? ""
        let sender: String
        if isFromMe { sender = "" }
        else if isGroup { sender = memberJID ?? fromJID ?? "" }
        else { sender = fromJID ?? chatJID }
        let seconds: Double = row["date"] ?? 0   // Core Data epoch: seconds since 2001-01-01
        return VoiceNoteRecord(
            messagePK: row["pk"],
            chatJID: chatJID,
            senderJID: sender,
            isFromMe: isFromMe,
            date: Date(timeIntervalSinceReferenceDate: seconds),
            durationSeconds: row["duration"] ?? 0,
            relativeMediaPath: row["path"],
            chatIsGroup: isGroup)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**
Run: `swift test --package-path AntiFishCore --filter VoiceNoteQueryTests` → `Executed 5 tests, with 0 failures`.
Run: `make test-integration` → `VoiceNoteQueryIntegrationTests` passes.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): query voice notes with sender attribution and incremental cursor

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: NameResolver

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/WhatsApp/NameResolver.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/NameResolverTests.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Integration/NameResolverIntegrationTests.swift`

- [ ] **Step 1: Write the failing tests**
```swift
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

    func testPartnerNameWhenNotSaved() throws {
        let id = NameResolver.resolve("200@g.us", tables: try tables())
        XCTAssertEqual(id.displayName, "Family")
        XCTAssertFalse(id.isSavedContact)
    }

    func testPhoneShapedPartnerNameIsSkippedForPushName() throws {
        let id = NameResolver.resolve("333@lid", tables: try tables())
        XCTAssertEqual(id.displayName, "Abdul")
        XCTAssertFalse(id.isSavedContact)
    }

    func testFallbackUsesLastFourDigits() {
        XCTAssertEqual(NameResolver.resolve("5551234567@lid", tables: NameTables()).displayName, "WA ····4567")
        XCTAssertEqual(NameResolver.fallbackName(for: "abc@lid"), "WhatsApp user")
    }

    func testPhoneShaped() {
        XCTAssertTrue(NameResolver.isPhoneShaped("+1 555 0100"))
        XCTAssertTrue(NameResolver.isPhoneShaped("(555) 010-0100"))
        XCTAssertFalse(NameResolver.isPhoneShaped("Abdul"))
        XCTAssertFalse(NameResolver.isPhoneShaped("WA ····4567"))
        XCTAssertFalse(NameResolver.isPhoneShaped(""))
    }

    func testAddressBookIndexesBothJIDForms() throws {
        let t = try tables()
        XCTAssertEqual(t.addressBook["111@lid"], "Abdul Test")
        XCTAssertEqual(t.addressBook["15550111@s.whatsapp.net"], "Abdul Test")
    }
}
```

```swift
import XCTest
@testable import AntiFishCore

final class NameResolverIntegrationTests: XCTestCase {
    func testLiveTablesNameAtLeastOneVoiceNoteSender() throws {
        try TestEnv.skipUnlessRealWA()
        let locator = ContainerLocator()
        let chat = try ChatStore.open(url: locator.chatStorageURL)
        let contacts = try? ChatStore.open(url: locator.contactsURL)
        let tables = try NameTables.load(chat: chat, contacts: contacts)
        XCTAssertGreaterThan(tables.addressBook.count, 0)
        let senders = Set(try VoiceNoteQuery.fetch(chat).filter { !$0.isFromMe }.map(\.senderJID))
        let named = senders.filter { !NameResolver.resolve($0, tables: tables).displayName.hasPrefix("WA ") }
        XCTAssertGreaterThan(named.count, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**
Run: `swift test --package-path AntiFishCore --filter NameResolverTests`
Expected: compile error `cannot find 'NameTables' in scope`.

- [ ] **Step 3: Write minimal implementation**
```swift
import Foundation
import GRDB

public struct ResolvedIdentity: Sendable, Equatable {
    public let jid: String
    public let displayName: String
    /// True only when the JID is in the user's synced address book (ContactsV2.sqlite).
    public let isSavedContact: Bool
    /// Chosen by the sender; an impersonator controls this string.
    public let pushName: String?
    public let avatarPath: String?
}

/// Name lookups loaded once per pass from ContactsV2.sqlite and ChatStorage.sqlite.
public struct NameTables: Sendable, Equatable {
    public var addressBook: [String: String] = [:]   // "<digits>@lid" or "<digits>@s.whatsapp.net" -> full name
    public var partnerNames: [String: String] = [:]  // chat JID -> ZPARTNERNAME
    public var pushNames: [String: String] = [:]     // JID -> push name
    public var avatarPaths: [String: String] = [:]   // JID -> container-relative path

    public init() {}

    public static func load(chat: ChatStore, contacts: ChatStore?) throws -> NameTables {
        var t = NameTables()
        try chat.queue.read { db in
            for row in try Row.fetchAll(db, sql: "SELECT ZCONTACTJID, ZCONTACTIDENTIFIER, ZPARTNERNAME FROM ZWACHATSESSION WHERE ZPARTNERNAME IS NOT NULL") {
                let name: String = row[2]
                if let jid: String = row[0] { t.partnerNames[jid] = name }
                if let alias: String = row[1] { t.partnerNames[alias] = name }
            }
            if try db.tableExists("ZWAPROFILEPUSHNAME") {
                for row in try Row.fetchAll(db, sql: "SELECT ZJID, ZPUSHNAME FROM ZWAPROFILEPUSHNAME WHERE ZJID IS NOT NULL AND ZPUSHNAME IS NOT NULL") {
                    t.pushNames[row[0]] = row[1]
                }
            }
            if try db.tableExists("ZWAPROFILEPICTUREITEM") {
                for row in try Row.fetchAll(db, sql: "SELECT ZJID, ZPATH FROM ZWAPROFILEPICTUREITEM WHERE ZJID IS NOT NULL AND ZPATH IS NOT NULL") {
                    t.avatarPaths[row[0]] = row[1]
                }
            }
        }
        if let contacts {
            try contacts.queue.read { db in
                for row in try Row.fetchAll(db, sql: "SELECT ZLID, ZPHONENUMBER, ZFULLNAME FROM ZWAADDRESSBOOKCONTACT WHERE ZFULLNAME IS NOT NULL AND ZFULLNAME != ''") {
                    let name: String = row[2]
                    if let lid: String = row[0], !lid.isEmpty { t.addressBook[lid] = name }
                    if let phone: String = row[1] {
                        let digits = phone.filter(\.isNumber)
                        if !digits.isEmpty { t.addressBook["\(digits)@s.whatsapp.net"] = name }
                    }
                }
            }
        }
        return t
    }
}

public enum NameResolver {
    /// Precedence: address book → saved chat name (unless phone-shaped) → push name → fallback.
    public static func resolve(_ jid: String, tables: NameTables) -> ResolvedIdentity {
        let saved = tables.addressBook[jid]
        let partner = tables.partnerNames[jid].flatMap { isPhoneShaped($0) ? nil : $0 }
        let push = tables.pushNames[jid]
        return ResolvedIdentity(
            jid: jid,
            displayName: saved ?? partner ?? push ?? fallbackName(for: jid),
            isSavedContact: saved != nil,
            pushName: push,
            avatarPath: tables.avatarPaths[jid])
    }

    public static func fallbackName(for jid: String) -> String {
        let digits = jid.prefix { $0 != "@" }.filter(\.isNumber)
        let last4 = String(digits.suffix(4))
        return last4.isEmpty ? "WhatsApp user" : "WA ····\(last4)"
    }

    public static func isPhoneShaped(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains(where: \.isNumber) else { return false }
        let allowed = CharacterSet(charactersIn: "+-() ").union(.decimalDigits)
        return trimmed.unicodeScalars.allSatisfy(allowed.contains)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**
Run: `swift test --package-path AntiFishCore --filter NameResolverTests` → `Executed 6 tests, with 0 failures`.
Run: `make test-integration` → `NameResolverIntegrationTests` passes.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): resolve WhatsApp JIDs to names with address-book precedence

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: OpusDecoder

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/Audio/OpusDecoder.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/OpusDecoderTests.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Integration/OpusDecoderIntegrationTests.swift`

- [ ] **Step 1: Write the failing tests**
```swift
import XCTest
import AVFoundation
@testable import AntiFishCore

final class OpusDecoderTests: XCTestCase {
    func testMissingFileIsUnreadable() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("missing.opus")
        XCTAssertThrowsError(try OpusDecoder.decode(url: url)) { error in
            XCTAssertEqual(error as? AudioDecodeError, .unreadable("missing.opus"))
        }
    }

    func testGarbageFileIsUnreadable() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("junk.opus")
        try Data("not audio".utf8).write(to: url)
        XCTAssertThrowsError(try OpusDecoder.decode(url: url))
    }

    /// A 48 kHz stereo 1 kHz tone written by AVFoundation decodes to 16 kHz mono with the right length and level.
    func testResamplesToSixteenKilohertzMono() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("tone.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames: AVAudioFrameCount = 48_000
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let v = Float(sin(2 * Double.pi * 1000 * Double(i) / 48_000)) * 0.5
            buffer.floatChannelData![0][i] = v
            buffer.floatChannelData![1][i] = v
        }
        try file.write(from: buffer)

        let decoded = try OpusDecoder.decode(url: url)
        XCTAssertEqual(decoded.sampleRate, 16_000)
        XCTAssertEqual(decoded.seconds, 1.0, accuracy: 0.02)
        XCTAssertEqual(decoded.rms, 0.5 / Float(2).squareRoot(), accuracy: 0.03)
    }
}
```

```swift
import XCTest
@testable import AntiFishCore

final class OpusDecoderIntegrationTests: XCTestCase {
    func testNewestIncomingVoiceNoteDecodes() throws {
        try TestEnv.skipUnlessRealWA()
        let locator = ContainerLocator()
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let note = try XCTUnwrap(try VoiceNoteQuery.fetch(store).last { note in
            !note.isFromMe && FileManager.default.fileExists(atPath: locator.mediaURL(relativePath: note.relativeMediaPath).path)
        })
        let decoded = try OpusDecoder.decode(url: locator.mediaURL(relativePath: note.relativeMediaPath))
        XCTAssertEqual(decoded.sampleRate, 16_000)
        XCTAssertGreaterThan(decoded.rms, 0.01)
        let expected = Double(note.durationSeconds)
        XCTAssertGreaterThan(decoded.seconds, expected * 0.7)
        XCTAssertLessThan(decoded.seconds, expected * 1.3 + 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**
Run: `swift test --package-path AntiFishCore --filter OpusDecoderTests`
Expected: compile error `cannot find 'OpusDecoder' in scope`.

- [ ] **Step 3: Write minimal implementation**
```swift
import AVFoundation
import Foundation

public enum AudioDecodeError: Error, Equatable {
    case unreadable(String)
    case unsupportedFormat(String)
    case conversionFailed(String)
}

public struct DecodedAudio: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Double
    public var seconds: Double { Double(samples.count) / sampleRate }
    public var rms: Float {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }
}

/// Decodes anything AVFoundation can read — WhatsApp's Ogg-Opus voice notes included — to 16 kHz mono Float32.
public enum OpusDecoder {
    public static let targetSampleRate: Double = 16_000

    public static func decode(url: URL) throws -> DecodedAudio {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) }
        catch { throw AudioDecodeError.unreadable(url.lastPathComponent) }

        let source = file.processingFormat
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(max(file.length, 1))),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 16_384) else {
            throw AudioDecodeError.unsupportedFormat(source.description)
        }
        do { try file.read(into: input) }
        catch { throw AudioDecodeError.unreadable(url.lastPathComponent) }

        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(input.frameLength) * targetSampleRate / source.sampleRate) + 1024)
        var delivered = false
        var status: AVAudioConverterOutputStatus = .haveData
        while status == .haveData {
            var convError: NSError?
            output.frameLength = 0
            status = converter.convert(to: output, error: &convError) { _, outStatus in
                if delivered { outStatus.pointee = .endOfStream; return nil }
                delivered = true
                outStatus.pointee = .haveData
                return input
            }
            if let convError { throw AudioDecodeError.conversionFailed(convError.localizedDescription) }
            if status == .error { throw AudioDecodeError.conversionFailed("converter returned .error") }
            if let channel = output.floatChannelData, output.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
            }
        }
        return DecodedAudio(samples: samples, sampleRate: targetSampleRate)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**
Run: `swift test --package-path AntiFishCore --filter OpusDecoderTests` → `Executed 3 tests, with 0 failures`.
Run: `make test-integration` → `OpusDecoderIntegrationTests` passes.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): decode Ogg-Opus voice notes to 16 kHz mono via AVFoundation

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: SpeechTrimmer (Silero VAD)

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/Voice/VoiceEngineError.swift`
- Create: `AntiFishCore/Sources/AntiFishCore/Audio/SpeechTrimmer.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/SpeechTrimmerTests.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Integration/SpeechTrimmerIntegrationTests.swift`

- [ ] **Step 1: Write the failing tests**
```swift
import XCTest
@testable import AntiFishCore

final class SpeechTrimmerTests: XCTestCase {
    func testMissingModelThrows() {
        XCTAssertThrowsError(try SpeechTrimmer(modelPath: "/nonexistent/silero_vad.onnx")) { error in
            XCTAssertEqual(error as? VoiceEngineError, .modelMissing("/nonexistent/silero_vad.onnx"))
        }
    }

    func testSilenceYieldsNoSpeech() throws {
        try TestEnv.skipUnlessModels()
        let trimmer = try SpeechTrimmer(modelPath: TestEnv.vadModelPath)
        let silence = [Float](repeating: 0, count: 3 * SpeechTrimmer.sampleRate)
        let trimmed = trimmer.trim(silence)
        XCTAssertEqual(trimmed.speechSeconds, 0)
        XCTAssertTrue(trimmed.samples.isEmpty)
    }

    func testEmptyInputIsSafe() throws {
        try TestEnv.skipUnlessModels()
        let trimmer = try SpeechTrimmer(modelPath: TestEnv.vadModelPath)
        XCTAssertEqual(trimmer.trim([]).speechSeconds, 0)
    }
}
```

```swift
import XCTest
@testable import AntiFishCore

final class SpeechTrimmerIntegrationTests: XCTestCase {
    func testRealVoiceNoteKeepsMostOfItsSpeech() throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let locator = ContainerLocator()
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let note = try XCTUnwrap(try VoiceNoteQuery.fetch(store).last { note in
            !note.isFromMe && note.durationSeconds >= 5
                && FileManager.default.fileExists(atPath: locator.mediaURL(relativePath: note.relativeMediaPath).path)
        })
        let decoded = try OpusDecoder.decode(url: locator.mediaURL(relativePath: note.relativeMediaPath))
        let trimmed = try SpeechTrimmer(modelPath: TestEnv.vadModelPath).trim(decoded.samples)
        XCTAssertGreaterThan(trimmed.speechSeconds, Double(note.durationSeconds) * 0.3)
        XCTAssertLessThanOrEqual(trimmed.speechSeconds, decoded.seconds * 1.2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**
Run: `swift test --package-path AntiFishCore --filter SpeechTrimmerTests`
Expected: compile error `cannot find 'SpeechTrimmer' in scope`.

- [ ] **Step 3: Write minimal implementation**

`AntiFishCore/Sources/AntiFishCore/Voice/VoiceEngineError.swift`:
```swift
public enum VoiceEngineError: Error, Equatable {
    case modelMissing(String)
    case embeddingFailed
}
```

`AntiFishCore/Sources/AntiFishCore/Audio/SpeechTrimmer.swift`:
```swift
import Foundation
import SherpaOnnx

public struct TrimmedSpeech: Sendable, Equatable {
    public let samples: [Float]
    public let speechSeconds: Double
}

/// Silero VAD through sherpa-onnx. Not Sendable: owned by the VoiceEngine actor.
public final class SpeechTrimmer {
    public static let sampleRate = 16_000
    private static let window = 512
    private let vad: SherpaOnnxVoiceActivityDetectorWrapper

    public init(modelPath: String) throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw VoiceEngineError.modelMissing(modelPath)
        }
        var config = sherpaOnnxVadModelConfig(
            sileroVad: sherpaOnnxSileroVadModelConfig(
                model: modelPath, threshold: 0.5, minSilenceDuration: 0.25,
                minSpeechDuration: 0.25, windowSize: Self.window, maxSpeechDuration: 20),
            sampleRate: Int32(Self.sampleRate), numThreads: 1)
        vad = SherpaOnnxVoiceActivityDetectorWrapper(config: &config, buffer_size_in_seconds: 120)
    }

    /// Returns only the speech portions, concatenated, at 16 kHz.
    public func trim(_ samples: [Float]) -> TrimmedSpeech {
        vad.reset()
        var kept: [Float] = []
        var index = 0
        while index < samples.count {
            let end = min(index + Self.window, samples.count)
            vad.acceptWaveform(samples: Array(samples[index..<end]))
            drain(into: &kept)
            index = end
        }
        vad.flush()
        drain(into: &kept)
        return TrimmedSpeech(samples: kept, speechSeconds: Double(kept.count) / Double(Self.sampleRate))
    }

    private func drain(into kept: inout [Float]) {
        while !vad.isEmpty() {
            kept.append(contentsOf: vad.front().samples)
            vad.pop()
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**
Run: `make test` (exports the models dir) → `SpeechTrimmerTests` 3 tests pass.
Run: `make test-integration` → `SpeechTrimmerIntegrationTests` passes.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): trim voice notes to speech with Silero VAD

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: SherpaEmbeddingExtractor

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/Voice/EmbeddingExtractor.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/EmbeddingExtractorTests.swift`

- [ ] **Step 1: Write the failing test**
```swift
import XCTest
@testable import AntiFishCore

final class EmbeddingExtractorTests: XCTestCase {
    /// Two seconds of a harmonic tone: deterministic, no personal data.
    private func tone(hz: Double, seconds: Double = 2) -> [Float] {
        let n = Int(seconds * Double(SherpaEmbeddingExtractor.sampleRate))
        return (0..<n).map { i in
            let t = Double(i) / Double(SherpaEmbeddingExtractor.sampleRate)
            return Float(0.3 * sin(2 * .pi * hz * t) + 0.15 * sin(2 * .pi * 2 * hz * t) + 0.05 * sin(2 * .pi * 3 * hz * t))
        }
    }

    func testMissingModelThrows() {
        XCTAssertThrowsError(try SherpaEmbeddingExtractor(modelPath: "/nonexistent/model.onnx"))
    }

    func testEmbeddingIs256DUnitNormAndDeterministic() throws {
        try TestEnv.skipUnlessModels()
        let extractor = try SherpaEmbeddingExtractor(modelPath: TestEnv.speakerModelPath)
        XCTAssertEqual(extractor.dimension, 256)
        XCTAssertEqual(extractor.modelVersion, "wespeaker_en_voxceleb_resnet34_LM")
        let a = try extractor.embed(tone(hz: 180))
        let b = try extractor.embed(tone(hz: 180))
        XCTAssertEqual(a.count, 256)
        XCTAssertEqual(a.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1, accuracy: 1e-4)
        XCTAssertEqual(Vector.cosine(a, b), 1, accuracy: 1e-4)
    }

    func testDifferentSignalsGiveDifferentEmbeddings() throws {
        try TestEnv.skipUnlessModels()
        let extractor = try SherpaEmbeddingExtractor(modelPath: TestEnv.speakerModelPath)
        let a = try extractor.embed(tone(hz: 120))
        let b = try extractor.embed(tone(hz: 260))
        XCTAssertLessThan(Vector.cosine(a, b), 0.999)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `make test` → compile error `cannot find 'SherpaEmbeddingExtractor' in scope`.

- [ ] **Step 3: Write minimal implementation**
```swift
import Foundation
import SherpaOnnx

public protocol EmbeddingExtractor: AnyObject {
    var dimension: Int { get }
    var modelVersion: String { get }
    /// `samples` are 16 kHz mono speech (already VAD-trimmed). Returns an L2-normalised vector.
    func embed(_ samples: [Float]) throws -> [Float]
}

/// WeSpeaker ResNet34-LM through sherpa-onnx. Not Sendable: owned by the VoiceEngine actor.
public final class SherpaEmbeddingExtractor: EmbeddingExtractor {
    public static let sampleRate = 16_000
    private let extractor: SherpaOnnxSpeakerEmbeddingExtractorWrapper
    public let modelVersion: String

    public init(modelPath: String, numThreads: Int = 2) throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw VoiceEngineError.modelMissing(modelPath)
        }
        var config = sherpaOnnxSpeakerEmbeddingExtractorConfig(model: modelPath, numThreads: numThreads)
        extractor = SherpaOnnxSpeakerEmbeddingExtractorWrapper(config: &config)
        modelVersion = URL(fileURLWithPath: modelPath).deletingPathExtension().lastPathComponent
    }

    public var dimension: Int { extractor.dim }

    public func embed(_ samples: [Float]) throws -> [Float] {
        let stream = extractor.createStream()
        stream.acceptWaveform(samples: samples, sampleRate: Self.sampleRate)
        stream.inputFinished()
        let raw = extractor.compute(stream: stream)
        guard raw.count == dimension, raw.contains(where: { $0 != 0 }) else {
            throw VoiceEngineError.embeddingFailed
        }
        return Vector.normalized(raw)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**
Run: `make test` → `EmbeddingExtractorTests` 3 tests pass.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): speaker embeddings via sherpa-onnx WeSpeaker ResNet34

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: VoiceEngine actor

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/Voice/VoiceEngine.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/VoiceEngineTests.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Integration/VoiceEngineIntegrationTests.swift`

- [ ] **Step 1: Write the failing tests**
```swift
import XCTest
@testable import AntiFishCore

final class VoiceEngineTests: XCTestCase {
    func testModelPathsFromDirectory() {
        let paths = ModelPaths(directory: URL(fileURLWithPath: "/m"))
        XCTAssertEqual(paths.speakerModel, "/m/wespeaker_en_voxceleb_resnet34_LM.onnx")
        XCTAssertEqual(paths.vadModel, "/m/silero_vad.onnx")
    }

    func testSilenceProducesNoEmbedding() async throws {
        try TestEnv.skipUnlessModels()
        let engine = try VoiceEngine(models: ModelPaths(directory: TestEnv.modelsDir))
        let analysis = try await engine.analyze(samples: [Float](repeating: 0, count: 2 * 16_000))
        XCTAssertTrue(analysis.embedding.isEmpty)
        XCTAssertEqual(analysis.speechSeconds, 0)
        XCTAssertEqual(analysis.totalSeconds, 2, accuracy: 0.001)
        XCTAssertEqual(engine.modelVersion, "wespeaker_en_voxceleb_resnet34_LM")
    }
}
```

```swift
import XCTest
@testable import AntiFishCore

final class VoiceEngineIntegrationTests: XCTestCase {
    func testRealVoiceNoteProducesEmbedding() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let locator = ContainerLocator()
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let note = try XCTUnwrap(try VoiceNoteQuery.fetch(store).last { note in
            !note.isFromMe && note.durationSeconds >= 3
                && FileManager.default.fileExists(atPath: locator.mediaURL(relativePath: note.relativeMediaPath).path)
        })
        let engine = try VoiceEngine(models: ModelPaths(directory: TestEnv.modelsDir))
        let analysis = try await engine.analyze(url: locator.mediaURL(relativePath: note.relativeMediaPath))
        XCTAssertEqual(analysis.embedding.count, 256)
        XCTAssertGreaterThan(analysis.speechSeconds, 0.5)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**
Run: `make test` → compile error `cannot find 'VoiceEngine' in scope`.

- [ ] **Step 3: Write minimal implementation**
```swift
import Foundation

public struct ModelPaths: Sendable, Equatable {
    public let speakerModel: String
    public let vadModel: String

    public init(speakerModel: String, vadModel: String) {
        self.speakerModel = speakerModel
        self.vadModel = vadModel
    }

    public init(directory: URL) {
        self.init(speakerModel: directory.appendingPathComponent("wespeaker_en_voxceleb_resnet34_LM.onnx").path,
                  vadModel: directory.appendingPathComponent("silero_vad.onnx").path)
    }
}

public struct VoiceAnalysis: Sendable, Equatable {
    /// Empty when there was too little speech to embed.
    public let embedding: [Float]
    public let speechSeconds: Double
    public let totalSeconds: Double
}

/// Owns the non-Sendable sherpa objects. Every decode/trim/embed goes through here.
public actor VoiceEngine {
    public static let minSpeechSecondsForEmbedding = 0.5
    private let trimmer: SpeechTrimmer
    private let extractor: SherpaEmbeddingExtractor
    public nonisolated let modelVersion: String

    public init(models: ModelPaths, numThreads: Int = 2) throws {
        trimmer = try SpeechTrimmer(modelPath: models.vadModel)
        extractor = try SherpaEmbeddingExtractor(modelPath: models.speakerModel, numThreads: numThreads)
        modelVersion = extractor.modelVersion
    }

    public func analyze(url: URL) throws -> VoiceAnalysis {
        try analyze(samples: try OpusDecoder.decode(url: url).samples)
    }

    public func analyze(samples: [Float]) throws -> VoiceAnalysis {
        let total = Double(samples.count) / OpusDecoder.targetSampleRate
        let trimmed = trimmer.trim(samples)
        guard trimmed.speechSeconds >= Self.minSpeechSecondsForEmbedding else {
            return VoiceAnalysis(embedding: [], speechSeconds: trimmed.speechSeconds, totalSeconds: total)
        }
        return VoiceAnalysis(embedding: try extractor.embed(trimmed.samples),
                             speechSeconds: trimmed.speechSeconds, totalSeconds: total)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**
Run: `make test` → `VoiceEngineTests` 2 tests pass.
Run: `make test-integration` → `VoiceEngineIntegrationTests` passes.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): VoiceEngine actor for decode, trim and embed

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: Fingerprint, Thresholds, Enroller

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/Voice/Thresholds.swift`
- Create: `AntiFishCore/Sources/AntiFishCore/Voice/Fingerprint.swift`
- Create: `AntiFishCore/Sources/AntiFishCore/Voice/Enroller.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/EnrollerTests.swift`

- [ ] **Step 1: Write the failing test**
```swift
import XCTest
@testable import AntiFishCore

final class EnrollerTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private func note(_ jid: String, pk: Int64, secs: Double = 12, daysAgo: Double = 0, vec: [Float] = [1, 0]) -> EnrolledNote {
        EnrolledNote(jid: jid, messagePK: pk, embedding: vec, speechSeconds: secs,
                     date: Date(timeIntervalSinceReferenceDate: 1_000_000 - daysAgo * day))
    }
    private let policy = EnrollmentPolicy()

    func testSenderNeedsThreeNotesAndThirtySeconds() {
        let notes = [
            note("a@lid", pk: 1), note("a@lid", pk: 2), note("a@lid", pk: 3),          // 36 s: enrolled
            note("b@lid", pk: 4), note("b@lid", pk: 5),                                 // 2 notes: no
            note("c@lid", pk: 6, secs: 5), note("c@lid", pk: 7, secs: 5), note("c@lid", pk: 8, secs: 5), // 15 s: no
        ]
        let fps = Enroller.fingerprints(from: notes, policy: policy, modelVersion: "m1")
        XCTAssertEqual(fps.map(\.jid), ["a@lid"])
        XCTAssertEqual(fps[0].noteCount, 3)
        XCTAssertEqual(fps[0].speechSeconds, 36)
        XCTAssertEqual(fps[0].modelVersion, "m1")
        XCTAssertEqual(Vector.cosine(fps[0].centroid, [1, 0]), 1, accuracy: 1e-6)
    }

    func testNewestThirtyNotesFeedTheCentroid() {
        let notes = (0..<40).map { i in note("d@lid", pk: Int64(i), daysAgo: Double(i)) }
        let fp = Enroller.fingerprints(from: notes, policy: policy, modelVersion: "m1")[0]
        XCTAssertEqual(fp.noteCount, 30)
        XCTAssertEqual(fp.lastNoteDate, notes[0].date)
    }

    func testNotesWithoutEmbeddingAreIgnoredAndOrderIsByRecency() {
        let notes = [
            note("old@lid", pk: 1, daysAgo: 10), note("old@lid", pk: 2, daysAgo: 11), note("old@lid", pk: 3, daysAgo: 12),
            note("new@lid", pk: 4), note("new@lid", pk: 5), note("new@lid", pk: 6),
            note("empty@lid", pk: 7, vec: []), note("empty@lid", pk: 8, vec: []), note("empty@lid", pk: 9, vec: []),
        ]
        XCTAssertEqual(Enroller.fingerprints(from: notes, policy: policy, modelVersion: "m1").map(\.jid), ["new@lid", "old@lid"])
    }

    func testProtectedIsTopTenByRecencyWithPinsFirst() {
        let notes = (0..<12).flatMap { s in (0..<3).map { n in note("s\(s)@lid", pk: Int64(s * 10 + n), daysAgo: Double(s)) } }
        let fps = Enroller.fingerprints(from: notes, policy: policy, modelVersion: "m1")
        let plain = Enroller.protectedJIDs(fps, pinned: [], policy: policy)
        XCTAssertEqual(plain.count, 10)
        XCTAssertEqual(plain.first, "s0@lid")
        XCTAssertFalse(plain.contains("s11@lid"))
        let pinned = Enroller.protectedJIDs(fps, pinned: ["s11@lid", "ghost@lid"], policy: policy)
        XCTAssertEqual(pinned.first, "s11@lid")
        XCTAssertEqual(pinned.count, 10)
        XCTAssertFalse(pinned.contains("ghost@lid"))
    }

    func testRollingAppendGate() {
        let t = Thresholds()
        let existing = [note("a@lid", pk: 1), note("a@lid", pk: 2)]
        let good = note("a@lid", pk: 3, secs: 4)
        XCTAssertEqual(Enroller.rollingAppend(existing: existing, candidate: good, score: 0.6, thresholds: t, policy: policy)?.count, 3)
        XCTAssertNil(Enroller.rollingAppend(existing: existing, candidate: good, score: 0.4, thresholds: t, policy: policy))
        XCTAssertNil(Enroller.rollingAppend(existing: existing, candidate: note("a@lid", pk: 3, secs: 1.5), score: 0.9, thresholds: t, policy: policy))
        XCTAssertNil(Enroller.rollingAppend(existing: existing, candidate: note("b@lid", pk: 3, secs: 4), score: 0.9, thresholds: t, policy: policy))
        XCTAssertNil(Enroller.rollingAppend(existing: existing, candidate: note("a@lid", pk: 2, secs: 4), score: 0.9, thresholds: t, policy: policy))
        XCTAssertNil(Enroller.rollingAppend(existing: existing, candidate: note("a@lid", pk: 3, secs: 4, vec: []), score: 0.9, thresholds: t, policy: policy))
    }

    func testRollingAppendKeepsNewestThirty() {
        let existing = (1...30).map { i in note("a@lid", pk: Int64(i), daysAgo: Double(i)) }
        let newest = note("a@lid", pk: 99, secs: 4)
        let merged = try! XCTUnwrap(Enroller.rollingAppend(existing: existing, candidate: newest, score: 0.9, thresholds: Thresholds(), policy: policy))
        XCTAssertEqual(merged.count, 30)
        XCTAssertEqual(merged.first?.messagePK, 99)
        XCTAssertFalse(merged.contains { $0.messagePK == 30 })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `make test` → compile error `cannot find 'EnrolledNote' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Voice/Thresholds.swift`:
```swift
/// Cosine-similarity thresholds. Defaults apply until Calibrator has ≥5 fingerprints to learn from.
public struct Thresholds: Sendable, Equatable, Codable {
    public var reject: Float
    public var match: Float
    public var calibrated: Bool

    public init(reject: Float = 0.25, match: Float = 0.45, calibrated: Bool = false) {
        self.reject = reject
        self.match = match
        self.calibrated = calibrated
    }
}
```

`Voice/Fingerprint.swift`:
```swift
import Foundation

/// One analysed voice note that contributes to a contact's fingerprint.
public struct EnrolledNote: Sendable, Equatable, Codable {
    public let jid: String
    public let messagePK: Int64
    public let embedding: [Float]
    public let speechSeconds: Double
    public let date: Date

    public init(jid: String, messagePK: Int64, embedding: [Float], speechSeconds: Double, date: Date) {
        self.jid = jid; self.messagePK = messagePK; self.embedding = embedding
        self.speechSeconds = speechSeconds; self.date = date
    }
}

public struct Fingerprint: Sendable, Equatable {
    public let jid: String
    /// L2-normalised mean of the enrolled embeddings.
    public let centroid: [Float]
    public let noteCount: Int
    public let speechSeconds: Double
    public let lastNoteDate: Date
    public let modelVersion: String

    public init(jid: String, centroid: [Float], noteCount: Int, speechSeconds: Double, lastNoteDate: Date, modelVersion: String) {
        self.jid = jid; self.centroid = centroid; self.noteCount = noteCount
        self.speechSeconds = speechSeconds; self.lastNoteDate = lastNoteDate; self.modelVersion = modelVersion
    }
}
```

`Voice/Enroller.swift`:
```swift
import Foundation

public struct EnrollmentPolicy: Sendable, Equatable {
    public var minNotes = 3
    public var minSpeechSeconds = 30.0
    public var maxNotes = 30
    public var protectedCount = 10
    public init() {}
}

public enum Enroller {
    /// Newest `maxNotes` notes per sender; a fingerprint only for senders meeting both minimums.
    /// Result is ordered by most recent note.
    public static func fingerprints(from notes: [EnrolledNote], policy: EnrollmentPolicy, modelVersion: String) -> [Fingerprint] {
        let bySender = Dictionary(grouping: notes.filter { !$0.embedding.isEmpty }, by: \.jid)
        return bySender.compactMap { jid, all -> Fingerprint? in
            let kept = Array(all.sorted { $0.date > $1.date }.prefix(policy.maxNotes))
            let speech = kept.reduce(0) { $0 + $1.speechSeconds }
            guard kept.count >= policy.minNotes, speech >= policy.minSpeechSeconds else { return nil }
            return Fingerprint(jid: jid, centroid: Vector.centroid(kept.map(\.embedding)), noteCount: kept.count,
                               speechSeconds: speech, lastNoteDate: kept[0].date, modelVersion: modelVersion)
        }
        .sorted { $0.lastNoteDate > $1.lastNoteDate }
    }

    /// Pinned enrolled JIDs first, then the most recently active, filled up to `protectedCount`.
    public static func protectedJIDs(_ fingerprints: [Fingerprint], pinned: [String], policy: EnrollmentPolicy) -> [String] {
        let enrolled = Set(fingerprints.map(\.jid))
        var result = pinned.filter(enrolled.contains)
        for fp in fingerprints.sorted(by: { $0.lastNoteDate > $1.lastNoteDate }) where !result.contains(fp.jid) {
            if result.count >= policy.protectedCount { break }
            result.append(fp.jid)
        }
        return result
    }

    /// Rolling-update gate: same sender, verified score, ≥2 s of speech, not already enrolled.
    /// Returns the merged list (newest first, capped) or nil when the note is rejected.
    public static func rollingAppend(existing: [EnrolledNote], candidate: EnrolledNote, score: Float,
                                    thresholds: Thresholds, policy: EnrollmentPolicy) -> [EnrolledNote]? {
        guard !candidate.embedding.isEmpty, candidate.speechSeconds >= 2, score >= thresholds.match,
              existing.allSatisfy({ $0.jid == candidate.jid }),
              !existing.contains(where: { $0.messagePK == candidate.messagePK }) else { return nil }
        let merged = (existing + [candidate]).sorted { $0.date > $1.date }
        return Array(merged.prefix(policy.maxNotes))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**
Run: `make test` → `EnrollerTests` 6 tests pass.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): enrolment policy, fingerprints and rolling update gate

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: Verifier

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/Voice/Verdict.swift`
- Create: `AntiFishCore/Sources/AntiFishCore/Voice/Verifier.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/VerifierTests.swift`

- [ ] **Step 1: Write the failing test**
```swift
import XCTest
@testable import AntiFishCore

final class VerifierTests: XCTestCase {
    private let t = Thresholds()   // reject 0.25, match 0.45
    private let names = ["a@lid": "Abdul", "k@lid": "Karim", "x@lid": "WA ····0001"]

    private func input(_ cls: SenderClass, sender: String = "a@lid", claim: String? = nil, speech: Double = 5,
                       scores: [String: Float]) -> VerificationInput {
        VerificationInput(senderJID: sender, senderClass: cls, claimedJID: claim, speechSeconds: speech,
                          comparisons: scores.map { Comparison(jid: $0.key, score: $0.value) }, names: names)
    }

    func testKnownEnrolledMatchIsVerified() {
        let v = Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": 0.6, "k@lid": 0.2]), thresholds: t)
        XCTAssertEqual(v.kind, .verified); XCTAssertEqual(v.colour, .green)
        XCTAssertEqual(v.comparedJID, "a@lid"); XCTAssertEqual(v.score, 0.6)
        XCTAssertTrue(v.explanation.contains("Abdul"))
    }

    func testVerifiedNeedsTwoSecondsOfSpeech() {
        let v = Verifier.verdict(input(.knownEnrolled, speech: 1.8, scores: ["a@lid": 0.6]), thresholds: t)
        XCTAssertEqual(v.kind, .unclear); XCTAssertEqual(v.reason, "shortClip")
    }

    func testKnownEnrolledMismatchIsTakeover() {
        let v = Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": 0.1, "k@lid": 0.7]), thresholds: t)
        XCTAssertEqual(v.kind, .takeoverSuspected); XCTAssertEqual(v.colour, .red); XCTAssertTrue(v.isRed)
        XCTAssertTrue(v.explanation.contains("does not match"))
        XCTAssertTrue(v.explanation.contains("Karim"))
    }

    func testRedNeedsThreeSecondsOfSpeech() {
        let v = Verifier.verdict(input(.knownEnrolled, speech: 2.5, scores: ["a@lid": 0.1]), thresholds: t)
        XCTAssertEqual(v.kind, .unclear); XCTAssertEqual(v.reason, "shortClip"); XCTAssertEqual(v.colour, .amber)
    }

    func testKnownEnrolledBorderlineIsUnclear() {
        let v = Verifier.verdict(input(.knownEnrolled, scores: ["a@lid": 0.35]), thresholds: t)
        XCTAssertEqual(v.kind, .unclear); XCTAssertEqual(v.reason, "borderline")
    }

    func testKnownUnenrolledIsUnverifiable() {
        let v = Verifier.verdict(input(.knownUnenrolled, scores: ["k@lid": 0.9]), thresholds: t)
        XCTAssertEqual(v.kind, .unverifiable); XCTAssertEqual(v.reason, "notEnrolled"); XCTAssertEqual(v.colour, .grey)
    }

    func testUnknownWithFalseClaimIsImpersonation() {
        let v = Verifier.verdict(input(.unknown, sender: "x@lid", claim: "a@lid", scores: ["a@lid": 0.1, "k@lid": 0.8]), thresholds: t)
        XCTAssertEqual(v.kind, .impersonationSuspected); XCTAssertEqual(v.colour, .red)
        XCTAssertEqual(v.comparedJID, "a@lid"); XCTAssertEqual(v.best?.jid, "k@lid")
        XCTAssertTrue(v.explanation.contains("Abdul"))
    }

    func testUnknownFalseClaimShortClipDowngrades() {
        let v = Verifier.verdict(input(.unknown, sender: "x@lid", claim: "a@lid", speech: 2, scores: ["a@lid": 0.1]), thresholds: t)
        XCTAssertEqual(v.kind, .unclear); XCTAssertEqual(v.reason, "shortClip")
    }

    func testUnknownMatchingSomeoneIsAmber() {
        let v = Verifier.verdict(input(.unknown, sender: "x@lid", scores: ["a@lid": 0.2, "k@lid": 0.7]), thresholds: t)
        XCTAssertEqual(v.kind, .matchesUnsavedNumber); XCTAssertEqual(v.colour, .amber)
        XCTAssertEqual(v.comparedJID, "k@lid"); XCTAssertTrue(v.explanation.contains("Karim"))
    }

    func testUnknownClaimBorderlineIsUnclear() {
        let v = Verifier.verdict(input(.unknown, sender: "x@lid", claim: "a@lid", scores: ["a@lid": 0.3, "k@lid": 0.3]), thresholds: t)
        XCTAssertEqual(v.kind, .unclear); XCTAssertEqual(v.reason, "borderline"); XCTAssertEqual(v.comparedJID, "a@lid")
    }

    func testUnknownNoClaimNoMatchIsGrey() {
        let v = Verifier.verdict(input(.unknown, sender: "x@lid", scores: ["a@lid": 0.2, "k@lid": 0.1]), thresholds: t)
        XCTAssertEqual(v.kind, .unknownVoice); XCTAssertEqual(v.colour, .grey); XCTAssertEqual(v.best?.jid, "a@lid")
    }

    func testTooShortBeatsEverything() {
        let v = Verifier.verdict(input(.knownEnrolled, speech: 1.0, scores: ["a@lid": 0.9]), thresholds: t)
        XCTAssertEqual(v.kind, .unclear); XCTAssertEqual(v.reason, "tooShort")
    }

    func testNoComparisonsIsUnverifiable() {
        let v = Verifier.verdict(input(.knownEnrolled, scores: [:]), thresholds: t)
        XCTAssertEqual(v.kind, .unverifiable); XCTAssertEqual(v.reason, "modelFailed")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `make test` → compile error `cannot find 'Verifier' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Voice/Verdict.swift`:
```swift
import Foundation

public enum SenderClass: String, Sendable, Codable {
    case knownEnrolled, knownUnenrolled, unknown
}

public struct Comparison: Sendable, Equatable, Codable {
    public let jid: String
    public let score: Float
    public init(jid: String, score: Float) { self.jid = jid; self.score = score }
}

public enum VerdictKind: String, Sendable, Codable {
    case verified, takeoverSuspected, impersonationSuspected, matchesUnsavedNumber, unknownVoice, unverifiable, unclear
}

public enum VerdictColour: String, Sendable, Codable { case green, red, amber, grey }

public enum UnclearReason: String, Sendable { case tooShort, shortClip, borderline }
public enum UnverifiableReason: String, Sendable { case notEnrolled, modelFailed, mediaMissing, decodeFailed }

public struct Verdict: Sendable, Equatable {
    public let kind: VerdictKind
    public let colour: VerdictColour
    /// The fingerprint the headline score is against: own (known senders), claimed, or best match.
    public let comparedJID: String?
    public let score: Float?
    public let best: Comparison?
    public let reason: String?
    public let explanation: String
    public var isRed: Bool { colour == .red }

    public init(kind: VerdictKind, colour: VerdictColour, comparedJID: String?, score: Float?,
                best: Comparison?, reason: String?, explanation: String) {
        self.kind = kind; self.colour = colour; self.comparedJID = comparedJID; self.score = score
        self.best = best; self.reason = reason; self.explanation = explanation
    }

    public static func unverifiable(_ reason: UnverifiableReason, explanation: String) -> Verdict {
        Verdict(kind: .unverifiable, colour: .grey, comparedJID: nil, score: nil, best: nil,
                reason: reason.rawValue, explanation: explanation)
    }
}

public struct VerificationInput: Sendable, Equatable {
    public let senderJID: String
    public let senderClass: SenderClass
    public let claimedJID: String?
    public let speechSeconds: Double
    /// Score against every fingerprint. Empty when no embedding could be computed.
    public let comparisons: [Comparison]
    public let names: [String: String]

    public init(senderJID: String, senderClass: SenderClass, claimedJID: String?, speechSeconds: Double,
                comparisons: [Comparison], names: [String: String]) {
        self.senderJID = senderJID; self.senderClass = senderClass; self.claimedJID = claimedJID
        self.speechSeconds = speechSeconds; self.comparisons = comparisons; self.names = names
    }
}
```

`Voice/Verifier.swift`:
```swift
import Foundation

public enum SpeechGates {
    public static let minSpeech = 1.5
    public static let minForRed = 3.0
    public static let minForVerified = 2.0
}

/// Section 8 of the spec: sender classes, claims, tiers, speech gates, evaluation order.
public enum Verifier {
    public static func verdict(_ input: VerificationInput, thresholds t: Thresholds) -> Verdict {
        let name = { (jid: String) in input.names[jid] ?? NameResolver.fallbackName(for: jid) }
        let sender = name(input.senderJID)
        let speech = String(format: "%.1f", input.speechSeconds)

        if input.speechSeconds < SpeechGates.minSpeech {
            return unclear(.tooShort, compared: nil, score: nil, best: nil,
                           "Too short to verify: only \(speech) s of speech.")
        }
        if input.senderClass == .knownUnenrolled {
            return .unverifiable(.notEnrolled, explanation: "Not enough voice history from \(sender) to verify yet.")
        }
        guard let best = input.comparisons.max(by: { $0.score < $1.score }) else {
            return .unverifiable(.modelFailed, explanation: "Couldn't extract a voice from this note.")
        }
        let shortForRed = input.speechSeconds < SpeechGates.minForRed

        switch input.senderClass {
        case .knownEnrolled:
            guard let own = input.comparisons.first(where: { $0.jid == input.senderJID }) else {
                return .unverifiable(.notEnrolled, explanation: "Not enough voice history from \(sender) to verify yet.")
            }
            if own.score >= t.match {
                if input.speechSeconds < SpeechGates.minForVerified {
                    return unclear(.shortClip, compared: own.jid, score: own.score, best: best,
                                   "Sounds like \(sender), but the clip is short (\(speech) s).")
                }
                return Verdict(kind: .verified, colour: .green, comparedJID: own.jid, score: own.score, best: best,
                               reason: nil, explanation: "Voice matches \(sender)'s fingerprint.")
            }
            if own.score <= t.reject {
                if shortForRed {
                    return unclear(.shortClip, compared: own.jid, score: own.score, best: best,
                                   "The voice does not look like \(sender)'s, but the clip is short (\(speech) s).")
                }
                var text = "Sent from \(sender)'s number, but the voice does not match \(sender)'s fingerprint."
                if best.jid != own.jid, best.score >= t.match { text += " Closest known voice: \(name(best.jid))." }
                return Verdict(kind: .takeoverSuspected, colour: .red, comparedJID: own.jid, score: own.score,
                               best: best, reason: nil, explanation: text)
            }
            return unclear(.borderline, compared: own.jid, score: own.score, best: best,
                           "The voice is inconclusive for \(sender).")

        case .unknown:
            let claimed = input.claimedJID.flatMap { c in input.comparisons.first { $0.jid == c } }
            if let claimed, claimed.score <= t.reject {
                if shortForRed {
                    return unclear(.shortClip, compared: claimed.jid, score: claimed.score, best: best,
                                   "Profile name says \(name(claimed.jid)) and the voice does not look like theirs, but the clip is short (\(speech) s).")
                }
                return Verdict(kind: .impersonationSuspected, colour: .red, comparedJID: claimed.jid, score: claimed.score,
                               best: best, reason: nil,
                               explanation: "Profile name says \(name(claimed.jid)), but the voice does not match \(name(claimed.jid))'s fingerprint.")
            }
            if best.score >= t.match {
                var text = "Voice matches \(name(best.jid)), but this number is not saved. Confirm on \(name(best.jid))'s saved number before acting."
                if let claimed, claimed.jid != best.jid { text += " Profile name says \(name(claimed.jid))." }
                return Verdict(kind: .matchesUnsavedNumber, colour: .amber, comparedJID: best.jid, score: best.score,
                               best: best, reason: nil, explanation: text)
            }
            if let claimed {
                return unclear(.borderline, compared: claimed.jid, score: claimed.score, best: best,
                               "Profile name says \(name(claimed.jid)); the voice is inconclusive.")
            }
            return Verdict(kind: .unknownVoice, colour: .grey, comparedJID: nil, score: nil, best: best, reason: nil,
                           explanation: "Voice does not match anyone you know.")

        case .knownUnenrolled:
            return .unverifiable(.notEnrolled, explanation: "Not enough voice history from \(sender) to verify yet.")
        }
    }

    private static func unclear(_ reason: UnclearReason, compared: String?, score: Float?, best: Comparison?,
                                _ explanation: String) -> Verdict {
        Verdict(kind: .unclear, colour: .amber, comparedJID: compared, score: score, best: best,
                reason: reason.rawValue, explanation: explanation)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**
Run: `make test` → `VerifierTests` 13 tests pass.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): verdict engine with sender classes, claims, tiers and speech gates

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 12: Calibrator

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/Voice/Calibrator.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/CalibratorTests.swift`

- [ ] **Step 1: Write the failing test**
```swift
import XCTest
@testable import AntiFishCore

final class CalibratorTests: XCTestCase {
    /// Six synthetic speakers in 6-d: speaker i points along axis i with a small, note-specific lean
    /// toward axis i+1. Genuine cosines land near 0.98, impostor cosines below 0.4.
    private func syntheticNotes(speakers: Int, notesEach: Int = 4) -> [EnrolledNote] {
        (0..<speakers).flatMap { i in
            (0..<notesEach).map { k in
                var v = [Float](repeating: 0, count: 6)
                v[i % 6] = 1
                v[(i + 1) % 6] = 0.1 * Float(k + 1)
                return EnrolledNote(jid: "s\(i)@lid", messagePK: Int64(i * 10 + k), embedding: Vector.normalized(v),
                                    speechSeconds: 10, date: Date(timeIntervalSinceReferenceDate: 1_000 + Double(k)))
            }
        }
    }

    func testPercentileNearestRank() {
        let v: [Float] = [5, 1, 4, 2, 3]
        XCTAssertEqual(Calibrator.percentile(v, 0), 1)
        XCTAssertEqual(Calibrator.percentile(v, 50), 3)
        XCTAssertEqual(Calibrator.percentile(v, 100), 5)
        XCTAssertEqual(Calibrator.percentile(v, 2), 1)
        XCTAssertEqual(Calibrator.percentile([], 50), 0)
    }

    func testWellSeparatedSpeakersCalibrate() {
        let result = Calibrator.calibrate(notes: syntheticNotes(speakers: 6), now: Date(timeIntervalSinceReferenceDate: 5))
        XCTAssertTrue(result.thresholds.calibrated)
        XCTAssertEqual(result.contactCount, 6)
        XCTAssertEqual(result.genuineCount, 24)
        XCTAssertEqual(result.impostorCount, 24 * 5)
        XCTAssertLessThan(result.thresholds.reject, result.thresholds.match)
        XCTAssertGreaterThan(result.thresholds.match, 0.9)
        XCTAssertGreaterThanOrEqual(result.thresholds.reject, 0.3)
        XCTAssertLessThanOrEqual(result.thresholds.reject, 0.4)
        XCTAssertGreaterThan(result.genuineMedian, result.impostorMedian)
        XCTAssertEqual(result.calibratedAt, Date(timeIntervalSinceReferenceDate: 5))
    }

    func testFewerThanFiveContactsKeepsDefaults() {
        let result = Calibrator.calibrate(notes: syntheticNotes(speakers: 4))
        XCTAssertEqual(result.thresholds, Thresholds())
        XCTAssertFalse(result.thresholds.calibrated)
        XCTAssertEqual(result.contactCount, 4)
    }

    func testContactsWithFewerThanThreeNotesAreExcluded() {
        var notes = syntheticNotes(speakers: 5)
        notes.append(EnrolledNote(jid: "thin@lid", messagePK: 999, embedding: [1, 0, 0, 0, 0, 0], speechSeconds: 5, date: Date()))
        XCTAssertEqual(Calibrator.calibrate(notes: notes).contactCount, 5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `make test` → compile error `cannot find 'Calibrator' in scope`.

- [ ] **Step 3: Write minimal implementation**
```swift
import Foundation

public struct CalibrationResult: Sendable, Equatable, Codable {
    public let thresholds: Thresholds
    public let contactCount: Int
    public let genuineCount: Int
    public let impostorCount: Int
    public let genuineMedian: Float
    public let impostorMedian: Float
    public let calibratedAt: Date
}

/// Section 8.3 of the spec. Learns thresholds from the user's own enrolled contacts:
/// green = a stranger scores this high ≤1% of the time; red = a real note scores this low ≤2% of the time.
public enum Calibrator {
    public static let minContacts = 5
    public static let minNotesPerContact = 3

    public static func calibrate(notes: [EnrolledNote], defaults: Thresholds = Thresholds(), now: Date = Date()) -> CalibrationResult {
        let bySender = Dictionary(grouping: notes.filter { !$0.embedding.isEmpty }, by: \.jid)
            .filter { $0.value.count >= minNotesPerContact }
        let centroids = bySender.mapValues { Vector.centroid($0.map(\.embedding)) }

        var genuine: [Float] = []
        var impostor: [Float] = []
        for (jid, own) in bySender {
            for (index, note) in own.enumerated() {
                var others = own
                others.remove(at: index)
                genuine.append(Vector.cosine(note.embedding, Vector.centroid(others.map(\.embedding))))
                for (otherJID, centroid) in centroids where otherJID != jid {
                    impostor.append(Vector.cosine(note.embedding, centroid))
                }
            }
        }

        var thresholds = defaults
        if bySender.count >= minContacts, !genuine.isEmpty, !impostor.isEmpty {
            let imp99 = percentile(impostor, 99)
            let gen2 = percentile(genuine, 2)
            thresholds = Thresholds(reject: min(imp99, gen2), match: max(imp99, gen2), calibrated: true)
        }
        return CalibrationResult(thresholds: thresholds, contactCount: bySender.count,
                                 genuineCount: genuine.count, impostorCount: impostor.count,
                                 genuineMedian: median(genuine), impostorMedian: median(impostor), calibratedAt: now)
    }

    /// Nearest-rank (rounded down) percentile; `p` in 0...100. Empty input yields 0.
    public static func percentile(_ values: [Float], _ p: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int((p / 100) * Double(sorted.count - 1))
        return sorted[max(0, min(sorted.count - 1, index))]
    }

    public static func median(_ values: [Float]) -> Float { percentile(values, 50) }
}
```

- [ ] **Step 4: Run test to verify it passes**
Run: `make test` → `CalibratorTests` 4 tests pass.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): calibrate thresholds from genuine and impostor score distributions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 13: AppDatabase (the app's own GRDB store)

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/Store/AppDatabase.swift`
- Create: `AntiFishCore/Sources/AntiFishCore/Store/Records.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/AppDatabaseTests.swift`

- [ ] **Step 1: Write the failing test**
```swift
import XCTest
@testable import AntiFishCore

final class AppDatabaseTests: XCTestCase {
    private let when = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testEnrollmentNotesRoundTripPerContact() throws {
        let db = try AppDatabase(url: nil)
        let notes = [EnrolledNote(jid: "a@lid", messagePK: 1, embedding: [0.5, -0.25], speechSeconds: 3, date: when),
                     EnrolledNote(jid: "a@lid", messagePK: 2, embedding: [1, 0], speechSeconds: 4, date: when)]
        try db.replaceEnrollment(jid: "a@lid", notes: notes)
        try db.replaceEnrollment(jid: "b@lid", notes: [EnrolledNote(jid: "b@lid", messagePK: 3, embedding: [0, 1], speechSeconds: 5, date: when)])
        XCTAssertEqual(try db.enrollmentNotes(jid: "a@lid"), notes)
        XCTAssertEqual(try db.allEnrollmentNotes().count, 3)
        try db.replaceEnrollment(jid: "a@lid", notes: [notes[1]])
        XCTAssertEqual(try db.enrollmentNotes(jid: "a@lid").map(\.messagePK), [2])
    }

    func testFingerprintsAreReplacedWholesale() throws {
        let db = try AppDatabase(url: nil)
        let fp = Fingerprint(jid: "a@lid", centroid: [1, 0], noteCount: 3, speechSeconds: 40, lastNoteDate: when, modelVersion: "m1")
        try db.saveFingerprints([fp])
        XCTAssertEqual(try db.fingerprints(), [fp])
        try db.saveFingerprints([])
        XCTAssertEqual(try db.fingerprints(), [])
    }

    func testVerdictsNewestFirstAndLookupByPK() throws {
        let db = try AppDatabase(url: nil)
        let note1 = VoiceNoteRecord(messagePK: 10, chatJID: "a@lid", senderJID: "a@lid", isFromMe: false, date: when, durationSeconds: 7, relativeMediaPath: "Message/Media/a@lid/1/2/x.opus", chatIsGroup: false)
        let note2 = VoiceNoteRecord(messagePK: 11, chatJID: "g@g.us", senderJID: "k@lid", isFromMe: false, date: when.addingTimeInterval(60), durationSeconds: 3, relativeMediaPath: "Message/Media/g@g.us/3/4/y.opus", chatIsGroup: true)
        let verdict = Verdict(kind: .verified, colour: .green, comparedJID: "a@lid", score: 0.71, best: Comparison(jid: "a@lid", score: 0.71), reason: nil, explanation: "ok")
        try db.saveVerdict(VerdictRecord(note: note1, verdict: verdict, speechSeconds: 5.5, computedAt: when, modelVersion: "m1"))
        try db.saveVerdict(VerdictRecord(note: note2, verdict: .unverifiable(.mediaMissing, explanation: "gone"), speechSeconds: 0, computedAt: when, modelVersion: "m1"))
        let all = try db.verdicts(limit: 10)
        XCTAssertEqual(all.map(\.messagePK), [11, 10])
        let first = try XCTUnwrap(try db.verdict(messagePK: 10))
        XCTAssertEqual(first.kind, "verified"); XCTAssertEqual(first.colour, "green")
        XCTAssertEqual(first.score ?? 0, 0.71, accuracy: 1e-6); XCTAssertEqual(first.bestJID, "a@lid")
        XCTAssertEqual(first.chatJID, "a@lid"); XCTAssertEqual(first.durationSeconds, 7)
        XCTAssertEqual(try db.verdict(messagePK: 11)?.reason, "mediaMissing")
        XCTAssertNil(try db.verdict(messagePK: 12))
    }

    func testContactsUpsertAndFlags() throws {
        let db = try AppDatabase(url: nil)
        try db.saveContacts([ContactRecord(jid: "a@lid", displayName: "Abdul", isSaved: true, pinned: false, blacklisted: false, avatarPath: nil)])
        try db.saveContacts([ContactRecord(jid: "a@lid", displayName: "Abdul T.", isSaved: true, pinned: true, blacklisted: false, avatarPath: "p")])
        let contacts = try db.contacts()
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0].displayName, "Abdul T."); XCTAssertTrue(contacts[0].pinned)
    }

    func testSettingsThresholdsAndCursor() throws {
        let db = try AppDatabase(url: nil)
        XCTAssertEqual(try db.thresholds(), Thresholds())
        XCTAssertEqual(try db.lastSeenMessagePK(), 0)
        let result = CalibrationResult(thresholds: Thresholds(reject: 0.3, match: 0.6, calibrated: true), contactCount: 7,
                                       genuineCount: 20, impostorCount: 120, genuineMedian: 0.8, impostorMedian: 0.1, calibratedAt: when)
        try db.saveCalibration(result)
        XCTAssertEqual(try db.thresholds(), result.thresholds)
        XCTAssertEqual(try db.calibration(), result)
        try db.setLastSeenMessagePK(4242)
        XCTAssertEqual(try db.lastSeenMessagePK(), 4242)
    }

    func testFileBackedDatabaseCreatesDirectory() throws {
        let url = try TestEnv.tempDir().appendingPathComponent("nested/dir/antifish.sqlite")
        _ = try AppDatabase(url: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `make test` → compile error `cannot find 'AppDatabase' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Store/Records.swift`:
```swift
import Foundation
import GRDB

public struct ContactRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "contact"
    public var jid: String
    public var displayName: String
    public var isSaved: Bool
    public var pinned: Bool
    public var blacklisted: Bool
    public var avatarPath: String?

    public init(jid: String, displayName: String, isSaved: Bool, pinned: Bool, blacklisted: Bool, avatarPath: String?) {
        self.jid = jid; self.displayName = displayName; self.isSaved = isSaved
        self.pinned = pinned; self.blacklisted = blacklisted; self.avatarPath = avatarPath
    }
}

public struct EnrollmentNoteRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "enrollmentNote"
    public var messagePK: Int64
    public var jid: String
    public var embedding: Data
    public var speechSeconds: Double
    public var date: Date

    public init(_ note: EnrolledNote) {
        messagePK = note.messagePK; jid = note.jid; embedding = Vector.toData(note.embedding)
        speechSeconds = note.speechSeconds; date = note.date
    }
    public var note: EnrolledNote {
        EnrolledNote(jid: jid, messagePK: messagePK, embedding: Vector.fromData(embedding), speechSeconds: speechSeconds, date: date)
    }
}

public struct FingerprintRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "fingerprint"
    public var jid: String
    public var centroid: Data
    public var noteCount: Int
    public var speechSeconds: Double
    public var lastNoteDate: Date
    public var modelVersion: String

    public init(_ fp: Fingerprint) {
        jid = fp.jid; centroid = Vector.toData(fp.centroid); noteCount = fp.noteCount
        speechSeconds = fp.speechSeconds; lastNoteDate = fp.lastNoteDate; modelVersion = fp.modelVersion
    }
    public var fingerprint: Fingerprint {
        Fingerprint(jid: jid, centroid: Vector.fromData(centroid), noteCount: noteCount,
                    speechSeconds: speechSeconds, lastNoteDate: lastNoteDate, modelVersion: modelVersion)
    }
}

public struct VerdictRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "verdict"
    public var messagePK: Int64
    public var senderJID: String
    public var chatJID: String
    public var chatIsGroup: Bool
    public var date: Date
    public var durationSeconds: Int
    public var relativeMediaPath: String
    public var kind: String
    public var colour: String
    public var comparedJID: String?
    public var score: Double?
    public var bestJID: String?
    public var bestScore: Double?
    public var reason: String?
    public var explanation: String
    public var speechSeconds: Double
    public var computedAt: Date
    public var modelVersion: String

    public init(note: VoiceNoteRecord, verdict: Verdict, speechSeconds: Double, computedAt: Date, modelVersion: String) {
        messagePK = note.messagePK; senderJID = note.senderJID; chatJID = note.chatJID; chatIsGroup = note.chatIsGroup
        date = note.date; durationSeconds = note.durationSeconds; relativeMediaPath = note.relativeMediaPath
        kind = verdict.kind.rawValue; colour = verdict.colour.rawValue; comparedJID = verdict.comparedJID
        score = verdict.score.map(Double.init); bestJID = verdict.best?.jid; bestScore = verdict.best.map { Double($0.score) }
        reason = verdict.reason; explanation = verdict.explanation
        self.speechSeconds = speechSeconds; self.computedAt = computedAt; self.modelVersion = modelVersion
    }

    public var isRed: Bool { colour == VerdictColour.red.rawValue }
}

public struct SettingRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "setting"
    public var key: String
    public var value: String
}
```

`Store/AppDatabase.swift`:
```swift
import Foundation
import GRDB

/// AntiFish's own store: contacts, enrolment notes, fingerprints, verdicts, settings.
public final class AppDatabase: Sendable {
    public let queue: DatabaseQueue

    public static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AntiFish/antifish.sqlite")
    }

    /// `nil` opens an in-memory database (tests).
    public init(url: URL?) throws {
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            queue = try DatabaseQueue(path: url.path)
        } else {
            queue = try DatabaseQueue()
        }
        try Self.migrator.migrate(queue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "contact") { t in
                t.primaryKey("jid", .text)
                t.column("displayName", .text).notNull()
                t.column("isSaved", .boolean).notNull().defaults(to: false)
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("blacklisted", .boolean).notNull().defaults(to: false)
                t.column("avatarPath", .text)
            }
            try db.create(table: "enrollmentNote") { t in
                t.primaryKey("messagePK", .integer)
                t.column("jid", .text).notNull().indexed()
                t.column("embedding", .blob).notNull()
                t.column("speechSeconds", .double).notNull()
                t.column("date", .datetime).notNull()
            }
            try db.create(table: "fingerprint") { t in
                t.primaryKey("jid", .text)
                t.column("centroid", .blob).notNull()
                t.column("noteCount", .integer).notNull()
                t.column("speechSeconds", .double).notNull()
                t.column("lastNoteDate", .datetime).notNull()
                t.column("modelVersion", .text).notNull()
            }
            try db.create(table: "verdict") { t in
                t.primaryKey("messagePK", .integer)
                t.column("senderJID", .text).notNull().indexed()
                t.column("chatJID", .text).notNull()
                t.column("chatIsGroup", .boolean).notNull()
                t.column("date", .datetime).notNull().indexed()
                t.column("durationSeconds", .integer).notNull()
                t.column("relativeMediaPath", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("colour", .text).notNull()
                t.column("comparedJID", .text)
                t.column("score", .double)
                t.column("bestJID", .text)
                t.column("bestScore", .double)
                t.column("reason", .text)
                t.column("explanation", .text).notNull()
                t.column("speechSeconds", .double).notNull()
                t.column("computedAt", .datetime).notNull()
                t.column("modelVersion", .text).notNull()
            }
            try db.create(table: "setting") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }
        return migrator
    }

    // MARK: Contacts
    public func saveContacts(_ contacts: [ContactRecord]) throws {
        try queue.write { db in for c in contacts { try c.save(db) } }
    }
    public func contacts() throws -> [ContactRecord] {
        try queue.read { db in try ContactRecord.order(Column("displayName")).fetchAll(db) }
    }

    // MARK: Enrolment
    public func replaceEnrollment(jid: String, notes: [EnrolledNote]) throws {
        try queue.write { db in
            try EnrollmentNoteRecord.filter(Column("jid") == jid).deleteAll(db)
            for note in notes { try EnrollmentNoteRecord(note).insert(db) }
        }
    }
    public func enrollmentNotes(jid: String) throws -> [EnrolledNote] {
        try queue.read { db in
            try EnrollmentNoteRecord.filter(Column("jid") == jid).order(Column("messagePK")).fetchAll(db).map(\.note)
        }
    }
    public func allEnrollmentNotes() throws -> [EnrolledNote] {
        try queue.read { db in try EnrollmentNoteRecord.order(Column("messagePK")).fetchAll(db).map(\.note) }
    }

    // MARK: Fingerprints
    public func saveFingerprints(_ fingerprints: [Fingerprint]) throws {
        try queue.write { db in
            try FingerprintRecord.deleteAll(db)
            for fp in fingerprints { try FingerprintRecord(fp).insert(db) }
        }
    }
    public func fingerprints() throws -> [Fingerprint] {
        try queue.read { db in try FingerprintRecord.order(Column("lastNoteDate").desc).fetchAll(db).map(\.fingerprint) }
    }

    // MARK: Verdicts
    public func saveVerdict(_ record: VerdictRecord) throws {
        try queue.write { db in try record.save(db) }
    }
    public func verdicts(limit: Int) throws -> [VerdictRecord] {
        try queue.read { db in try VerdictRecord.order(Column("date").desc, Column("messagePK").desc).limit(limit).fetchAll(db) }
    }
    public func verdict(messagePK: Int64) throws -> VerdictRecord? {
        try queue.read { db in try VerdictRecord.fetchOne(db, key: messagePK) }
    }

    // MARK: Settings
    public func setting(_ key: String) throws -> String? {
        try queue.read { db in try SettingRecord.fetchOne(db, key: key)?.value }
    }
    public func setSetting(_ key: String, _ value: String) throws {
        try queue.write { db in try SettingRecord(key: key, value: value).save(db) }
    }
    public func lastSeenMessagePK() throws -> Int64 {
        Int64(try setting("lastSeenMessagePK") ?? "0") ?? 0
    }
    public func setLastSeenMessagePK(_ pk: Int64) throws {
        try setSetting("lastSeenMessagePK", String(pk))
    }
    public func calibration() throws -> CalibrationResult? {
        guard let json = try setting("calibration") else { return nil }
        return try JSONDecoder().decode(CalibrationResult.self, from: Data(json.utf8))
    }
    public func saveCalibration(_ result: CalibrationResult) throws {
        let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        try setSetting("calibration", json)
    }
    public func thresholds() throws -> Thresholds {
        try calibration()?.thresholds ?? Thresholds()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**
Run: `make test` → `AppDatabaseTests` 6 tests pass.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): GRDB app store for contacts, enrolment, fingerprints, verdicts, settings

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 14: ContainerWatcher (FSEvents + safety-net poll)

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/WhatsApp/ContainerWatcher.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/ContainerWatcherTests.swift`

- [ ] **Step 1: Write the failing test**
```swift
import XCTest
@testable import AntiFishCore

final class ContainerWatcherTests: XCTestCase {
    func testRelevance() {
        XCTAssertTrue(ContainerWatcher.isRelevant("/c/Message/Media/111@lid/a/b/x.opus"))
        XCTAssertTrue(ContainerWatcher.isRelevant("/c/Message/Media/111@lid/a/b/x.M4A"))
        XCTAssertTrue(ContainerWatcher.isRelevant("/c/ChatStorage.sqlite-wal"))
        XCTAssertTrue(ContainerWatcher.isRelevant("/c/ChatStorage.sqlite"))
        XCTAssertFalse(ContainerWatcher.isRelevant("/c/Message/Media/111@lid/a/b/x.jpg"))
        XCTAssertFalse(ContainerWatcher.isRelevant("/c/Media/Profile/x.opus"))
        XCTAssertFalse(ContainerWatcher.isRelevant("/c/ContactsV2.sqlite-wal"))
    }

    func testFiresOnceForANewVoiceNoteFile() throws {
        let root = try TestEnv.tempDir()
        let mediaDir = root.appendingPathComponent("Message/Media/111@lid/a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        let fired = expectation(description: "watcher fired")
        fired.assertForOverFulfill = false
        let watcher = ContainerWatcher(root: root, debounce: 0.3, pollInterval: 3600) { fired.fulfill() }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)   // let the stream attach before writing
        try Data([1, 2, 3]).write(to: mediaDir.appendingPathComponent("n.opus"))
        wait(for: [fired], timeout: 8)
    }

    func testIgnoresIrrelevantFiles() throws {
        let root = try TestEnv.tempDir()
        let mediaDir = root.appendingPathComponent("Message/Media/111@lid/a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        let fired = expectation(description: "should not fire")
        fired.isInverted = true
        let watcher = ContainerWatcher(root: root, debounce: 0.3, pollInterval: 3600) { fired.fulfill() }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)
        try Data([1]).write(to: mediaDir.appendingPathComponent("thumb.jpg"))
        wait(for: [fired], timeout: 3)
    }

    func testStopIsIdempotent() throws {
        let watcher = ContainerWatcher(root: try TestEnv.tempDir(), debounce: 0.1, pollInterval: 3600) {}
        watcher.start()
        watcher.stop()
        watcher.stop()
    }
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `make test` → compile error `cannot find 'ContainerWatcher' in scope`.

- [ ] **Step 3: Write minimal implementation**
```swift
import CoreServices
import Foundation

/// Watches WhatsApp's container for new voice-note files and message-database writes.
/// Emits one debounced callback per burst of changes, plus a periodic safety-net poll.
/// Callers must call `stop()` before releasing the watcher.
public final class ContainerWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable () -> Void

    private let root: URL
    private let debounce: TimeInterval
    private let pollInterval: TimeInterval
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.magnetismstudios.antifish.watcher")
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private var timer: DispatchSourceTimer?

    public init(root: URL, debounce: TimeInterval = 1.5, pollInterval: TimeInterval = 60, handler: @escaping Handler) {
        self.root = root
        self.debounce = debounce
        self.pollInterval = pollInterval
        self.handler = handler
    }

    /// Voice-note files under Message/Media, and the message database or its WAL.
    static func isRelevant(_ path: String) -> Bool {
        if path.hasSuffix("/ChatStorage.sqlite-wal") || path.hasSuffix("/ChatStorage.sqlite") { return true }
        guard path.contains("/Message/Media/") else { return false }
        let lower = path.lowercased()
        return lower.hasSuffix(".opus") || lower.hasSuffix(".m4a")
    }

    public func start() {
        queue.sync {
            guard stream == nil else { return }
            var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                               retain: nil, release: nil, copyDescription: nil)
            let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
                guard let info, count > 0 else { return }
                let watcher = Unmanaged<ContainerWatcher>.fromOpaque(info).takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
                if paths.contains(where: { ($0 as? String).map(ContainerWatcher.isRelevant) ?? false }) {
                    watcher.scheduleFire()
                }
            }
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
            guard let created = FSEventStreamCreate(nil, callback, &context, [root.path] as CFArray,
                                                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags) else { return }
            FSEventStreamSetDispatchQueue(created, queue)
            FSEventStreamStart(created)
            stream = created

            let poll = DispatchSource.makeTimerSource(queue: queue)
            poll.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
            poll.setEventHandler { [weak self] in self?.handler() }
            poll.resume()
            timer = poll
        }
    }

    public func stop() {
        queue.sync {
            if let stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
            timer?.cancel()
            timer = nil
            pending?.cancel()
            pending = nil
        }
    }

    /// Called on `queue` by the FSEvents callback.
    private func scheduleFire() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.handler() }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**
Run: `make test` → `ContainerWatcherTests` 4 tests pass (the two FSEvents tests take a few seconds).

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): watch WhatsApp container for new voice notes via FSEvents

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 15: ClaimMatcher, pending-media cursor, Coordinator

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/Voice/ClaimMatcher.swift`
- Modify: `AntiFishCore/Sources/AntiFishCore/WhatsApp/VoiceNoteQuery.swift` (add `pendingFloor`)
- Create: `AntiFishCore/Sources/AntiFishCore/Pipeline/Coordinator.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/ClaimMatcherTests.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/PendingFloorTests.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Integration/CoordinatorIntegrationTests.swift`

- [ ] **Step 1: Write the failing tests**

`Unit/ClaimMatcherTests.swift`:
```swift
import XCTest
@testable import AntiFishCore

final class ClaimMatcherTests: XCTestCase {
    private let names = ["a@lid": "Abdul Test", "k@lid": "Karim Élan", "jo@lid": "Jo Li"]
    private let enrolled = ["a@lid", "k@lid", "jo@lid"]

    func testNormalize() {
        XCTAssertEqual(ClaimMatcher.normalize("  Karim  Élan!! "), "karim elan")
        XCTAssertEqual(ClaimMatcher.normalize("ABDUL-TEST"), "abdultest")
    }

    func testFullNameMatch() {
        XCTAssertEqual(ClaimMatcher.claimedJID(pushName: "abdul test", enrolled: enrolled, names: names), "a@lid")
    }

    func testFirstNameMatchNeedsThreeLetters() {
        XCTAssertEqual(ClaimMatcher.claimedJID(pushName: "Karim 🔥", enrolled: enrolled, names: names), "k@lid")
        XCTAssertNil(ClaimMatcher.claimedJID(pushName: "Jo", enrolled: enrolled, names: names))
        XCTAssertEqual(ClaimMatcher.claimedJID(pushName: "Jo Li", enrolled: enrolled, names: names), "jo@lid")
    }

    func testNoClaim() {
        XCTAssertNil(ClaimMatcher.claimedJID(pushName: "Someone Else", enrolled: enrolled, names: names))
        XCTAssertNil(ClaimMatcher.claimedJID(pushName: nil, enrolled: enrolled, names: names))
        XCTAssertNil(ClaimMatcher.claimedJID(pushName: "", enrolled: enrolled, names: names))
    }
}
```

`Unit/PendingFloorTests.swift`:
```swift
import XCTest
@testable import AntiFishCore

final class PendingFloorTests: XCTestCase {
    func testOldestIncomingNoteWithoutFileSinceDate() throws {
        let store = try ChatStore(url: try FixtureDB.standardPair().chat)
        // Row 1002 is an incoming voice note whose media has no local path yet.
        XCTAssertEqual(try VoiceNoteQuery.pendingFloor(store, since: Date(timeIntervalSinceReferenceDate: 0)), 1002)
        XCTAssertNil(try VoiceNoteQuery.pendingFloor(store, since: Date(timeIntervalSinceReferenceDate: 900_000_000)))
    }
}
```

`Integration/CoordinatorIntegrationTests.swift`:
```swift
import XCTest
@testable import AntiFishCore

final class CoordinatorIntegrationTests: XCTestCase {
    /// Enrols this Mac's real contacts, calibrates, and verifies the newest incoming note. Takes a few minutes.
    func testEnrollCalibrateAndVerifyOnRealData() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let config = CoordinatorConfig(locator: ContainerLocator(), models: ModelPaths(directory: TestEnv.modelsDir))
        let db = try AppDatabase(url: nil)
        let engine = try VoiceEngine(models: config.models, numThreads: 4)
        let coordinator = Coordinator(config: config, db: db, engine: engine)

        let fingerprints = try await coordinator.enrollAll()
        XCTAssertGreaterThanOrEqual(fingerprints.count, 10)
        XCTAssertTrue(fingerprints.allSatisfy { $0.noteCount >= 3 && $0.speechSeconds >= 30 && $0.centroid.count == 256 })

        let calibration = try XCTUnwrap(try db.calibration())
        XCTAssertGreaterThanOrEqual(calibration.contactCount, 5)
        XCTAssertTrue(calibration.thresholds.calibrated)
        XCTAssertLessThan(calibration.thresholds.reject, calibration.thresholds.match)
        XCTAssertGreaterThan(calibration.genuineMedian, calibration.impostorMedian + 0.15)

        let contacts = try db.contacts()
        XCTAssertGreaterThanOrEqual(contacts.count, fingerprints.count)
        XCTAssertTrue(contacts.contains { $0.isSaved })

        let store = try ChatStore.open(url: config.locator.chatStorageURL)
        let newest = try XCTUnwrap(try VoiceNoteQuery.fetch(store).last { note in
            !note.isFromMe && !note.senderJID.hasPrefix("status@")
                && FileManager.default.fileExists(atPath: config.locator.mediaURL(relativePath: note.relativeMediaPath).path)
        })
        let record = try await coordinator.verify(newest)
        XCTAssertEqual(record.messagePK, newest.messagePK)
        XCTAssertNotEqual(record.reason, "mediaMissing")
        XCTAssertNotEqual(record.reason, "decodeFailed")
        XCTAssertEqual(try db.verdict(messagePK: newest.messagePK)?.kind, record.kind)
    }

    func testProcessNewVerifiesRecentNotesAndAdvancesCursor() async throws {
        try TestEnv.skipUnlessRealWA()
        try TestEnv.skipUnlessModels()
        let config = CoordinatorConfig(locator: ContainerLocator(), models: ModelPaths(directory: TestEnv.modelsDir))
        let db = try AppDatabase(url: nil)
        let coordinator = Coordinator(config: config, db: db, engine: try VoiceEngine(models: config.models, numThreads: 4))
        let store = try ChatStore.open(url: config.locator.chatStorageURL)
        let maxPK = try VoiceNoteQuery.maxMessagePK(store)
        try db.setLastSeenMessagePK(maxPK - 300)
        let verdicts = try await coordinator.processNew()
        XCTAssertGreaterThan(verdicts.count, 0)
        XCTAssertTrue(verdicts.allSatisfy { $0.messagePK > maxPK - 300 })
        XCTAssertGreaterThanOrEqual(try db.lastSeenMessagePK(), maxPK - 300)
        XCTAssertEqual(try await coordinator.processNew().count, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**
Run: `make test` → compile errors `cannot find 'ClaimMatcher' in scope`, `has no member 'pendingFloor'`.

- [ ] **Step 3: Write minimal implementation**

`Voice/ClaimMatcher.swift`:
```swift
import Foundation

/// Section 8.1: does an unknown sender's (self-chosen) push name claim to be an enrolled contact?
public enum ClaimMatcher {
    /// Lowercase, diacritics stripped, letters and single spaces only.
    public static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .filter { $0.isLetter || $0 == " " }
            .split(separator: " ")
            .joined(separator: " ")
    }

    public static func claimedJID(pushName: String?, enrolled: [String], names: [String: String]) -> String? {
        guard let push = pushName.map(normalize), !push.isEmpty else { return nil }
        let pushFirst = push.split(separator: " ").first.map(String.init) ?? push
        for jid in enrolled {
            guard let full = names[jid].map(normalize), !full.isEmpty else { continue }
            if full == push { return jid }
            let first = full.split(separator: " ").first.map(String.init) ?? full
            if first.count >= 3, first == pushFirst { return jid }
        }
        return nil
    }
}
```

Add to `WhatsApp/VoiceNoteQuery.swift` inside `enum VoiceNoteQuery`:
```swift
    /// Oldest incoming voice note newer than `since` whose media has not been downloaded yet.
    /// The live cursor must not advance past it, or the note is missed when the file arrives.
    public static func pendingFloor(_ store: ChatStore, since: Date) throws -> Int64? {
        try store.queue.read { db in
            try Int64.fetchOne(db, sql: """
                SELECT MIN(m.Z_PK) FROM ZWAMESSAGE m
                JOIN ZWAMEDIAITEM mi ON mi.Z_PK = m.ZMEDIAITEM
                WHERE m.ZMESSAGETYPE = 3 AND m.ZISFROMME = 0 AND mi.ZMEDIALOCALPATH IS NULL
                  AND m.ZMESSAGEDATE > :since
                """, arguments: ["since": since.timeIntervalSinceReferenceDate])
        }
    }
```

`Pipeline/Coordinator.swift`:
```swift
import Foundation
import os

public struct CoordinatorConfig: Sendable {
    public var locator: ContainerLocator
    public var models: ModelPaths
    public var policy = EnrollmentPolicy()
    public var mediaRetries = 3
    public var mediaRetryDelay: TimeInterval = 3.3
    public var pendingLookback: TimeInterval = 7 * 86_400

    public init(locator: ContainerLocator, models: ModelPaths) {
        self.locator = locator
        self.models = models
    }
}

public enum CoordinatorEvent: Sendable, Equatable {
    case enrollmentProgress(done: Int, total: Int)
    case enrollmentFinished(fingerprints: Int, protected: [String])
    case verdict(VerdictRecord)
    case error(String)
}

/// Orchestrates enrolment, live verification and persistence. One instance per app.
public actor Coordinator {
    private let config: CoordinatorConfig
    private let db: AppDatabase
    private let engine: VoiceEngine
    private let logger = Logger(subsystem: "com.magnetismstudios.antifish", category: "coordinator")
    private var chat: ChatStore?
    private var tables = NameTables()
    private let continuation: AsyncStream<CoordinatorEvent>.Continuation
    public nonisolated let events: AsyncStream<CoordinatorEvent>

    public init(config: CoordinatorConfig, db: AppDatabase, engine: VoiceEngine) {
        self.config = config
        self.db = db
        self.engine = engine
        let (stream, continuation) = AsyncStream<CoordinatorEvent>.makeStream(bufferingPolicy: .bufferingNewest(256))
        self.events = stream
        self.continuation = continuation
    }

    // MARK: Stores

    private func openStores() throws -> ChatStore {
        let store = try chat ?? ChatStore.open(url: config.locator.chatStorageURL)
        chat = store
        let contacts = try? ChatStore.open(url: config.locator.contactsURL)
        tables = try NameTables.load(chat: store, contacts: contacts)
        return store
    }

    private func isCandidate(_ note: VoiceNoteRecord) -> Bool {
        !note.isFromMe && !note.senderJID.isEmpty && !note.senderJID.hasPrefix("status@")
    }

    private func mediaExists(_ note: VoiceNoteRecord) -> Bool {
        FileManager.default.fileExists(atPath: config.locator.mediaURL(relativePath: note.relativeMediaPath).path)
    }

    // MARK: Enrolment (spec section 7)

    @discardableResult
    public func enrollAll() async throws -> [Fingerprint] {
        let store = try openStores()
        let policy = config.policy
        let blacklist = Set(try db.contacts().filter(\.blacklisted).map(\.jid))
        let candidates = try VoiceNoteQuery.fetch(store).filter { isCandidate($0) && mediaExists($0) }
        let bySender = Dictionary(grouping: candidates, by: \.senderJID)
            .filter { $0.value.count >= policy.minNotes && !blacklist.contains($0.key) }
        let todo = bySender.values.flatMap { $0.sorted { $0.date > $1.date }.prefix(policy.maxNotes) }

        let sameModel = (try db.setting("enrollmentModelVersion")) == engine.modelVersion
        let cached = sameModel
            ? Dictionary((try db.allEnrollmentNotes()).map { ($0.messagePK, $0) }, uniquingKeysWith: { a, _ in a })
            : [:]

        var notes: [EnrolledNote] = []
        for (index, note) in todo.enumerated() {
            if let hit = cached[note.messagePK] {
                notes.append(hit)
            } else {
                do {
                    let analysis = try await engine.analyze(url: config.locator.mediaURL(relativePath: note.relativeMediaPath))
                    notes.append(EnrolledNote(jid: note.senderJID, messagePK: note.messagePK, embedding: analysis.embedding,
                                              speechSeconds: analysis.speechSeconds, date: note.date))
                } catch {
                    logger.notice("skipping note \(note.messagePK, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
            continuation.yield(.enrollmentProgress(done: index + 1, total: todo.count))
        }

        let fingerprints = Enroller.fingerprints(from: notes, policy: policy, modelVersion: engine.modelVersion)
        for fp in fingerprints {
            let own = notes.filter { $0.jid == fp.jid && !$0.embedding.isEmpty }.sorted { $0.date > $1.date }
            try db.replaceEnrollment(jid: fp.jid, notes: Array(own.prefix(policy.maxNotes)))
        }
        try db.saveFingerprints(fingerprints)
        try db.setSetting("enrollmentModelVersion", engine.modelVersion)

        let pinned = Set(try db.contacts().filter(\.pinned).map(\.jid))
        try db.saveContacts(bySender.keys.map { jid in
            let identity = NameResolver.resolve(jid, tables: tables)
            return ContactRecord(jid: jid, displayName: identity.displayName, isSaved: identity.isSavedContact,
                                 pinned: pinned.contains(jid), blacklisted: false, avatarPath: identity.avatarPath)
        })
        try db.saveCalibration(Calibrator.calibrate(notes: try db.allEnrollmentNotes()))

        let protected = Enroller.protectedJIDs(fingerprints, pinned: Array(pinned), policy: policy)
        continuation.yield(.enrollmentFinished(fingerprints: fingerprints.count, protected: protected))
        return fingerprints
    }

    // MARK: Live verification (spec section 8)

    @discardableResult
    public func verify(_ note: VoiceNoteRecord, now: Date = Date()) async throws -> VerdictRecord {
        if chat == nil { _ = try openStores() }
        let fingerprints = try db.fingerprints()
        let thresholds = try db.thresholds()
        let identity = NameResolver.resolve(note.senderJID, tables: tables)
        var names = Dictionary(fingerprints.map { ($0.jid, NameResolver.resolve($0.jid, tables: tables).displayName) },
                               uniquingKeysWith: { a, _ in a })
        names[note.senderJID] = identity.displayName
        let hasFingerprint = fingerprints.contains { $0.jid == note.senderJID }
        let senderClass: SenderClass = identity.isSavedContact ? (hasFingerprint ? .knownEnrolled : .knownUnenrolled) : .unknown

        let url = config.locator.mediaURL(relativePath: note.relativeMediaPath)
        var verdict: Verdict
        var speech = 0.0
        let mediaAvailable = await waitForMedia(at: url)
        if !mediaAvailable {
            verdict = .unverifiable(.mediaMissing, explanation: "The audio hasn't been downloaded yet.")
        } else {
            do {
                let analysis = try await engine.analyze(url: url)
                speech = analysis.speechSeconds
                let comparisons = analysis.embedding.isEmpty ? [] : fingerprints.map {
                    Comparison(jid: $0.jid, score: Vector.cosine(analysis.embedding, $0.centroid))
                }
                let claimed = senderClass == .unknown
                    ? ClaimMatcher.claimedJID(pushName: identity.pushName, enrolled: fingerprints.map(\.jid), names: names)
                    : nil
                verdict = Verifier.verdict(VerificationInput(senderJID: note.senderJID, senderClass: senderClass,
                                                             claimedJID: claimed, speechSeconds: speech,
                                                             comparisons: comparisons, names: names), thresholds: thresholds)
                if verdict.kind == .verified, let score = verdict.score {
                    try rollingUpdate(note: note, analysis: analysis, score: score, thresholds: thresholds, fingerprints: fingerprints)
                }
            } catch let error as AudioDecodeError {
                verdict = .unverifiable(.decodeFailed, explanation: "Couldn't decode this audio (\(error)).")
            } catch {
                verdict = .unverifiable(.modelFailed, explanation: "Voice analysis failed (\(error)).")
            }
        }
        let record = VerdictRecord(note: note, verdict: verdict, speechSeconds: speech, computedAt: now, modelVersion: engine.modelVersion)
        try db.saveVerdict(record)
        continuation.yield(.verdict(record))
        return record
    }

    private func rollingUpdate(note: VoiceNoteRecord, analysis: VoiceAnalysis, score: Float,
                               thresholds: Thresholds, fingerprints: [Fingerprint]) throws {
        let candidate = EnrolledNote(jid: note.senderJID, messagePK: note.messagePK, embedding: analysis.embedding,
                                     speechSeconds: analysis.speechSeconds, date: note.date)
        guard let merged = Enroller.rollingAppend(existing: try db.enrollmentNotes(jid: note.senderJID), candidate: candidate,
                                                  score: score, thresholds: thresholds, policy: config.policy) else { return }
        try db.replaceEnrollment(jid: note.senderJID, notes: merged)
        let refreshed = Enroller.fingerprints(from: merged, policy: config.policy, modelVersion: engine.modelVersion)
        try db.saveFingerprints(fingerprints.filter { $0.jid != note.senderJID } + refreshed)
    }

    /// The DB row can precede the downloaded file by a moment; retry briefly.
    private func waitForMedia(at url: URL) async -> Bool {
        for attempt in 0..<max(1, config.mediaRetries) {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            if attempt < config.mediaRetries - 1 {
                try? await Task.sleep(for: .seconds(config.mediaRetryDelay))
            }
        }
        return false
    }

    /// Verifies every candidate note newer than the cursor, then advances the cursor
    /// without passing notes whose media is still pending.
    @discardableResult
    public func processNew() async throws -> [VerdictRecord] {
        let store = try openStores()
        let cursor = try db.lastSeenMessagePK()
        var results: [VerdictRecord] = []
        for note in try VoiceNoteQuery.fetch(store, afterPK: cursor) where isCandidate(note) {
            if let existing = try db.verdict(messagePK: note.messagePK), existing.reason != UnverifiableReason.mediaMissing.rawValue {
                continue
            }
            results.append(try await verify(note))
        }
        let maxPK = try VoiceNoteQuery.maxMessagePK(store)
        let floor = try VoiceNoteQuery.pendingFloor(store, since: Date().addingTimeInterval(-config.pendingLookback))
        let next = min(maxPK, (floor ?? Int64.max) - 1)
        try db.setLastSeenMessagePK(max(cursor, next))
        return results
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**
Run: `make test` → `ClaimMatcherTests` (4) and `PendingFloorTests` (1) pass.
Run: `make test-integration` → `CoordinatorIntegrationTests` 2 tests pass. Note the wall time of `enrollAll` in the commit message.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(core): coordinator for enrolment, live verification and pending-media cursor

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 16: `antifish` CLI

**Files:**
- Modify: `AntiFishCore/Sources/antifish/main.swift`
- Create: `AntiFishCore/Sources/antifish/Commands.swift`

- [ ] **Step 1: Write the failing check**

The CLI has no unit tests of its own (it only formats core results); its check is a smoke run. Before implementing, confirm the current stub prints only the version:
Run: `swift run --package-path AntiFishCore antifish status`
Expected: prints `antifish 0.1.0` and nothing else (the failing state: `status` is not understood).

- [ ] **Step 2: Write the implementation**

`AntiFishCore/Sources/antifish/Commands.swift`:
```swift
import AntiFishCore
import Foundation

enum CLIError: Error { case usage, whatsAppUnavailable(String), modelsMissing(String) }

struct CLIOptions {
    var command = "status"
    var args: [String] = []
    var dbURL: URL? = AppDatabase.defaultURL()
    var modelsDir: URL = {
        if let p = ProcessInfo.processInfo.environment["ANTIFISH_MODELS_DIR"] { return URL(fileURLWithPath: p) }
        return URL(fileURLWithPath: "AntiFish/Resources/Models")
    }()

    static func parse(_ argv: [String]) throws -> CLIOptions {
        var options = CLIOptions()
        var rest = Array(argv.dropFirst())
        while let flag = rest.first, flag.hasPrefix("--") {
            rest.removeFirst()
            switch flag {
            case "--db": options.dbURL = URL(fileURLWithPath: rest.removeFirst())
            case "--memory-db": options.dbURL = nil
            case "--models": options.modelsDir = URL(fileURLWithPath: rest.removeFirst())
            default: throw CLIError.usage
            }
        }
        if let command = rest.first { options.command = command; rest.removeFirst() }
        options.args = rest
        return options
    }
}

struct CLI {
    let options: CLIOptions
    let locator = ContainerLocator()

    func run() async throws {
        switch options.command {
        case "status": try status()
        case "enroll": try await enroll()
        case "verify": try await verify()
        case "calibrate": try calibrate()
        case "feed": try feed()
        default: throw CLIError.usage
        }
    }

    private func requireWhatsApp() throws {
        guard locator.isInstalled else { throw CLIError.whatsAppUnavailable("WhatsApp Desktop is not linked on this Mac") }
        guard locator.hasFullDiskAccess else { throw CLIError.whatsAppUnavailable("Full Disk Access is required (System Settings → Privacy & Security → Full Disk Access)") }
    }

    private func makeCoordinator() throws -> (Coordinator, AppDatabase) {
        let models = ModelPaths(directory: options.modelsDir)
        guard FileManager.default.fileExists(atPath: models.speakerModel), FileManager.default.fileExists(atPath: models.vadModel) else {
            throw CLIError.modelsMissing(options.modelsDir.path)
        }
        let db = try AppDatabase(url: options.dbURL)
        let engine = try VoiceEngine(models: models, numThreads: 4)
        return (Coordinator(config: CoordinatorConfig(locator: locator, models: models), db: db, engine: engine), db)
    }

    func status() throws {
        print("WhatsApp container: \(locator.isInstalled ? "found" : "missing")")
        print("Full Disk Access:   \(locator.hasFullDiskAccess ? "granted" : "denied")")
        let models = ModelPaths(directory: options.modelsDir)
        print("Models:             \(FileManager.default.fileExists(atPath: models.speakerModel) ? "present" : "missing") at \(options.modelsDir.path)")
        guard locator.isInstalled, locator.hasFullDiskAccess else { return }
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let notes = try VoiceNoteQuery.fetch(store)
        let incoming = notes.filter { !$0.isFromMe }
        let onDisk = incoming.filter { FileManager.default.fileExists(atPath: locator.mediaURL(relativePath: $0.relativeMediaPath).path) }
        print("Voice notes:        \(notes.count) total, \(incoming.count) incoming, \(onDisk.count) on disk")
        let db = try AppDatabase(url: options.dbURL)
        let fps = try db.fingerprints()
        let t = try db.thresholds()
        print("Fingerprints:       \(fps.count)  thresholds reject=\(t.reject) match=\(t.match) \(t.calibrated ? "(calibrated)" : "(defaults)")")
    }

    func enroll() async throws {
        try requireWhatsApp()
        let (coordinator, db) = try makeCoordinator()
        let started = Date()
        let fps = try await coordinator.enrollAll()
        let contacts = Dictionary(uniqueKeysWithValues: try db.contacts().map { ($0.jid, $0) })
        print("Enrolled \(fps.count) contacts in \(Int(Date().timeIntervalSince(started))) s")
        for fp in fps {
            let name = contacts[fp.jid]?.displayName ?? fp.jid
            let saved = contacts[fp.jid]?.isSaved == true ? "saved" : "unsaved"
            print(String(format: "  %-28@ %3d notes %6.0f s  %@", name, fp.noteCount, fp.speechSeconds, saved))
        }
        if let c = try db.calibration() {
            print("Calibration: contacts=\(c.contactCount) genuineMedian=\(c.genuineMedian) impostorMedian=\(c.impostorMedian) reject=\(c.thresholds.reject) match=\(c.thresholds.match) calibrated=\(c.thresholds.calibrated)")
        }
    }

    func verify() async throws {
        try requireWhatsApp()
        let (coordinator, _) = try makeCoordinator()
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let notes = try VoiceNoteQuery.fetch(store).filter { !$0.isFromMe && !$0.senderJID.hasPrefix("status@") }
        let targets: [VoiceNoteRecord]
        if options.args.first == "--newest" || options.args.isEmpty {
            targets = notes.suffix(Int(options.args.dropFirst().first ?? "1") ?? 1)
        } else {
            let path = options.args[0]
            targets = notes.filter { locator.mediaURL(relativePath: $0.relativeMediaPath).path == path || $0.relativeMediaPath == path }
            if targets.isEmpty { print("no voice note row for \(path)"); return }
        }
        for note in targets {
            let record = try await coordinator.verify(note)
            print("[\(record.colour.uppercased())] \(record.kind)  sender=\(record.senderJID)  score=\(record.score.map { String(format: "%.2f", $0) } ?? "-")  speech=\(String(format: "%.1f", record.speechSeconds))s")
            print("   \(record.explanation)")
        }
    }

    func calibrate() throws {
        let db = try AppDatabase(url: options.dbURL)
        let result = Calibrator.calibrate(notes: try db.allEnrollmentNotes())
        try db.saveCalibration(result)
        print("contacts=\(result.contactCount) genuine=\(result.genuineCount) impostor=\(result.impostorCount)")
        print("genuineMedian=\(result.genuineMedian) impostorMedian=\(result.impostorMedian)")
        print("reject=\(result.thresholds.reject) match=\(result.thresholds.match) calibrated=\(result.thresholds.calibrated)")
    }

    func feed() throws {
        let db = try AppDatabase(url: options.dbURL)
        let limit = Int(options.args.first ?? "20") ?? 20
        for v in try db.verdicts(limit: limit) {
            print("\(v.date)  [\(v.colour)] \(v.kind)  \(v.senderJID)  \(v.explanation)")
        }
    }
}
```

`AntiFishCore/Sources/antifish/main.swift`:
```swift
import AntiFishCore
import Foundation

let usage = """
antifish \(AntiFishCore.version)
usage: antifish [--db <path> | --memory-db] [--models <dir>] <command>
  status                 container, permissions, counts, thresholds
  enroll                 build fingerprints from on-disk voice notes, then calibrate
  verify [--newest [n]]  verify the newest n incoming notes (default 1)
  verify <media path>    verify one note by its media path
  calibrate              recompute thresholds from stored enrolment notes
  feed [n]               print the last n verdicts
"""

do {
    let options = try CLIOptions.parse(CommandLine.arguments)
    try await CLI(options: options).run()
} catch CLIError.usage {
    print(usage)
    exit(1)
} catch CLIError.whatsAppUnavailable(let why) {
    FileHandle.standardError.write(Data("error: \(why)\n".utf8))
    exit(2)
} catch CLIError.modelsMissing(let dir) {
    FileHandle.standardError.write(Data("error: models missing in \(dir); run `make models`\n".utf8))
    exit(3)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
```

- [ ] **Step 3: Smoke-run every command**
Run: `make cli ARGS="status"` → prints container/FDA/model lines and the voice-note counts.
Run: `make cli ARGS="--memory-db enroll"` → lists enrolled contacts (expect ≥10 rows on this Mac) and a calibration line with `calibrated=true`.
Run: `make cli ARGS="enroll"` then `make cli ARGS="verify --newest 3"` → three verdict lines, none `unverifiable`.
Run: `make cli ARGS="feed 5"` → five verdicts, newest first.
Run: `swift run --package-path AntiFishCore antifish bogus; echo "exit=$?"` → usage text and `exit=1`.

- [ ] **Step 4: Commit**
```bash
git add -A AntiFishCore && git commit -m "feat(cli): antifish status/enroll/verify/calibrate/feed commands

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 17: Wrap-up, verification evidence, hand-off to Plan 2

**Files:**
- Create: `README.md`
- Modify: `testing.md` (add the CLI smoke commands from Task 16 under a "CLI smoke" heading)

- [ ] **Step 1: README**
```markdown
# AntiFish

Flags WhatsApp Desktop voice notes whose voice does not match the apparent sender.
Runs entirely on this Mac: reads WhatsApp's local database and voice-note files, fingerprints your contacts with an
offline speaker-embedding model, and scores every incoming note against them. No network, no cloud.

- Design: `docs/specs/2026-09-12-voice-note-impersonation-design.md`
- Plans: `docs/plans/`
- Build and test: `make models && make test`; real-data checks: `make test-integration`
- Try it: `make cli ARGS="enroll"` then `make cli ARGS="verify --newest 3"`
```

- [ ] **Step 2: Full verification run (record the output in the commit message)**
Run, in this order, and paste the summary lines into the commit body:
```bash
make test            # expect: all unit tests pass; model-dependent ones run because make exports ANTIFISH_MODELS_DIR
make test-integration
make cli ARGS="status"
```
Expected: `make test` reports 0 failures across SmokeTests, ContainerLocatorTests, VectorTests, ChatStoreTests, VoiceNoteQueryTests, NameResolverTests, OpusDecoderTests, SpeechTrimmerTests, EmbeddingExtractorTests, VoiceEngineTests, EnrollerTests, VerifierTests, CalibratorTests, AppDatabaseTests, ContainerWatcherTests, ClaimMatcherTests, PendingFloorTests. `make test-integration` reports 0 failures across the seven `*IntegrationTests` classes.

- [ ] **Step 3: Commit**
```bash
git add README.md testing.md && git commit -m "docs: README and CLI smoke instructions; Plan 1 verified green

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Plan self-review (done before execution starts)

- **Spec coverage.** Sections 3, 5 (core modules), 6, 7, 8, 8.3, 10 (rows: DB busy → Task 3; media row before file → Task 15 `waitForMedia` + `pendingFloor`; decode failure → Task 15; model missing → Tasks 7/8/16; <1.5 s speech → Task 11), 11 (unit + integration layers), 12 (package, Makefile, models) are covered by Tasks 0–17. Not in this plan, by design: spec sections 9 (UI), the onboarding/FDA deep link, notifications, login item, XCUITest, the re-link detection prompt, signing/notarization, and the pre-commit hook. Those are Plans 2 and 3 (below).
- **Placeholder scan.** No TBD/TODO; every step has code and an expected result.
- **Type consistency.** Names used across tasks were cross-checked: `Enroller.fingerprints(from:policy:modelVersion:)`, `Enroller.protectedJIDs(_:pinned:policy:)`, `Enroller.rollingAppend(existing:candidate:score:thresholds:policy:)`, `Calibrator.calibrate(notes:defaults:now:)`, `Verifier.verdict(_:thresholds:)`, `Verdict.unverifiable(_:explanation:)`, `VerdictRecord(note:verdict:speechSeconds:computedAt:modelVersion:)`, `VoiceEngine.analyze(url:)`/`analyze(samples:)`, `VoiceNoteQuery.fetch(_:afterPK:)`/`maxMessagePK(_:)`/`pendingFloor(_:since:)`, `NameTables.load(chat:contacts:)`, `NameResolver.resolve(_:tables:)`, `ClaimMatcher.claimedJID(pushName:enrolled:names:)`, `ContainerWatcher(root:debounce:pollInterval:handler:)`, and every `AppDatabase` method are defined once and called with the same labels everywhere.
- **Known risks to watch during execution.** (1) sherpa-onnx's SPM package is tools-version 5.9 and links a static xcframework plus onnxruntime; if `swift test` fails to link, switch the product to `sherpa-onnx-shared` in Package.swift. (2) `AVAudioFile` reading Ogg-Opus is verified on macOS 26 only. (3) FSEvents tests on a temp directory need the default 1 s latency plus debounce; the 8 s timeout allows for that. (4) The Coordinator integration test analyses up to ~600 notes; allow several minutes on first run.

## Follow-on plans (written after Plan 1 is green, against the real core API)

- **Plan 2 — `docs/plans/<date>-antifish-app.md`:** XcodeGen `project.yml` with the `AntiFish` app target depending on `AntiFishCore`; onboarding (WhatsApp found → Full Disk Access with deep link and 1.2 s re-probe → notifications + launch at login); Feed window, detail pane, Contacts window, Settings → Calibration; `MenuBarExtra`; `UNUserNotificationCenter` on red only; `ContainerWatcher` wired to `Coordinator.processNew()`; backfill progress; container re-link detection; XCUITest E2E; intentful-ui frame-diff loop for every transition.
- **Plan 3 — `docs/plans/<date>-antifish-release.md`:** Developer ID signing and notarization under W4464244GE via `make release`; hardened runtime entitlements; bundling the models into the app; the pre-commit privacy hook (blocks staged text containing nine or more digits before `@lid`/`@s.whatsapp.net`); launch-time Opus decode probe with the "macOS version" banner; version bump and DMG packaging.
