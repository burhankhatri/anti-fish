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
    var lastNeedingAttention: FeedItem?
    var selectedItemID: Int64?
    var needsRebuild = false

    // Which side of the app is showing, and what the mail side has found.
    var source: AppSource = .whatsapp
    var mailScan: MailScan?
    var isScanningMail = false
    var mailError: String?
    var selectedMailID: String?

    var mailMessages: [MailMessage] { mailScan?.messages ?? [] }
    var dangerMailCount: Int { mailMessages.filter { $0.tier == .danger }.count }
    var selectedMail: MailMessage? { mailMessages.first { $0.id == selectedMailID } }

    // WhatsApp-shaped state: a list of chats, one of them open.
    var chats: [ChatRow] = []
    var selectedChatPK: Int64?
    var thread: [ThreadItem] = []
    var isLoadingThread = false
    var chatSearch = ""
    var chatOrder: ChatOrder = .recent {
        didSet { Task { try? await refreshChats() } }
    }

    var visibleChats: [ChatRow] {
        guard !chatSearch.isEmpty else { return chats }
        let needle = chatSearch.lowercased()
        return chats.filter { $0.displayName.lowercased().contains(needle) }
    }

    var selectedChat: ChatRow? {
        chats.first { $0.id == selectedChatPK }
    }

    let locator: ContainerLocator
    let notifier = Notifier()
    let player = NotePlayer()

    private let databaseURL: URL?
    private let modelsDirectory: URL
    private(set) var coordinator: Coordinator?
    private var db: AppDatabase?
    private var watcher: ContainerWatcher?
    private var eventTask: Task<Void, Never>?
    private var pendingPass = false
    private var identities: [String: ResolvedIdentity] = [:]
    private var waveforms: [Int64: [Float]] = [:]
    private var previews: [Int64: String] = [:]
    private let mailReader = MailReader()
    private let imageCheck = ImageCheck()

    init(locator: ContainerLocator = AppModel.defaultLocator,
         databaseURL: URL? = AppModel.defaultDatabaseURL,
         modelsDirectory: URL = AppModel.defaultModelsDirectory) {
        self.locator = locator
        self.databaseURL = databaseURL
        self.modelsDirectory = modelsDirectory
    }

    // Environment overrides let the interface tests point at a fixture container and a scratch store.
    static var defaultLocator: ContainerLocator {
        if let root = ProcessInfo.processInfo.environment["ANTIFISH_CONTAINER_ROOT"] {
            return ContainerLocator(root: URL(fileURLWithPath: root))
        }
        return ContainerLocator()
    }

    static var defaultDatabaseURL: URL? {
        if let path = ProcessInfo.processInfo.environment["ANTIFISH_DB_PATH"] {
            return URL(fileURLWithPath: path)
        }
        return AppDatabase.defaultURL()
    }

    static var defaultModelsDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["ANTIFISH_MODELS_DIR"] {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.resourceURL?.appendingPathComponent("Models")
            ?? URL(fileURLWithPath: "AntiFish/Resources/Models")
    }

    // MARK: Starting up

    func start() async {
        guard locator.isInstalled else {
            phase = .needsWhatsApp
            statusLine = "WhatsApp Desktop not found"
            return
        }
        guard locator.hasFullDiskAccess else {
            phase = .needsFullDiskAccess
            statusLine = "Waiting for Full Disk Access"
            return
        }
        do {
            let db = try self.db ?? AppDatabase(url: databaseURL)
            self.db = db
            try checkRelink(db)

            if coordinator == nil {
                let models = ModelPaths(directory: modelsDirectory)
                let engine = try VoiceEngine(models: models, numThreads: 4)
                let coordinator = Coordinator(config: CoordinatorConfig(locator: locator, models: models),
                                              db: db, engine: engine)
                self.coordinator = coordinator
                eventTask = Task { [weak self] in
                    for await event in coordinator.events { await self?.handle(event) }
                }
            }

            if try db.setting("onboardingDone") != "1" {
                phase = .setupChoices
                statusLine = "Finish setup"
                return
            }
            if try db.fingerprints().isEmpty, let coordinator {
                phase = .enrolling(done: 0, total: 0)
                statusLine = "Building fingerprints"
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

    /// A re-linked WhatsApp writes a fresh database. The old fingerprints still describe the same
    /// people, but the user should be told so they can rebuild.
    private func checkRelink(_ db: AppDatabase) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: locator.chatStorageURL.path)
        let created = (attributes[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0
        if let stored = try db.setting("containerCreated"), let previous = Double(stored),
           abs(previous - created) > 1, !(try db.fingerprints().isEmpty) {
            needsRebuild = true
            banner = "WhatsApp was re-linked on this Mac. Fingerprints may be stale — rebuild them in Settings."
        }
        try db.setSetting("containerCreated", String(created))
    }

    func rebuildFingerprints() async {
        guard let db, let coordinator else { return }
        phase = .enrolling(done: 0, total: 0)
        do {
            for jid in Set(try db.allEnrollmentNotes().map(\.jid)) {
                try db.replaceEnrollment(jid: jid, notes: [])
            }
            try db.saveFingerprints([])
            try await coordinator.enrollAll()
            needsRebuild = false
            banner = nil
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
            if let item = feed.first(where: { $0.id == record.messagePK }), item.needsAttention {
                lastNeedingAttention = item
                notifier.notify(item)
            }
        case .error(let message):
            banner = message
        }
    }

    // MARK: Projections

    func refresh() async throws {
        try await refreshFeed()
        try await refreshChats()
        try await refreshContacts()
        calibration = try db?.calibration()
        if selectedChatPK != nil { try await refreshThread() }
    }

    // MARK: Checking a claim

    /// Everyone the user could name when asked who a caller claims to be.
    var claimCandidates: [ClaimCandidate] = []
    /// The answer to the last claim the user tested, keyed by message.
    var claimResults: [Int64: Verdict] = [:]
    var claimInFlight: Int64?

    func loadClaimCandidates() async {
        claimCandidates = (try? await coordinator?.claimCandidates()) ?? []
    }

    /// "This person says they are Abdul." Asks the question and keeps the answer beside the note.
    func checkClaim(_ item: ThreadItem, claiming jid: String) async {
        claimInFlight = item.id
        defer { claimInFlight = nil }
        if let verdict = try? await coordinator?.check(messagePK: item.id, claiming: jid) {
            claimResults[item.id] = verdict
        }
    }

    func clearClaim(_ item: ThreadItem) {
        claimResults.removeValue(forKey: item.id)
    }

    // MARK: Email

    /// Shows whatever the last scan found straight away; a fresh scan runs only when asked.
    func loadCachedMail() {
        mailScan = try? mailReader.cachedScan()
    }

    func scanMail() async {
        guard !isScanningMail else { return }
        isScanningMail = true
        mailError = nil
        defer { isScanningMail = false }
        do {
            let reader = mailReader
            mailScan = try await Task.detached(priority: .userInitiated) {
                try reader.scan(limit: 400, pick: 30)
            }.value
        } catch {
            mailError = "Couldn't read your mail: \(error)"
        }
    }

    var mailIsAvailable: Bool { mailReader.isAvailable }
    var imageCheckAvailable: Bool { imageCheck.isConfigured }
    var imageCheckReason: String { imageCheck.unavailableReason }

    // MARK: Chats

    func refreshChats() async throws {
        guard let coordinator else { return }
        let hidden = Set((try? db?.hiddenChatJIDs()) ?? [])
        let summaries = chatOrder.apply(to: try await coordinator.chats().filter { !hidden.contains($0.jid) })
        let verdicts = Dictionary(grouping: try db?.verdicts(limit: 500) ?? [], by: \.chatJID)

        var rows: [ChatRow] = []
        for summary in summaries {
            let who = await identity(summary.jid)
            let name = summary.savedName?.isEmpty == false ? summary.savedName! : who.displayName
            let avatar = who.avatarPath
                .map { locator.mediaURL(relativePath: $0) }
                .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            let attention = verdicts[summary.jid]?.filter(\.isRed).count ?? 0
            rows.append(ChatRow(summary: summary, displayName: name, avatarURL: avatar,
                                preview: previews[summary.sessionPK] ?? "", attentionCount: attention))
        }
        chats = rows
    }

    /// Opens a chat: shows what is already known straight away, then checks any voice notes in it
    /// that have never been looked at.
    func openChat(_ chat: ChatRow) async {
        selectedChatPK = chat.id
        thread = []
        try? await refreshThread()
        await verifyUnjudgedNotes(in: chat)
    }

    func refreshThread() async throws {
        guard let coordinator, let sessionPK = selectedChatPK else { return }
        let messages = try await coordinator.messages(sessionPK: sessionPK)
        var items: [ThreadItem] = []
        for message in messages {
            let name = message.isFromMe ? "You" : await identity(message.senderJID).displayName
            items.append(ThreadItem(message: message, senderName: name,
                                    verdict: try db?.verdict(messagePK: message.messagePK)))
        }
        thread = items
        if let last = messages.last {
            previews[sessionPK] = Self.preview(for: last)
        }
    }

    /// Verifies the voice notes in this chat that have no verdict yet, newest first so the ones
    /// the user is looking at resolve first.
    private func verifyUnjudgedNotes(in chat: ChatRow) async {
        guard let coordinator, let db else { return }
        isLoadingThread = true
        defer { isLoadingThread = false }
        let pending = thread.filter { $0.isVoiceNote && !$0.isFromMe && $0.verdict == nil
                                       && $0.message.relativeMediaPath != nil }
        for item in pending.reversed().prefix(30) {
            guard let path = item.message.relativeMediaPath else { continue }
            let note = VoiceNoteRecord(messagePK: item.message.messagePK,
                                       chatJID: chat.summary.jid,
                                       senderJID: item.message.senderJID,
                                       isFromMe: false,
                                       date: item.message.date,
                                       durationSeconds: item.message.durationSeconds,
                                       relativeMediaPath: path,
                                       chatIsGroup: chat.isGroup)
            _ = try? await coordinator.verify(note)
            if selectedChatPK == chat.id { try? await refreshThread() }
        }
        _ = db
    }

    /// Takes a chat out of the list. WhatsApp never learns about it; this is AntiFish's own view.
    func hideChat(_ chat: ChatRow) async {
        try? db?.setChatHidden(jid: chat.summary.jid, true)
        if selectedChatPK == chat.id { selectedChatPK = nil; thread = [] }
        try? await refreshChats()
    }

    func hideChats(matching predicate: (ChatRow) -> Bool) async {
        for chat in chats where predicate(chat) {
            try? db?.setChatHidden(jid: chat.summary.jid, true)
        }
        try? await refreshChats()
    }

    var hiddenChatCount: Int { ((try? db?.hiddenChatJIDs()) ?? [])?.count ?? 0 }

    func unhideAllChats() async {
        for jid in ((try? db?.hiddenChatJIDs()) ?? []) ?? [] {
            try? db?.setChatHidden(jid: jid, false)
        }
        try? await refreshChats()
    }

    static func preview(for message: ChatMessage) -> String {
        if let text = message.text, !text.isEmpty { return text }
        return message.kind.placeholder
    }

    private func identity(_ jid: String) async -> ResolvedIdentity {
        if let hit = identities[jid] { return hit }
        let resolved = (try? await coordinator?.identity(for: jid))
            ?? ResolvedIdentity(jid: jid, displayName: NameResolver.fallbackName(for: jid),
                                isSavedContact: false, pushName: nil, avatarPath: nil)
        identities[jid] = resolved
        return resolved
    }

    func refreshFeed() async throws {
        guard let db else { return }
        var items: [FeedItem] = []
        for record in try db.verdicts(limit: 500) {
            let sender = await identity(record.senderJID)
            let chat = record.chatIsGroup ? await identity(record.chatJID).displayName : nil
            let avatar = sender.avatarPath
                .map { locator.mediaURL(relativePath: $0) }
                .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            items.append(FeedItem(record: record, senderName: sender.displayName,
                                  chatName: chat, avatarURL: avatar))
        }
        feed = items
    }

    func refreshContacts() async throws {
        guard let db, let coordinator else { return }
        let fingerprints = Dictionary(try db.fingerprints().map { ($0.jid, $0) },
                                      uniquingKeysWith: { a, _ in a })
        let protected = try await coordinator.protectedJIDs()
        protectedJIDs = protected

        var rows: [ContactRow] = []
        for contact in try db.contacts() where !contact.blacklisted {
            let fp = fingerprints[contact.jid]
            let tier: ContactRow.Tier = protected.contains(contact.jid)
                ? .protected
                : (fp != nil ? .enrolled : .needsVoice)
            rows.append(ContactRow(jid: contact.jid, name: contact.displayName, isSaved: contact.isSaved,
                                   pinned: contact.pinned, noteCount: fp?.noteCount ?? 0,
                                   speechSeconds: fp?.speechSeconds ?? 0, lastNoteDate: fp?.lastNoteDate,
                                   tier: tier,
                                   avatarURL: contact.avatarPath.map { locator.mediaURL(relativePath: $0) }))
        }
        contacts = Self.sorted(rows)
        if !isPaused {
            statusLine = "Watching · \(protected.count) protected · \(fingerprints.count) enrolled"
        }
    }

    /// Tier first, pinned to the top of their tier, then most recently heard from.
    static func sorted(_ rows: [ContactRow]) -> [ContactRow] {
        rows.sorted { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.pinned != b.pinned { return a.pinned }
            return (a.lastNoteDate ?? .distantPast) > (b.lastNoteDate ?? .distantPast)
        }
    }

    func name(for jid: String) -> String {
        contacts.first { $0.jid == jid }?.name
            ?? identities[jid]?.displayName
            ?? NameResolver.fallbackName(for: jid)
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

    /// One pass at a time; a burst of arrivals collapses into a single follow-up.
    func schedulePass() {
        guard !isPaused, let coordinator else { return }
        if isProcessing {
            pendingPass = true
            return
        }
        isProcessing = true
        Task { [weak self] in
            do {
                _ = try await coordinator.processNew()
            } catch {
                await MainActor.run { self?.banner = error.localizedDescription }
            }
            guard let self else { return }
            try? await self.refresh()
            self.isProcessing = false
            if self.pendingPass {
                self.pendingPass = false
                self.schedulePass()
            }
        }
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused {
            statusLine = "Paused"
        } else {
            schedulePass()
        }
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
        let result = Calibrator.calibrate(notes: (try? db.allEnrollmentNotes()) ?? [],
                                          center: (try? db.embeddingCenter()) ?? .identity)
        try? db.saveCalibration(result)
        calibration = result
    }

    /// Bar heights for the detail view's waveform, computed once per note and kept.
    func waveform(for item: FeedItem, bars: Int = 40) async -> [Float] {
        if let cached = waveforms[item.id] { return cached }
        let url = mediaURL(for: item)
        let levels = await Task.detached(priority: .userInitiated) { () -> [Float] in
            guard let decoded = try? OpusDecoder.decode(url: url), !decoded.samples.isEmpty else { return [] }
            let chunk = max(1, decoded.samples.count / bars)
            var out: [Float] = []
            out.reserveCapacity(bars)
            for start in stride(from: 0, to: decoded.samples.count, by: chunk) {
                let end = min(start + chunk, decoded.samples.count)
                let slice = decoded.samples[start..<end]
                let rms = (slice.reduce(0) { $0 + $1 * $1 } / Float(slice.count)).squareRoot()
                out.append(rms)
            }
            let peak = out.max() ?? 1
            return peak > 0 ? out.map { $0 / peak } : out
        }.value
        waveforms[item.id] = levels
        return levels
    }

    func mediaURL(for item: FeedItem) -> URL {
        locator.mediaURL(relativePath: item.record.relativeMediaPath)
    }

    func waveform(forThread item: ThreadItem, bars: Int = 28) async -> [Float] {
        guard let url = mediaURL(for: item) else { return [] }
        if let cached = waveforms[item.id] { return cached }
        let levels = await Task.detached(priority: .utility) { () -> [Float] in
            guard let decoded = try? OpusDecoder.decode(url: url), !decoded.samples.isEmpty else { return [] }
            let chunk = max(1, decoded.samples.count / bars)
            var out: [Float] = []
            for start in stride(from: 0, to: decoded.samples.count, by: chunk) {
                let end = min(start + chunk, decoded.samples.count)
                let slice = decoded.samples[start..<end]
                out.append((slice.reduce(0) { $0 + $1 * $1 } / Float(slice.count)).squareRoot())
            }
            let peak = out.max() ?? 1
            return peak > 0 ? out.map { max(0.12, $0 / peak) } : out
        }.value
        waveforms[item.id] = levels
        return levels
    }

    func mediaURL(for item: ThreadItem) -> URL? {
        item.message.relativeMediaPath.map { locator.mediaURL(relativePath: $0) }
    }

    var thresholds: Thresholds { calibration?.thresholds ?? Thresholds() }
}
