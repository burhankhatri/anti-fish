import AntiFishCore
import Foundation

enum CLIError: Error {
    case usage
    case whatsAppUnavailable(String)
    case modelsMissing(String)
}

struct CLIOptions {
    var command = "status"
    var args: [String] = []
    var dbURL: URL? = AppDatabase.defaultURL()
    var modelsDir: URL = {
        if let path = ProcessInfo.processInfo.environment["ANTIFISH_MODELS_DIR"] {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "AntiFish/Resources/Models")
    }()

    static func parse(_ argv: [String]) throws -> CLIOptions {
        var options = CLIOptions()
        var rest = Array(argv.dropFirst())
        while let flag = rest.first, flag.hasPrefix("--"), flag != "--newest" {
            rest.removeFirst()
            switch flag {
            case "--db":
                guard !rest.isEmpty else { throw CLIError.usage }
                options.dbURL = URL(fileURLWithPath: rest.removeFirst())
            case "--memory-db":
                options.dbURL = nil
            case "--models":
                guard !rest.isEmpty else { throw CLIError.usage }
                options.modelsDir = URL(fileURLWithPath: rest.removeFirst())
            default:
                throw CLIError.usage
            }
        }
        if let command = rest.first {
            options.command = command
            rest.removeFirst()
        }
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
        case "chats": try chats()
        default: throw CLIError.usage
        }
    }

    // MARK: Preconditions

    private func requireWhatsApp() throws {
        guard locator.isInstalled else {
            throw CLIError.whatsAppUnavailable("WhatsApp Desktop is not linked on this Mac")
        }
        guard locator.hasFullDiskAccess else {
            throw CLIError.whatsAppUnavailable(
                "Full Disk Access is required. System Settings > Privacy & Security > Full Disk Access")
        }
    }

    private func makeCoordinator() throws -> (Coordinator, AppDatabase) {
        let models = ModelPaths(directory: options.modelsDir)
        guard FileManager.default.fileExists(atPath: models.speakerModel),
              FileManager.default.fileExists(atPath: models.vadModel) else {
            throw CLIError.modelsMissing(options.modelsDir.path)
        }
        let db = try AppDatabase(url: options.dbURL)
        let engine = try VoiceEngine(models: models, numThreads: 4)
        return (Coordinator(config: CoordinatorConfig(locator: locator, models: models), db: db, engine: engine), db)
    }

    // MARK: Commands

    func status() throws {
        print("WhatsApp container: \(locator.isInstalled ? "found" : "missing")")
        print("Full Disk Access:   \(locator.hasFullDiskAccess ? "granted" : "denied")")
        let models = ModelPaths(directory: options.modelsDir)
        let haveModels = FileManager.default.fileExists(atPath: models.speakerModel)
        print("Models:             \(haveModels ? "present" : "missing") at \(options.modelsDir.path)")
        guard locator.isInstalled, locator.hasFullDiskAccess else { return }

        let store = try ChatStore.open(url: locator.chatStorageURL)
        let notes = try VoiceNoteQuery.fetch(store)
        let incoming = notes.filter { !$0.isFromMe }
        let onDisk = incoming.filter {
            FileManager.default.fileExists(atPath: locator.mediaURL(relativePath: $0.relativeMediaPath).path)
        }
        print("Voice notes:        \(notes.count) total, \(incoming.count) incoming, \(onDisk.count) on disk")

        let db = try AppDatabase(url: options.dbURL)
        let fingerprints = try db.fingerprints()
        let t = try db.thresholds()
        print("Fingerprints:       \(fingerprints.count)")
        print(String(format: "Decision point:     %.2f  (%@)",
                     t.decision, t.calibrated ? "learned from your contacts" : "starting value"))
        if let c = try db.calibration() {
            print(String(format: "Calibration:        %d contacts, your people score %.2f, strangers %.2f, error %.0f%%",
                         c.contactCount, c.genuineMedian, c.impostorMedian, c.errorRate * 100))
        }
    }

    func enroll() async throws {
        try requireWhatsApp()
        let (coordinator, db) = try makeCoordinator()
        print("Listening to the voice notes already on this Mac. This runs once and takes a few minutes.")
        let started = Date()
        let fingerprints = try await coordinator.enrollAll()
        let contacts = Dictionary(uniqueKeysWithValues: try db.contacts().map { ($0.jid, $0) })
        print("\nEnrolled \(fingerprints.count) contacts in \(Int(Date().timeIntervalSince(started))) s\n")
        for fp in fingerprints {
            let contact = contacts[fp.jid]
            let name = contact?.displayName ?? fp.jid
            let saved = contact?.isSaved == true ? "saved" : "unsaved"
            print(String(format: "  %-30@ %3d notes  %5.0f s of speech  %@",
                         name as NSString, fp.noteCount, fp.speechSeconds, saved))
        }
        if let c = try db.calibration() {
            print(String(format: "\nCalibration: %d contacts, genuine median %.2f vs impostor median %.2f",
                         c.contactCount, c.genuineMedian, c.impostorMedian))
            print(String(format: "Decision point: %.2f  (%@), wrong about %.0f%% of the time",
                         c.thresholds.decision,
                         c.thresholds.calibrated ? "learned from your contacts" : "starting value",
                         c.errorRate * 100))
        }
    }

    func verify() async throws {
        try requireWhatsApp()
        let (coordinator, _) = try makeCoordinator()
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let candidates = try VoiceNoteQuery.fetch(store).filter {
            !$0.isFromMe && !$0.senderJID.isEmpty && !$0.senderJID.hasPrefix("status@")
                && FileManager.default.fileExists(atPath: locator.mediaURL(relativePath: $0.relativeMediaPath).path)
        }

        var targets: [VoiceNoteRecord] = []
        if options.args.isEmpty || options.args[0] == "--newest" {
            let count = Int(options.args.dropFirst().first ?? "1") ?? 1
            targets = Array(candidates.suffix(count))
        } else {
            let needle = options.args[0]
            targets = candidates.filter {
                $0.relativeMediaPath == needle
                    || locator.mediaURL(relativePath: $0.relativeMediaPath).path == needle
                    || String($0.messagePK) == needle
            }
            if targets.isEmpty {
                print("No voice note matches \(needle)")
                return
            }
        }

        for note in targets {
            let record = try await coordinator.verify(note)
            printVerdict(record, coordinator: coordinator)
        }
    }

    func chats() throws {
        try requireWhatsApp()
        let store = try ChatStore.open(url: locator.chatStorageURL)
        let contacts = try? ChatStore.open(url: locator.contactsURL)
        let tables = try NameTables.load(chat: store, contacts: contacts)
        let list = try ChatListQuery.fetch(store)
        let limit = Int(options.args.first ?? "15") ?? 15
        print("\(list.count) chats\n")
        for chat in list.prefix(limit) {
            let name = chat.savedName?.isEmpty == false
                ? chat.savedName!
                : NameResolver.resolve(chat.jid, tables: tables).displayName
            let messages = try MessageQuery.fetch(store, sessionPK: chat.sessionPK, limit: 40)
            let notes = messages.filter { $0.kind == .voiceNote && !$0.isFromMe }.count
            let last = messages.last.map { m -> String in
                let body = m.text ?? m.kind.placeholder
                return String(body.prefix(40)).replacingOccurrences(of: "\n", with: " ")
            } ?? ""
            print(String(format: "  %-28@ %@ %2d msgs %2d voice  %@",
                         name as NSString, chat.isGroup ? "group" : "  1:1", messages.count, notes, last))
        }
    }

    func calibrate() throws {
        let db = try AppDatabase(url: options.dbURL)
        let result = Calibrator.calibrate(notes: try db.allEnrollmentNotes(), center: try db.embeddingCenter())
        try db.saveCalibration(result)
        print("contacts=\(result.contactCount) genuine=\(result.genuineCount) impostor=\(result.impostorCount)")
        print(String(format: "genuine median %.3f vs impostor median %.3f", result.genuineMedian, result.impostorMedian))
        print(String(format: "decision point %.3f  (%@), error %.1f%%",
                     result.thresholds.decision,
                     result.thresholds.calibrated ? "calibrated" : "starting value",
                     result.errorRate * 100))
    }

    func feed() throws {
        let db = try AppDatabase(url: options.dbURL)
        let limit = Int(options.args.first ?? "20") ?? 20
        let verdicts = try db.verdicts(limit: limit)
        if verdicts.isEmpty {
            print("No verdicts yet. Run `antifish enroll`, then `antifish verify --newest 5`.")
            return
        }
        let names = Dictionary(uniqueKeysWithValues: try db.contacts().map { ($0.jid, $0.displayName) })
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM HH:mm"
        for v in verdicts {
            let who = names[v.senderJID] ?? NameResolver.fallbackName(for: v.senderJID)
            print("\(formatter.string(from: v.date))  [\(v.colour.uppercased())] \(who)")
            print("    \(v.explanation)")
        }
    }

    private func printVerdict(_ record: VerdictRecord, coordinator: Coordinator) {
        let score = record.score.map { String(format: "%.2f", $0) } ?? "-"
        print("[\(record.colour.uppercased())] \(record.kind)  score=\(score)  speech=\(String(format: "%.1f", record.speechSeconds))s")
        print("    \(record.explanation)")
    }
}
