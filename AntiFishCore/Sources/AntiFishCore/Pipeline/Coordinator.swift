import Foundation
import os

public struct CoordinatorConfig: Sendable {
    public var locator: ContainerLocator
    public var models: ModelPaths
    public var policy = EnrollmentPolicy()
    /// A message row can land a moment before its audio finishes downloading.
    public var mediaRetries = 3
    public var mediaRetryDelay: TimeInterval = 3.3
    /// How far back to look for notes still waiting on their audio.
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

/// Runs the pipeline: enrol voices, verify new notes, keep the store current.
/// An actor so the models and the cursor are only ever touched from one place.
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

    @discardableResult
    private func openStores() throws -> ChatStore {
        let store = try chat ?? ChatStore.open(url: config.locator.chatStorageURL)
        chat = store
        tables = try NameTables.load(chat: store, contacts: try? ChatStore.open(url: config.locator.contactsURL))
        return store
    }

    /// Notes worth judging: incoming, attributable to a person, and not a status broadcast.
    private func isCandidate(_ note: VoiceNoteRecord) -> Bool {
        !note.isFromMe && !note.senderJID.isEmpty && !note.senderJID.hasPrefix("status@")
    }

    private func mediaExists(_ note: VoiceNoteRecord) -> Bool {
        FileManager.default.fileExists(atPath: config.locator.mediaURL(relativePath: note.relativeMediaPath).path)
    }

    // MARK: Enrolment

    /// Builds a fingerprint for every sender with enough recent voice on this Mac, recomputes the
    /// centre of the embedding space, and learns thresholds from the result.
    @discardableResult
    public func enrollAll() async throws -> [Fingerprint] {
        let store = try openStores()
        let policy = config.policy
        let blacklist = Set(try db.contacts().filter(\.blacklisted).map(\.jid))
        let candidates = try VoiceNoteQuery.fetch(store).filter { isCandidate($0) && mediaExists($0) }
        let bySender = Dictionary(grouping: candidates, by: \.senderJID)
            .filter { $0.value.count >= policy.minNotes && !blacklist.contains($0.key) }
        let todo = bySender.values.flatMap { $0.sorted { $0.date > $1.date }.prefix(policy.maxNotes) }

        // Re-use embeddings already computed with this model; they are expensive and never change.
        let sameModel = (try db.setting("enrollmentModelVersion")) == engine.modelVersion
        let cached: [Int64: EnrolledNote] = sameModel
            ? Dictionary(try db.allEnrollmentNotes().map { ($0.messagePK, $0) }, uniquingKeysWith: { a, _ in a })
            : [:]

        var notes: [EnrolledNote] = []
        for (index, note) in todo.enumerated() {
            if let hit = cached[note.messagePK] {
                notes.append(hit)
            } else {
                do {
                    let analysis = try await engine.analyze(url: config.locator.mediaURL(relativePath: note.relativeMediaPath))
                    notes.append(EnrolledNote(jid: note.senderJID, messagePK: note.messagePK,
                                              embedding: analysis.embedding,
                                              speechSeconds: analysis.speechSeconds, date: note.date))
                } catch {
                    logger.notice("skipping note \(note.messagePK, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
            continuation.yield(.enrollmentProgress(done: index + 1, total: todo.count))
        }

        let usable = notes.filter { !$0.embedding.isEmpty }
        let center = EmbeddingCenter(embeddings: usable.map(\.embedding))
        try db.saveEmbeddingCenter(center)

        let fingerprints = Enroller.fingerprints(from: notes, policy: policy, center: center,
                                                 modelVersion: engine.modelVersion)
        for fp in fingerprints {
            let own = usable.filter { $0.jid == fp.jid }.sorted { $0.date > $1.date }
            try db.replaceEnrollment(jid: fp.jid, notes: Array(own.prefix(policy.maxNotes)))
        }
        try db.saveFingerprints(fingerprints)
        try db.clearUnverifiableVerdicts(for: fingerprints.map(\.jid), reason: .notEnrolled)
        try db.setSetting("enrollmentModelVersion", engine.modelVersion)

        let pinned = Set(try db.contacts().filter(\.pinned).map(\.jid))
        try db.saveContacts(bySender.keys.map { jid in
            let identity = NameResolver.resolve(jid, tables: tables)
            return ContactRecord(jid: jid, displayName: identity.displayName,
                                 isSaved: identity.isSavedContact, pinned: pinned.contains(jid),
                                 blacklisted: false, avatarPath: identity.avatarPath)
        })
        try db.saveCalibration(Calibrator.calibrate(notes: try db.allEnrollmentNotes(), center: center))

        let protected = Enroller.protectedJIDs(fingerprints, pinned: Array(pinned), policy: policy)
        continuation.yield(.enrollmentFinished(fingerprints: fingerprints.count, protected: protected))
        return fingerprints
    }

    /// Builds baselines for people who have crossed the threshold since the last full enrolment.
    ///
    /// The first run enrols everyone with enough voice. Anyone who starts sending voice notes
    /// afterwards had no baseline at all, so they could not be verified and never appeared among
    /// the people a caller might claim to be.
    ///
    /// The centre of the embedding space is deliberately left as it was: moving it would make
    /// every existing centroid incomparable with the scores already stored against it.
    @discardableResult
    public func enrollNewcomers() async throws -> [String] {
        let store = try openStores()
        let policy = config.policy
        let existing = Set(try db.fingerprints().map(\.jid))
        let blacklist = Set(try db.contacts().filter(\.blacklisted).map(\.jid))
        let center = try db.embeddingCenter()

        let bySender = Dictionary(grouping: try VoiceNoteQuery.fetch(store)
                                    .filter { isCandidate($0) && mediaExists($0) },
                                  by: \.senderJID)
            .filter { jid, notes in
                !existing.contains(jid) && !blacklist.contains(jid) && notes.count >= policy.minNotes
            }
        guard !bySender.isEmpty else { return [] }

        var added: [String] = []
        var fingerprints = try db.fingerprints()

        for (jid, notes) in bySender {
            var enrolled: [EnrolledNote] = []
            for note in notes.sorted(by: { $0.date > $1.date }).prefix(policy.maxNotes) {
                guard let analysis = try? await engine.analyze(
                    url: config.locator.mediaURL(relativePath: note.relativeMediaPath)),
                      !analysis.embedding.isEmpty else { continue }
                enrolled.append(EnrolledNote(jid: jid, messagePK: note.messagePK,
                                             embedding: analysis.embedding,
                                             speechSeconds: analysis.speechSeconds, date: note.date))
            }
            let built = Enroller.fingerprints(from: enrolled, policy: policy, center: center,
                                              modelVersion: engine.modelVersion)
            guard let fingerprint = built.first else { continue }
            try db.replaceEnrollment(jid: jid, notes: enrolled)
            fingerprints.append(fingerprint)
            added.append(jid)

            if try db.contact(jid: jid) == nil {
                let who = NameResolver.resolve(jid, tables: tables)
                try db.saveContacts([ContactRecord(jid: jid, displayName: who.displayName,
                                                   isSaved: who.isSavedContact, pinned: false,
                                                   blacklisted: false, avatarPath: who.avatarPath)])
            }
        }

        guard !added.isEmpty else { return [] }
        try db.saveFingerprints(fingerprints)
        // Notes already judged "no baseline yet" can now be judged properly.
        try db.clearUnverifiableVerdicts(for: added, reason: .notEnrolled)
        try db.saveCalibration(Calibrator.calibrate(notes: try db.allEnrollmentNotes(), center: center))
        let pinned = try db.contacts().filter(\.pinned).map(\.jid)
        continuation.yield(.enrollmentFinished(
            fingerprints: fingerprints.count,
            protected: Enroller.protectedJIDs(fingerprints, pinned: pinned, policy: policy)))
        return added
    }

    // MARK: Verification

    /// Everyone the user could name when asked "who does this person say they are?".
    public func claimCandidates() throws -> [ClaimCandidate] {
        if chat == nil { try openStores() }
        let fingerprints = try db.fingerprints()
        let names = Dictionary(fingerprints.map { ($0.jid, NameResolver.resolve($0.jid, tables: tables).displayName) },
                               uniquingKeysWith: { a, _ in a })
        return ClaimCandidate.list(from: fingerprints, names: names)
    }

    /// Re-checks a note the app has already judged, this time against a name the user supplied.
    /// Nothing is stored: the user is asking a question, not correcting the app.
    public func check(messagePK: Int64, claiming claimedJID: String) async throws -> Verdict? {
        guard let stored = try db.verdict(messagePK: messagePK) else { return nil }
        let note = VoiceNoteRecord(messagePK: stored.messagePK, chatJID: stored.chatJID,
                                   senderJID: stored.senderJID, isFromMe: false, date: stored.date,
                                   durationSeconds: stored.durationSeconds,
                                   relativeMediaPath: stored.relativeMediaPath,
                                   chatIsGroup: stored.chatIsGroup)
        return try await judge(note, forcedClaim: claimedJID).verdict
    }

    @discardableResult
    public func verify(_ note: VoiceNoteRecord, now: Date = Date()) async throws -> VerdictRecord {
        let outcome = try await judge(note, forcedClaim: nil)
        let record = VerdictRecord(note: note, verdict: outcome.verdict, speechSeconds: outcome.speechSeconds,
                                   computedAt: now, modelVersion: engine.modelVersion)
        try db.saveVerdict(record)
        continuation.yield(.verdict(record))
        return record
    }

    /// Listens to one note and decides. `forcedClaim` is a name the user supplied, which replaces
    /// the guess made from the sender's own profile name.
    private func judge(_ note: VoiceNoteRecord,
                       forcedClaim: String?) async throws -> (verdict: Verdict, speechSeconds: Double) {
        if chat == nil { try openStores() }
        let fingerprints = try db.fingerprints()
        let thresholds = try db.thresholds()
        let center = try db.embeddingCenter()
        let identity = NameResolver.resolve(note.senderJID, tables: tables)

        var names = Dictionary(fingerprints.map { ($0.jid, NameResolver.resolve($0.jid, tables: tables).displayName) },
                               uniquingKeysWith: { a, _ in a })
        names[note.senderJID] = identity.displayName

        let hasFingerprint = fingerprints.contains { $0.jid == note.senderJID }
        let natural: SenderClass = identity.isSavedContact
            ? (hasFingerprint ? .knownEnrolled : .knownUnenrolled)
            : .unknown
        // Naming someone the user does not have saved asks the impersonation question. Naming the
        // sender themselves is just the ordinary check, and calling their own saved number
        // "a number you have not saved" was both wrong and alarming.
        let senderClass: SenderClass
        if let forcedClaim, forcedClaim != note.senderJID {
            senderClass = .unknown
        } else {
            senderClass = natural
        }

        let url = config.locator.mediaURL(relativePath: note.relativeMediaPath)
        let mediaReady = await waitForMedia(at: url)
        guard mediaReady else {
            return (.unverifiable(.mediaMissing, explanation: "The audio hasn't been downloaded yet."), 0)
        }

        do {
            let analysis = try await engine.analyze(url: url)
            let speech = analysis.speechSeconds
            let projected = center.project(analysis.embedding)
            var comparisons: [Comparison] = []
            if !analysis.embedding.isEmpty {
                for fp in fingerprints {
                    let notes = try db.enrollmentNotes(jid: fp.jid).map { center.project($0.embedding) }
                    comparisons.append(Comparison(jid: fp.jid,
                                                  score: VoiceMatcher.score(probe: projected,
                                                                            centroid: fp.centroid,
                                                                            noteEmbeddings: notes)))
                }
            }
            let claimed = forcedClaim
                ?? (senderClass == .unknown
                    ? ClaimMatcher.claimedJID(pushName: identity.pushName,
                                              enrolled: fingerprints.map(\.jid), names: names)
                    : nil)
            let verdict = Verifier.verdict(
                VerificationInput(senderJID: note.senderJID, senderClass: senderClass,
                                  claimedJID: claimed, speechSeconds: speech,
                                  comparisons: comparisons, names: names),
                thresholds: thresholds)

            if forcedClaim == nil, verdict.kind == .verified, let score = verdict.score {
                try rollingUpdate(note: note, analysis: analysis, score: score,
                                  thresholds: thresholds, fingerprints: fingerprints, center: center)
            }
            return (verdict, speech)
        } catch let error as AudioDecodeError {
            return (.unverifiable(.decodeFailed, explanation: "Couldn't decode this audio (\(error))."), 0)
        } catch {
            return (.unverifiable(.modelFailed, explanation: "Voice analysis failed (\(error))."), 0)
        }
    }

    /// Keeps a fingerprint current as a voice drifts, without letting an impostor into it.
    private func rollingUpdate(note: VoiceNoteRecord, analysis: VoiceAnalysis, score: Float,
                               thresholds: Thresholds, fingerprints: [Fingerprint],
                               center: EmbeddingCenter) throws {
        let candidate = EnrolledNote(jid: note.senderJID, messagePK: note.messagePK,
                                     embedding: analysis.embedding,
                                     speechSeconds: analysis.speechSeconds, date: note.date)
        guard let merged = Enroller.rollingAppend(existing: try db.enrollmentNotes(jid: note.senderJID),
                                                  candidate: candidate, score: score,
                                                  thresholds: thresholds, policy: config.policy) else { return }
        try db.replaceEnrollment(jid: note.senderJID, notes: merged)
        let refreshed = Enroller.fingerprints(from: merged, policy: config.policy, center: center,
                                              modelVersion: engine.modelVersion)
        try db.saveFingerprints(fingerprints.filter { $0.jid != note.senderJID } + refreshed)
    }

    private func waitForMedia(at url: URL) async -> Bool {
        for attempt in 0..<max(1, config.mediaRetries) {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            if attempt < config.mediaRetries - 1 {
                try? await Task.sleep(for: .seconds(config.mediaRetryDelay))
            }
        }
        return false
    }

    // MARK: Catching up

    /// Verifies every candidate note newer than the cursor, then moves the cursor forward without
    /// stepping over notes whose audio has not arrived yet.
    @discardableResult
    public func processNew() async throws -> [VerdictRecord] {
        let store = try openStores()
        let cursor = try db.lastSeenMessagePK()
        var results: [VerdictRecord] = []
        for note in try VoiceNoteQuery.fetch(store, afterPK: cursor) where isCandidate(note) {
            if let existing = try db.verdict(messagePK: note.messagePK),
               existing.reason != UnverifiableReason.mediaMissing.rawValue {
                continue
            }
            results.append(try await verify(note))
        }
        // Someone may have crossed the threshold with the notes just processed.
        try await enrollNewcomers()

        let maxPK = try VoiceNoteQuery.maxMessagePK(store)
        let floor = try VoiceNoteQuery.pendingFloor(store, since: Date().addingTimeInterval(-config.pendingLookback))
        let next = min(maxPK, (floor ?? Int64.max) - 1)
        try db.setLastSeenMessagePK(max(cursor, next))
        return results
    }

    // MARK: Lookups used by the interface

    public func chats(limit: Int = 500) throws -> [ChatSummary] {
        try ChatListQuery.fetch(try openStores(), limit: limit)
    }

    public func messages(sessionPK: Int64, limit: Int = 300) throws -> [ChatMessage] {
        try MessageQuery.fetch(try openStores(), sessionPK: sessionPK, limit: limit)
    }

    public func identity(for jid: String) throws -> ResolvedIdentity {
        if chat == nil { try openStores() }
        return NameResolver.resolve(jid, tables: tables)
    }

    public func setPinned(jid: String, _ pinned: Bool) throws {
        try db.setPinned(jid: jid, pinned)
    }

    /// "Report impostor": take the sender out of the picture entirely. Their fingerprint and
    /// enrolment go, they stay out of future enrolment runs, and the verdict is pinned red.
    public func reportImpostor(messagePK: Int64) throws {
        guard let verdict = try db.verdict(messagePK: messagePK) else { return }
        let jid = verdict.senderJID
        if try db.contact(jid: jid) == nil {
            let who = try identity(for: jid)
            try db.saveContacts([ContactRecord(jid: jid, displayName: who.displayName,
                                               isSaved: who.isSavedContact, pinned: false,
                                               blacklisted: true, avatarPath: who.avatarPath)])
        } else {
            try db.setBlacklisted(jid: jid, true)
        }
        try db.replaceEnrollment(jid: jid, notes: [])
        try db.saveFingerprints(try db.fingerprints().filter { $0.jid != jid })
        try db.overrideVerdict(messagePK: messagePK, kind: .impersonationSuspected, colour: .red,
                               reason: "userReported",
                               explanation: "You reported this sender as an impostor.")
    }

    /// "Yes, this is really them": the user overrules the app, so the note joins the sender's
    /// enrolment regardless of score and the verdict becomes verified.
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

        // A user-confirmed contact gets a fingerprint even on thin evidence; they vouched for it.
        var relaxed = config.policy
        relaxed.minNotes = 1
        relaxed.minSpeechSeconds = 0
        let center = try db.embeddingCenter()
        let refreshed = Enroller.fingerprints(from: kept, policy: relaxed, center: center,
                                              modelVersion: engine.modelVersion)
        try db.saveFingerprints(try db.fingerprints().filter { $0.jid != jid } + refreshed)

        if try db.contact(jid: jid) == nil {
            let who = try identity(for: jid)
            try db.saveContacts([ContactRecord(jid: jid, displayName: who.displayName,
                                               isSaved: who.isSavedContact, pinned: false,
                                               blacklisted: false, avatarPath: who.avatarPath)])
        }
        try db.overrideVerdict(messagePK: messagePK, kind: .verified, colour: .green,
                               reason: "userConfirmed",
                               explanation: "You confirmed this is really \(try identity(for: jid).displayName).")
    }

    public func protectedJIDs() throws -> [String] {
        Enroller.protectedJIDs(try db.fingerprints(),
                               pinned: try db.contacts().filter(\.pinned).map(\.jid),
                               policy: config.policy)
    }
}
