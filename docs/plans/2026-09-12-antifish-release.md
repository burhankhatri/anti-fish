# AntiFish Release Implementation Plan (Plan 3 of 3)

**Goal:** Ship AntiFish as a Developer ID-signed, notarized, stapled DMG with a stable code identity, a privacy pre-commit hook, and a launch-time audio-decode probe.
**Architecture:** Release builds come from `make release` (Release configuration, hardened runtime, secure timestamp), are notarized twice (the `.app`, then the DMG) through a notarytool keychain profile, and stapled. The privacy hook lives in `.githooks/` and is enabled with `core.hooksPath`. The decode probe is a core function surfaced as an app banner.
**Tech Stack:** xcodebuild, codesign, `xcrun notarytool` (keychain profile, no plaintext secrets), `xcrun stapler`, `hdiutil`, `spctl`, bash, git hooks.
**Depends on:** Plan 1 (core, `AntiFishCore/`) and Plan 2 (app target `AntiFish`, scheme `AntiFish`, entitlements at `AntiFish/App/AntiFish.entitlements` and `AntiFish/App/AntiFish-Debug.entitlements`, `project.yml` at the repo root).

Conventions: every task is TDD or has an executable check; commit after each green task with a conventional message ending in `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Never put an Apple ID password, app-specific password, or private key in the repo.

---

### Task 0: Notary credentials in the keychain (one-time, no repo changes)

- [ ] **Step 1: Store the profile**
Run (interactive; paste the app-specific password from appleid.apple.com → Sign-In and Security → App-Specific Passwords when prompted):
```bash
xcrun notarytool store-credentials "AntiFishNotary" --apple-id "burhanuddinkhatri@gmail.com" --team-id W4464244GE
```
Expected: `Credentials saved to Keychain.`

- [ ] **Step 2: Verify**
Run: `xcrun notarytool history --keychain-profile AntiFishNotary | head -5`
Expected: a (possibly empty) submission history, no authentication error.

---

### Task 1: Release entitlements and `make release`

**Files:**
- Create: `AntiFish/App/AntiFish.entitlements` (if Plan 2 did not already create it with this content, replace it)
- Modify: `Makefile`
- Create: `scripts/verify-release.sh`

- [ ] **Step 1: Write the failing check**
`scripts/verify-release.sh` — asserts what a shippable build must satisfy:
```bash
#!/bin/bash
# Verifies a built AntiFish.app (and optional DMG) is signed with Developer ID, hardened, timestamped,
# carries no debug entitlement, embeds the models, and passes Gatekeeper assessment.
set -euo pipefail
APP="${1:?usage: verify-release.sh <path/to/AntiFish.app> [path/to/AntiFish.dmg]}"
DMG="${2:-}"
fail() { echo "FAIL: $*"; exit 1; }

codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | grep -q 'valid on disk' || fail "codesign verify"
codesign -dvv "$APP" 2>&1 | grep -q 'Authority=Developer ID Application: Magnetism Studios (W4464244GE)' || fail "not Developer ID signed"
codesign -dvv "$APP" 2>&1 | grep -q 'Timestamp=' || fail "no secure timestamp"
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q 'get-task-allow' && fail "debug entitlement present"
codesign -dvv "$APP" 2>&1 | grep -q 'flags=0x10000(runtime)' || fail "hardened runtime off"
[ -f "$APP/Contents/Resources/Models/wespeaker_en_voxceleb_resnet34_LM.onnx" ] || fail "speaker model not bundled"
[ -f "$APP/Contents/Resources/Models/silero_vad.onnx" ] || fail "VAD model not bundled"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" | grep -qx 'com.magnetismstudios.antifish.mac' || fail "bundle id"
spctl -a -vv -t exec "$APP" 2>&1 | grep -q 'accepted' || fail "spctl rejected the app"
xcrun stapler validate "$APP" >/dev/null 2>&1 || fail "app not stapled"
if [ -n "$DMG" ]; then
  spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | grep -q 'accepted' || fail "spctl rejected the DMG"
  xcrun stapler validate "$DMG" >/dev/null 2>&1 || fail "DMG not stapled"
fi
echo "OK: $APP is Developer ID signed, hardened, timestamped, stapled; models bundled${DMG:+; DMG stapled}"
```
Run: `chmod +x scripts/verify-release.sh && scripts/verify-release.sh build/Build/Products/Release/AntiFish.app`
Expected: `FAIL: codesign verify` (no Release build exists yet).

- [ ] **Step 2: Entitlements**
`AntiFish/App/AntiFish.entitlements` — hardened runtime with library validation kept ON; no sandbox (WhatsApp's container is unreadable from a sandbox); no other capabilities:
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
`AntiFish/App/AntiFish-Debug.entitlements` has identical content (Xcode adds `get-task-allow` to Debug builds by itself).

- [ ] **Step 3: Makefile release targets**
Append to `Makefile` (the app targets `project build install run test-ui` come from Plan 2):
```make
APP_NAME     := AntiFish.app
RELEASE_APP  := build/Build/Products/Release/$(APP_NAME)
DMG_PATH     := $(HOME)/Desktop/AntiFish.dmg
SIGN_IDENTITY := Developer ID Application: Magnetism Studios (W4464244GE)
NOTARY_PROFILE := AntiFishNotary
SHORT_VERSION := $(shell awk '/CFBundleShortVersionString:/ {gsub(/"/,"",$$2); print $$2; exit}' project.yml)

.PHONY: release verify-release

# Release = Release config + hardened runtime + secure timestamp, no get-task-allow.
# Notarized twice (zip of .app, then the DMG) so both the drag-to-Applications path and the
# open-the-DMG path verify offline. Credentials come from the keychain profile (Task 0), never the repo.
release: project models
	find build -name "._*" -type f -delete 2>/dev/null || true
	xcodebuild -project AntiFish.xcodeproj -scheme AntiFish -configuration Release \
	  -destination 'platform=macOS' -derivedDataPath build \
	  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp build
	# Re-sign anything embedded (dylibs/frameworks from SPM binary targets ship ad-hoc signed).
	@if [ -d "$(RELEASE_APP)/Contents/Frameworks" ]; then \
	  find "$(RELEASE_APP)/Contents/Frameworks" -depth \( -name '*.dylib' -o -name '*.framework' \) -print0 \
	    | xargs -0 -n1 codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)"; \
	  codesign --force --options runtime --timestamp --entitlements AntiFish/App/AntiFish.entitlements \
	    --sign "$(SIGN_IDENTITY)" "$(RELEASE_APP)"; \
	fi
	rm -f build/AntiFish-notarize.zip
	ditto -c -k --keepParent "$(RELEASE_APP)" build/AntiFish-notarize.zip
	@echo "[1/2] notarizing .app (1-5 min)…"
	xcrun notarytool submit build/AntiFish-notarize.zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(RELEASE_APP)"
	rm -f build/AntiFish-notarize.zip
	rm -rf build/dmg-stage && mkdir -p build/dmg-stage
	cp -R "$(RELEASE_APP)" build/dmg-stage/
	ln -s /Applications build/dmg-stage/Applications
	rm -f "$(DMG_PATH)"
	hdiutil create -volname "AntiFish $(SHORT_VERSION)" -srcfolder build/dmg-stage -ov -format UDZO "$(DMG_PATH)"
	rm -rf build/dmg-stage
	@echo "[2/2] notarizing DMG (1-5 min)…"
	xcrun notarytool submit "$(DMG_PATH)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(DMG_PATH)"
	scripts/verify-release.sh "$(RELEASE_APP)" "$(DMG_PATH)"
	@echo "Shipped: $(DMG_PATH)"

verify-release:
	scripts/verify-release.sh "$(RELEASE_APP)" "$(DMG_PATH)"
```

- [ ] **Step 4: Run the release and the check**
Run: `make release`
Expected: two `status: Accepted` lines from notarytool, `The staple and validate action worked!` twice, and the final `OK: … models bundled; DMG stapled` from the script.

- [ ] **Step 5: Commit**
```bash
git add Makefile scripts/verify-release.sh AntiFish/App/AntiFish.entitlements AntiFish/App/AntiFish-Debug.entitlements
git commit -m "build: notarized, stapled Developer ID release pipeline with keychain notary profile

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Privacy pre-commit hook

**Files:**
- Create: `.githooks/pre-commit`
- Create: `scripts/test-hooks.sh`
- Modify: `Makefile` (add `hooks` target), `testing.md`

- [ ] **Step 1: Write the failing test**
`scripts/test-hooks.sh` — exercises the hook in a throwaway repo:
```bash
#!/bin/bash
# Self-test for .githooks/pre-commit: real-looking JIDs and data files must be refused; short fake JIDs pass.
set -euo pipefail
HOOK="$(cd "$(dirname "$0")/.." && pwd)/.githooks/pre-commit"
[ -x "$HOOK" ] || { echo "FAIL: $HOOK missing or not executable"; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
mkdir -p "$tmp/.githooks" && cp "$HOOK" "$tmp/.githooks/pre-commit"
git -C "$tmp" config core.hooksPath .githooks
git -C "$tmp" config user.email t@example.com && git -C "$tmp" config user.name t
expect_refused() {  # $1 = description; file already staged
  if git -C "$tmp" commit -q -m "$1" >/dev/null 2>&1; then echo "FAIL: commit accepted: $1"; exit 1; fi
  git -C "$tmp" reset -q; echo "refused as expected: $1"
}
printf 'sender = "123456789012@lid"\n' > "$tmp/leak.swift"; git -C "$tmp" add leak.swift; expect_refused "real-looking lid"
rm "$tmp/leak.swift"
printf 'x 15551234567@s.whatsapp.net\n' > "$tmp/leak.txt"; git -C "$tmp" add leak.txt; expect_refused "real-looking phone jid"
rm "$tmp/leak.txt"
head -c 64 /dev/urandom > "$tmp/note.opus"; git -C "$tmp" add note.opus; expect_refused "opus file"
rm "$tmp/note.opus"
printf 'fixture = "111@lid"\n' > "$tmp/ok.swift"; git -C "$tmp" add ok.swift
git -C "$tmp" commit -q -m "short fake jid" || { echo "FAIL: short fake JID was refused"; exit 1; }
echo "OK: hook refuses real JIDs and data files, accepts fixtures"
```
Run: `chmod +x scripts/test-hooks.sh && scripts/test-hooks.sh`
Expected: `FAIL: …/.githooks/pre-commit missing or not executable`.

- [ ] **Step 2: Write the hook**
`.githooks/pre-commit`:
```bash
#!/bin/bash
# Refuses commits that would leak WhatsApp data: real-looking JIDs (9+ digits before @lid /
# @s.whatsapp.net / @g.us) in text, or audio/database/model files. Fixtures use short fake JIDs.
set -uo pipefail
status=0
pattern='[0-9]{9,}@(lid|s\.whatsapp\.net|g\.us)'
while IFS= read -r -d '' file; do
  case "$file" in
    *.opus|*.m4a|*.sqlite|*.sqlite-wal|*.sqlite-shm|*.onnx)
      echo "pre-commit: refusing data/model file: $file"; status=1; continue ;;
  esac
  if git show ":$file" | grep -Eq "$pattern"; then
    echo "pre-commit: real-looking WhatsApp identifier in $file:"
    git show ":$file" | grep -En "$pattern" | sed -E 's/[0-9]{9,}/<digits>/g' | head -3
    status=1
  fi
done < <(git diff --cached --name-only --diff-filter=ACM -z)
[ "$status" -ne 0 ] && echo "pre-commit: blocked. Remove the data or replace identifiers with short fakes like 111@lid."
exit "$status"
```
Makefile addition:
```make
.PHONY: hooks
hooks:
	chmod +x .githooks/pre-commit scripts/test-hooks.sh
	git config core.hooksPath .githooks
	scripts/test-hooks.sh
```
`testing.md` addition under a "Hooks" heading: `make hooks` installs and self-tests the privacy pre-commit hook; run it once per clone.

- [ ] **Step 3: Run test to verify it passes**
Run: `make hooks`
Expected: three `refused as expected` lines, then `OK: hook refuses real JIDs and data files, accepts fixtures`.

- [ ] **Step 4: Commit**
```bash
git add .githooks/pre-commit scripts/test-hooks.sh Makefile testing.md
git commit -m "chore: privacy pre-commit hook blocking WhatsApp identifiers and data files

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Launch-time decode probe

**Files:**
- Create: `AntiFishCore/Sources/AntiFishCore/Audio/DecodeProbe.swift`
- Test: `AntiFishCore/Tests/AntiFishCoreTests/Unit/DecodeProbeTests.swift`
- Modify: `AntiFish/App/AppModel.swift` (Plan 2 defines `banner: String?` and calls `start()`; this task adds the probe call)

- [ ] **Step 1: Write the failing test**
```swift
import AVFoundation
import XCTest
@testable import AntiFishCore

final class DecodeProbeTests: XCTestCase {
    /// Fixture container: ChatStorage/ContactsV2 from FixtureDB placed under a temp root.
    private func fixtureRoot() throws -> (ContainerLocator, URL) {
        let pair = try FixtureDB.standardPair()
        let root = pair.chat.deletingLastPathComponent()
        return (ContainerLocator(root: root), root)
    }

    func testNoFilesMeansNoVoiceNotesYet() throws {
        let (locator, _) = try fixtureRoot()
        XCTAssertEqual(DecodeProbe.run(locator: locator), .noVoiceNotesYet)
    }

    func testGarbageFileFails() throws {
        let (locator, root) = try fixtureRoot()
        let path = root.appendingPathComponent("Message/Media/200@g.us/c/d/n2.opus")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("junk".utf8).write(to: path)
        guard case .failed = DecodeProbe.run(locator: locator) else { return XCTFail("expected .failed") }
    }

    func testDecodableFileIsOK() throws {
        let (locator, root) = try fixtureRoot()
        let path = root.appendingPathComponent("Message/Media/200@g.us/c/d/n2.opus")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let cafURL = root.appendingPathComponent("tone.caf")
        let file = try AVAudioFile(forWriting: cafURL, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        for i in 0..<16_000 { buffer.floatChannelData![0][i] = Float(sin(Double(i) / 10)) * 0.3 }
        try file.write(from: buffer)
        try FileManager.default.copyItem(at: cafURL, to: path)   // AVAudioFile sniffs content, not extension
        guard case .ok(let seconds) = DecodeProbe.run(locator: locator) else { return XCTFail("expected .ok") }
        XCTAssertEqual(seconds, 1, accuracy: 0.05)
    }

    func testMissingContainerIsNoVoiceNotesYet() throws {
        XCTAssertEqual(DecodeProbe.run(locator: ContainerLocator(root: try TestEnv.tempDir())), .noVoiceNotesYet)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `make test` → compile error `cannot find 'DecodeProbe' in scope`.

- [ ] **Step 3: Write minimal implementation**
```swift
import Foundation

public enum DecodeProbeResult: Sendable, Equatable {
    case ok(seconds: Double)
    case noVoiceNotesYet
    case failed(String)
}

/// Spec section 12: Ogg-Opus decoding is verified on macOS 26 only. At launch, decode the newest
/// incoming voice note once; a failure becomes a banner instead of a crash or a silent feed.
public enum DecodeProbe {
    public static func run(locator: ContainerLocator) -> DecodeProbeResult {
        guard let store = try? ChatStore.open(url: locator.chatStorageURL),
              let notes = try? VoiceNoteQuery.fetch(store) else { return .noVoiceNotesYet }
        guard let newest = notes.last(where: { note in
            !note.isFromMe && FileManager.default.fileExists(atPath: locator.mediaURL(relativePath: note.relativeMediaPath).path)
        }) else { return .noVoiceNotesYet }
        do {
            let decoded = try OpusDecoder.decode(url: locator.mediaURL(relativePath: newest.relativeMediaPath))
            return decoded.samples.isEmpty ? .failed("decoded 0 samples") : .ok(seconds: decoded.seconds)
        } catch {
            return .failed(String(describing: error))
        }
    }
}
```
In `AntiFish/App/AppModel.swift`, inside `start()` after the Full Disk Access gate and before the coordinator starts:
```swift
        if case .failed(let why) = DecodeProbe.run(locator: locator) {
            banner = "This Mac can't decode WhatsApp voice notes (\(why)). AntiFish needs macOS 15 or newer with Opus support."
        }
```

- [ ] **Step 4: Run tests to verify they pass**
Run: `make test` → `DecodeProbeTests` 4 tests pass. Run: `make build` → app compiles with the banner wiring.

- [ ] **Step 5: Commit**
```bash
git add -A AntiFishCore AntiFish/App/AppModel.swift
git commit -m "feat: launch-time Opus decode probe with a clear banner on unsupported macOS

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Version bump, release checklist, verification

**Files:**
- Modify: `Makefile` (add `bump`)
- Create: `docs/release-checklist.md`
- Modify: `testing.md` (add the release checks)

- [ ] **Step 1: Failing check**
Run: `make bump VERSION=0.1.1 && grep -n 'CFBundleShortVersionString: "0.1.1"' project.yml`
Expected: `make: *** No rule to make target 'bump'`.

- [ ] **Step 2: Implement**
Makefile addition (CFBundleVersion is a monotonically increasing build number; `bump` increments it and sets the short version):
```make
.PHONY: bump
bump:
	@test -n "$(VERSION)" || { echo "usage: make bump VERSION=x.y.z"; exit 1; }
	@build=$$(awk '/CFBundleVersion:/ {gsub(/"/,"",$$2); print $$2+1; exit}' project.yml); \
	sed -i '' -E "s/(CFBundleShortVersionString: )\"[^\"]*\"/\1\"$(VERSION)\"/; s/(CFBundleVersion: )\"[^\"]*\"/\1\"$$build\"/" project.yml; \
	echo "project.yml -> $(VERSION) ($$build)"
	git add project.yml && git commit -q -m "release: bump to $(VERSION)" && git tag "v$(VERSION)"
```
`docs/release-checklist.md`:
```markdown
# Release checklist

1. `make models` — both model files present and checksummed.
2. `make test` — unit suite green.
3. `make test-integration` — real-data suite green on this Mac.
4. `make test-ui` — XCUITest E2E green.
5. `make loop-mac` — frame diff reports SMOOTH for onboarding → feed, row → detail, and the menu bar popover.
6. `make bump VERSION=x.y.z` — commits and tags.
7. `make release` — builds Release, notarizes and staples the .app and the DMG, runs `scripts/verify-release.sh`.
8. Second-Mac smoke: copy the DMG to another Mac, drag to Applications, first launch shows onboarding, granting Full Disk Access unlocks the feed within 2 s, no Gatekeeper warning at any step.
9. `git push --follow-tags`.
```
`testing.md` addition under "Release": `make verify-release` re-runs the signing/notarization assertions on the last Release build.

- [ ] **Step 3: Verify**
Run: `make bump VERSION=0.1.1` → `project.yml -> 0.1.1 (2)` and a new tag `v0.1.1`. Then `git tag -d v0.1.1 && git reset --soft HEAD~1 && git checkout project.yml` to undo the trial bump (the real bump happens at release time).

- [ ] **Step 4: Commit**
```bash
git add Makefile docs/release-checklist.md testing.md
git commit -m "build: version bump target and release checklist

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Plan self-review

- **Spec coverage.** Section 12 (Developer ID, hardened runtime, not sandboxed, notarized `make release`, models bundled, decode probe with banner), section 11 guarantees (pre-commit hook with the amended pattern), section 10 row "model file missing" (verify-release asserts the models are in the bundle). Sparkle, telemetry and paywall are deliberately absent (section 2).
- **Placeholder scan.** None. Every step has code and an expected output.
- **Consistency with Plans 1 and 2.** Uses Plan 1's `ContainerLocator`, `ChatStore.open`, `VoiceNoteQuery.fetch`, `OpusDecoder.decode` with the same labels; uses Plan 2's scheme `AntiFish`, `build/Build/Products/Release/AntiFish.app`, `AntiFish/App/AppModel.swift` with `banner: String?` and `start()`, and the `models` Make target from Plan 1.
- **Secrets.** The only credential is the notary app-specific password, stored in the login keychain by `notarytool store-credentials` (Task 0). Nothing in the repo.
- **Risks.** (1) If the sherpa-onnx or onnxruntime binary target ships as a dylib rather than a static archive, the re-sign loop in `make release` handles it; verify-release will still catch a bad signature. (2) Notarization rejects binaries without a secure timestamp; `OTHER_CODE_SIGN_FLAGS=--timestamp` is set explicitly. (3) `spctl -t open` for DMGs needs the primary-signature context; the script passes it.
