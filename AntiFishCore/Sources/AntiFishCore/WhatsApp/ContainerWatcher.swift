import CoreServices
import Foundation

/// Watches WhatsApp's container for arriving voice notes and message-database writes.
///
/// Emits one debounced callback per burst of changes, plus a slow poll as a safety net in case
/// the file-system stream misses something. Call `stop()` before releasing the watcher.
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

    public init(root: URL, debounce: TimeInterval = 1.5, pollInterval: TimeInterval = 60,
                handler: @escaping Handler) {
        self.root = root
        self.debounce = debounce
        self.pollInterval = pollInterval
        self.handler = handler
    }

    /// Voice-note files under Message/Media, and the message database or its write-ahead log.
    /// Everything else in the container changes constantly and is none of our business.
    static func isRelevant(_ path: String) -> Bool {
        if path.hasSuffix("/ChatStorage.sqlite") || path.hasSuffix("/ChatStorage.sqlite-wal") { return true }
        guard path.contains("/Message/Media/"), !path.contains("/Message/Media/Profile/") else { return false }
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
            let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer)
            guard let created = FSEventStreamCreate(nil, callback, &context, [root.path] as CFArray,
                                                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                                    1.0, flags) else { return }
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

    /// Called on `queue` by the file-system callback. Collapses a burst of writes into one call.
    private func scheduleFire() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.handler() }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }
}
