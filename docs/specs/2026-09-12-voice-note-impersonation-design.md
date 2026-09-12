# AntiFish — Voice-Note Impersonation Detection for WhatsApp Desktop (macOS)

**Date:** 2026-09-12
**Status:** Approved 2026-09-12 (all sections)
**Working name:** AntiFish (bundle ID `com.magnetismstudios.antifish.mac`)

## 1. Goal

A resident macOS app that watches WhatsApp Desktop's local data, builds a voice
fingerprint for the people who send the user voice notes, and, for every
incoming voice note, tells the user whether the voice matches who the sender
appears to be. Verdicts are shown in a clean feed; only "possible impersonation"
interrupts the user.

## 2. Non-goals (v1)

- No text-message analysis and no WhatsApp chat-mirror UI (decision: voice-note feed only).
- No AI-clone / synthetic-speech detection. A clone of Abdul's voice that matches
  Abdul's fingerprint is reported as verified. Anti-spoofing is v2.
- No iMessage, Telegram, Signal, WhatsApp Web.
- No network at runtime. Models are bundled. No Sparkle, telemetry, paywall.
- No Mac App Store: the sandbox forbids reading WhatsApp's group container.
- The user's own voice is not fingerprinted.

## 3. Facts the design rests on

Verified on this machine on 2026-09-12 (WhatsApp Desktop 26.33.73, macOS 26.4,
Xcode 26.4.1, Swift 6.3.1, Apple M4).

| Fact | Detail |
| --- | --- |
| Container | `~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/` |
| Message DB | `ChatStorage.sqlite`, WAL mode. A read-only open while WhatsApp runs succeeds, sees rows still in the WAL, and an incremental query joined to media costs ~26 ms. Copying (Overlap's method) is unnecessary. |
| Voice-note rows | `ZWAMESSAGE.ZMESSAGETYPE = 3` (type 2 is video; Overlap has these swapped). `ZWAMESSAGE.ZMEDIAITEM → ZWAMEDIAITEM.Z_PK`. `ZMEDIALOCALPATH` is relative to `<container>/Message`, e.g. `Media/<chatJID>/8/c/<uuid>.opus` (one `.m4a` seen). `ZMOVIEDURATION` = seconds. `ZISFROMME`, `ZFROMJID` (chat JID), `ZMESSAGEDATE` = seconds since 2001-01-01. |
| Group sender | `ZWAMESSAGE.ZGROUPMEMBER → ZWAGROUPMEMBER.ZMEMBERJID` (all `@lid`). Group voice notes are therefore attributable to individuals. |
| Media availability | All 576 incoming voice notes resolve under `<container>/Message/<ZMEDIALOCALPATH>`. Media exists only from the day Desktop was linked (2026-08-26). Since then 100% of voice notes are on disk: auto-download is on. Historical notes synced from the phone have no file and are ignored. |
| Audio format | Ogg-Opus, 48 kHz mono, ~20 kbps. `AVAudioFile` decodes it natively (full decode verified; SDK exposes `kAudioFormatOpus`). No ffmpeg. |
| Names | `ContactsV2.sqlite` → `ZWAADDRESSBOOKCONTACT` (`ZLID` = `<digits>@lid`, `ZPHONENUMBER` = `+<digits>`, `ZFULLNAME`) is the user's saved address book. Coverage of enrollable senders: address book 17/30, `ZWACHATSESSION.ZPARTNERNAME` 19/30, `ZWAPROFILEPUSHNAME` 28/30 (push name is chosen by the sender = attacker-controlled). `LID.sqlite` pair table is empty on this build. |
| Voice supply | 78 senders with on-disk incoming voice; 30 with ≥3 notes and ≥30 s; 20 with ≥60 s. Top sender: 121 notes / 975 s. |
| Runtime | sherpa-onnx v1.13.8 SPM package (prebuilt macOS static xcframework + onnxruntime 1.28.2). Swift API: `SherpaOnnxSpeakerEmbeddingExtractorWrapper` — `createStream()` → `acceptWaveform(samples:sampleRate:)` → `inputFinished()` → `compute(stream:)` → `[Float]`. VAD: `SherpaOnnxVoiceActivityDetectorWrapper` with Silero. |
| Models | `wespeaker_en_voxceleb_resnet34_LM.onnx` (26.5 MB, 256-d embedding), `silero_vad.onnx` (0.6 MB). Both downloadable from the sherpa-onnx GitHub releases. |
| Signing | `Developer ID Application: Magnetism Studios (W4464244GE)` is in the keychain. XcodeGen 2.45.4 installed. |

## 4. Approaches considered

**A — One resident app (chosen).** A SwiftUI app with a main window and a
`MenuBarExtra` that watches, analyses and displays in-process. One code identity
needs Full Disk Access, one process, no IPC.

**B — LaunchAgent daemon + XPC + UI app.** Survives the UI being quit, but two
binaries need FDA, XPC plumbing, and double packaging. Not needed: a menu-bar
app is already resident and launches at login.

**C — CLI core, thin app that shells out.** Testable, but no live watching and
two processes. We keep a CLI as a thin extra target over the shared core
instead, which gives the same testability without the split.

## 5. Architecture

### Targets

| Target | Kind | Contents |
| --- | --- | --- |
| `AntiFishCore` | local Swift package | WhatsApp reading, audio, voice engine, store, verdict logic. No UI. All unit and integration tests live here. |
| `AntiFish` | macOS app | SwiftUI features, menu bar, notifications, login item, onboarding. Depends on AntiFishCore. |
| `antifish` | CLI executable | `enroll`, `verify <path>`, `calibrate`, `status` over AntiFishCore. For scripts, tests and headless debugging. |
| `AntiFishCoreTests` | XCTest | Unit + integration. |
| `AntiFishUITests` | XCUITest | End-to-end. |

### AntiFishCore modules (one responsibility per file)

- `WhatsApp/ContainerLocator` — resolves the group container; `isInstalled`;
  `hasFullDiskAccess` (attempts a 1-byte read of `ChatStorage.sqlite`).
- `Store/SQLite` — a thin wrapper over the system `SQLite3` C library:
  open (read-only or read-write), prepared statements, typed column reads,
  and a `user_version` migration runner. No third-party database dependency.
- `WhatsApp/ChatStore` — `SQLite.Database` opened read-only with a 2 s
  busy timeout on the live `ChatStorage.sqlite`. `ContactsStore` likewise on
  `ContactsV2.sqlite`. Fallback: if an open fails with `SQLITE_BUSY` three times
  in a row, copy DB+WAL+SHM to a temp dir and open the copy for that pass only.
- `WhatsApp/VoiceNoteQuery` — returns `VoiceNoteRecord { messagePK, chatJID,
  senderJID, isFromMe, date, durationSeconds, relativeMediaPath, chatIsGroup }`
  for type-3 rows with a non-null path; `all()` and `since(messagePK:)`.
- `WhatsApp/NameResolver` — `resolve(jid) -> ResolvedIdentity { displayName,
  isSavedContact, pushName?, avatarPath? }`. Precedence: address-book full name
  → chat partner name (if it is not phone-shaped) → push name → `WA ····1234`
  (last four digits of the JID's numeric part). `isSavedContact` is true only
  for address-book hits.
- `WhatsApp/ContainerWatcher` — FSEvents stream on the container root (1 s
  latency) filtered to paths under `Message/Media` ending in `.opus`/`.m4a` or
  equal to `ChatStorage.sqlite-wal`; debounced 1.5 s; emits `changed`. A 60 s
  timer poll is the safety net.
- `Audio/OpusDecoder` — `AVAudioFile` + `AVAudioConverter` → 16 kHz mono
  `[Float]`. Errors: `unreadable`, `unsupportedFormat`.
- `Audio/SpeechTrimmer` — Silero VAD; concatenates speech segments; returns
  `TrimmedSpeech { samples, speechSeconds }`.
- `Voice/EmbeddingExtractor` (protocol) + `SherpaEmbeddingExtractor` —
  `embed([Float]) -> [Float]` (256-d, L2-normalised).
- `Voice/Fingerprint` — `{ jid, centroid, noteCount, speechSeconds, updatedAt,
  modelVersion }`; `centroid` = L2-normalised mean of enrolment embeddings.
- `Voice/Enroller` — enrolment policy (section 7).
- `Voice/Verifier` — sender classification + scoring → `Verdict` (section 8).
- `Voice/Calibrator` — thresholds from score distributions (section 8.3).
- `Store/AppDatabase` — `SQLite.Database` at
  `~/Library/Application Support/AntiFish/antifish.sqlite`. Tables: `contact`
  (jid, displayName, isSaved, pinned, blacklisted, avatarPath), `enrollment_note`
  (jid, messagePK, embedding BLOB, speechSeconds, date), `fingerprint` (jid,
  centroid BLOB, noteCount, speechSeconds, updatedAt, modelVersion), `verdict`
  (messagePK PK, senderJID, kind, score, comparedJID, bestJID, bestScore,
  speechSeconds, computedAt, modelVersion), `setting` (key, value).
- `Pipeline/Coordinator` — actor that orchestrates: change → new notes → decode
  → trim → embed → verify → store → publish; enrolment refresh; backfill.

### Concurrency

Swift 6 strict concurrency. `VoiceEngine` is an actor owning the extractor and
VAD (sherpa objects are not Sendable). `Coordinator` is an actor. The UI observes
an `@Observable @MainActor FeedModel` fed by the coordinator.

## 6. Data flow

**Enrolment (first run, then refresh after each live pass):** query all incoming
on-disk voice notes → group by sender JID (group messages attributed via
`ZWAGROUPMEMBER`; `status@broadcast` and the user's own JIDs excluded) → for each
sender with ≥3 notes: decode, trim and embed the 30 most recent notes → if total
speech ≥ 30 s, store enrolment notes and the fingerprint. Rank by most recent
incoming note; top 10 are Protected. Then the Calibrator runs (needs ≥5
fingerprints) and stores thresholds.

**Live:** watcher fires → `VoiceNoteQuery.since(lastSeenPK)` → for each new
incoming note whose file exists (retry 3× over 10 s when the DB row precedes the
file) → decode, trim, embed → `Verifier` → store verdict → `FeedModel` update →
notification if red. If the sender is a saved contact with a fingerprint and the
verdict is Verified, `Enroller.append` performs the rolling update (section 7).

**Backfill:** on first run every historical incoming on-disk note (576 today)
gets a verdict in the background, newest first, with progress in the feed
header. On an M4 one note costs well under a second end to end.

## 7. Enrolment policy

- Candidate: sender JID of incoming voice notes (`ZISFROMME = 0`), excluding
  `status@broadcast` and the user's own JIDs.
- Thresholds: ≥3 notes AND ≥30 s of VAD speech. At most the 30 newest notes per
  sender feed the centroid.
- Ranking: most recent incoming voice note, descending. Top 10 = Protected
  (pinned in the UI, notification-eligible). The rest = Enrolled. The user can
  pin/unpin (pin overrides ranking) and remove (removed JIDs are blacklisted
  from auto-enrolment until re-added).
- Rolling update: a new note joins a contact's enrolment only if (a) it came
  from that contact's own JID, (b) its verdict is Verified (score ≥ T_match),
  and (c) it has ≥2 s of speech. Notes beyond 30 drop off, oldest first, and
  the centroid is recomputed. This gate stops an impostor from poisoning a
  fingerprint.
- Re-enrolment when `modelVersion` changes; embeddings are not comparable
  across models.

## 8. Verdict logic

### 8.1 Sender classes and claims

| Class | Definition |
| --- | --- |
| `knownEnrolled` | sender JID is a saved address-book contact with a fingerprint |
| `knownUnenrolled` | saved contact without a fingerprint (too little voice) |
| `unknown` | not in the address book, including group members never saved |

`claimedJID` (computed only for `unknown` senders) = the enrolled contact whose
normalised full name equals the sender's normalised push name, or whose first
name (≥3 letters) equals the push name's first token. Normalisation: lowercase,
diacritics stripped, non-letters removed.

### 8.2 Scoring and tiers

`score(note, contact) = cosine(embedding, contact.centroid)`. Global thresholds
`T_reject < T_match`; defaults 0.25 / 0.45 until calibrated.

Speech gates: speech < 1.5 s → `unclear(tooShort)`. Red verdicts require ≥3 s of
speech, otherwise they downgrade to `unclear(shortClip)`. Verified requires ≥2 s.

| Verdict | Colour | When |
| --- | --- | --- |
| `verified(contact, score)` | green | `knownEnrolled`, score ≥ T_match |
| `takeoverSuspected(contact, score)` | red | `knownEnrolled`, score ≤ T_reject — Abdul's number, not Abdul's voice |
| `impersonationSuspected(claimed, score)` | red | `unknown` with a claim, score vs claimed ≤ T_reject |
| `matchesUnsavedNumber(contact, score)` | amber | `unknown`, best score ≥ T_match — "voice matches Abdul, number not saved; confirm on his saved number" |
| `unknownVoice(best?, bestScore)` | grey | `unknown`, no claim, best < T_match |
| `unverifiable(reason)` | grey | `knownUnenrolled`, media missing, decode or model failure |
| `unclear(reason, contact?, score)` | amber | score strictly between T_reject and T_match, or a short-clip downgrade |

Every verdict carries a one-line explanation and the top-3 comparison scores for
the detail view.

**Evaluation order.** `knownEnrolled`: compare only against the sender's own
fingerprint; the best other-contact score is reported in the explanation but
never changes the tier. `unknown`: (1) claim present and score vs claimed
≤ T_reject → `impersonationSuspected`; (2) best score over all fingerprints
≥ T_match → `matchesUnsavedNumber(best)` (the explanation names the claim when
it differs from the best match); (3) claim present and score vs claimed in the
unclear band → `unclear`; (4) otherwise `unknownVoice(best)`. Speech gates apply
after the tier is chosen.

### 8.3 Calibration

Runs after enrolment and weekly. Inputs: enrolment embeddings per contact
(k ≥ 3).

- genuine = for each contact `c` and each note `i`: `cosine(e_i, centroid(c
  without i))`.
- impostor = for each contact `c`, each note `e` in `c`, each other contact `d`:
  `cosine(e, centroid(d))`.
- `imp99` = 99th percentile of impostor; `gen2` = 2nd percentile of genuine.
- `T_match = max(imp99, gen2)`; `T_reject = min(imp99, gen2)`.
- Fewer than 5 fingerprints → keep defaults and show "uncalibrated".

Thresholds, sample counts and both medians are stored in `setting` and shown in
Settings → Calibration. Meaning: green means a stranger scores this high at most
1% of the time; red means a real note scores this low at most 2% of the time.

## 9. UI

- **Feed window** (default 900×620): header with status ("Watching · 10
  protected", backfill progress), list grouped by day. Row = avatar or
  initials, sender name, "in <group>" when applicable, time, duration,
  play/pause (`AVAudioPlayer`), verdict pill, one-line explanation. Selecting a
  row opens a detail pane: score bar against both thresholds, top-3
  comparisons, enrolment quality of the compared contact, and two actions —
  "This is really them" (appends the note to enrolment) and "Report impostor"
  (blacklists the sender JID, pins the verdict red). Both are local only.
- **Contacts window:** Protected (10, pin/unpin), Enrolled, Needs more voice.
  Each shows notes, seconds, last note date; remove and pin controls.
- **Onboarding:** WhatsApp found → Full Disk Access (deep link to
  `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`,
  re-probe every 1.2 s) → Notifications + Launch at login (`SMAppService`) →
  "Building fingerprints" progress.
- **Menu bar** (`MenuBarExtra`): status dot (green watching / amber paused / red
  when the latest verdict is red), last 3 verdicts, Open, Pause watching, Quit.
- **Notification** (red only, via `UNUserNotificationCenter`): "Possible
  impersonation — 'Abdul' (unsaved number): voice does not match Abdul", with
  an Open action.
- Native macOS 26 design language, no custom chrome. Built and verified with
  the intentful-ui loop: no transition ships until the frame diff reports SMOOTH.

## 10. Error handling

| Condition | Behaviour |
| --- | --- |
| WhatsApp not installed / container missing | Onboarding step 1 blocks with instructions; watcher not started |
| No Full Disk Access | Onboarding step 2; re-probe every 1.2 s; deep link |
| DB open `SQLITE_BUSY` | retry 3× with 2 s busy timeout → copy fallback for that pass → log |
| Schema drift (missing table/column) | `VoiceNoteQuery` throws → feed banner "WhatsApp changed its database format"; last verdicts stay; no crash. A schema probe at launch logs which optional tables exist |
| Media row before the file exists | retry 3× over 10 s → `unverifiable(mediaMissing)`; re-checked on the next watcher tick |
| Decode failure (incl. `.m4a`) | `AVAudioFile` is tried for any extension; on failure `unverifiable(decodeFailed)` |
| Model file missing or corrupt | engine refuses to start; banner "Reinstall AntiFish"; CLI exit code 3 |
| < 1.5 s speech | `unclear(tooShort)` |
| < 5 fingerprints | default thresholds; Settings shows "uncalibrated" |
| WhatsApp re-linked (container recreated) | detected by a changed `ChatStorage.sqlite` creation date → prompt to rebuild fingerprints |

Logging: `os.Logger`, subsystem `com.magnetismstudios.antifish`. JIDs, phone
digits and names are always `.private`. Nothing is ever written to `/tmp`.

## 11. Testing

Decision: tests use real voice notes from this machine's WhatsApp container and
nothing from it is ever committed.

- **Unit** (`AntiFishCore`, no audio, no WhatsApp DB): `NameResolver`
  precedence; claim matching; `Verifier` tier table (every class × score band ×
  speech gate); `Calibrator` maths on synthetic vectors; `Enroller` ranking,
  caps and rolling gate; `VoiceNoteQuery` SQL against an in-memory GRDB
  database created from the same DDL subset (schema text only, captured once
  from `sqlite_master`, no personal data).
- **Integration** (needs the live container; `XCTSkip` when absent or when
  `ANTIFISH_REAL_WA` is unset): `ContainerLocator` finds the container;
  `ChatStore` opens the live DB read-only while WhatsApp runs; `VoiceNoteQuery`
  returns ≥1 incoming note whose file exists; `OpusDecoder` decodes a real note
  to 16 kHz with RMS > 0.01; `SpeechTrimmer` returns speech within 0.3×–1.2× of
  `ZMOVIEDURATION`; `SherpaEmbeddingExtractor` returns 256 floats with unit
  norm; `Enroller` enrols ≥10 contacts; separation: median genuine score
  exceeds median impostor score by ≥0.15; `Calibrator` yields
  `T_reject < T_match`; verifying the newest note yields a non-`unverifiable`
  verdict.
- **E2E** (XCUITest, live data, same env gate): launch → onboarding passes →
  feed shows ≥1 row → Contacts shows ≥1 protected → selecting a row shows a
  verdict pill → menu bar extra exists. Transitions verified with the
  intentful-ui frame-diff loop.
- **Guarantees:** tests write only under `NSTemporaryDirectory()`.
  `.gitignore` covers `*.opus`, `*.m4a`, `*.sqlite*`, `Models/*.onnx`,
  `DerivedData/`, `.worktrees/`. A pre-commit hook blocks the commit if any
  staged text file contains a real-looking JID (nine or more digits directly
  before `@lid` or `@s.whatsapp.net`); test fixtures use short fake JIDs such
  as `111@lid`, and source may legitimately mention the container path.
- `testing.md` documents `make test` (unit), `ANTIFISH_REAL_WA=1 make
  test-integration`, and `make test-ui`.

## 12. Tech stack and repo layout

- Swift 6.3, SwiftUI, deployment target macOS 15.0. Ogg-Opus decoding is
  verified on 26.4 only and the SDK carries no availability annotation for it,
  so the app runs a launch-time decode probe on the newest on-disk voice note;
  on failure it shows a banner naming the required macOS version instead of
  crashing. No decoder dependency is added.
- XcodeGen 2.45.4 (`project.yml` is the source of truth), Makefile targets:
  `project build run test test-integration test-ui models release`.
- SPM: `sherpa-onnx` v1.13.8 (product `sherpa-onnx`, static) is the only
  third-party dependency. Storage uses the system `SQLite3` library through a
  small in-repo wrapper. GRDB was evaluated and dropped on 2026-09-12: its git
  history is ~220 MB and the mirror clone stalled, which is a poor trade for a
  privacy tool whose storage needs are a handful of tables. Overlap reads the
  same WhatsApp databases with the raw C API, so the approach is proven.
- Models fetched by `make models` with SHA-256 verification into
  `AntiFish/Resources/Models/` (gitignored); copied into the bundle at build.
- Bundle ID `com.magnetismstudios.antifish.mac`; not sandboxed; hardened
  runtime; Developer ID signing (W4464244GE); `make release` notarizes.

```
anti-fish/
  project.yml  Makefile  testing.md  CLAUDE.md  .gitignore
  AntiFishCore/
    Package.swift
    Sources/AntiFishCore/{WhatsApp,Audio,Voice,Store,Pipeline}/
    Tests/AntiFishCoreTests/{Unit,Integration}/
  AntiFish/
    App/  Features/{Onboarding,Feed,Contacts,MenuBar,Settings}/  Resources/Models/
  AntiFishCLI/
  AntiFishUITests/
  docs/specs/  docs/plans/
```

## 13. Risks

- Ogg-Opus decode on macOS 15 is unverified (mitigation in section 12).
- Calibration needs ≥5 enrolled contacts; a user with little voice traffic stays
  on default thresholds, visibly marked uncalibrated.
- Same-household voices (siblings) can score high against each other. The amber
  band and the "matches unsaved number" wording deliberately never show green
  for an unsaved number.
- WhatsApp schema changes: all reads are confined to `VoiceNoteQuery` and
  `NameResolver`, each with a schema probe and a clear failure banner.
- A voice clone that fools the ResNet34 model is reported Verified. Explicit
  non-goal; v2 adds anti-spoofing.
- Tests depend on this machine's WhatsApp data (decision); they skip elsewhere.
