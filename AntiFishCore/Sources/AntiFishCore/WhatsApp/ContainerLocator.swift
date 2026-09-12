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

    /// Full Disk Access probe: TCC blocks the `open()` itself, so a 1-byte read is the only honest test.
    public var hasFullDiskAccess: Bool {
        guard let handle = try? FileHandle(forReadingFrom: chatStorageURL) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1)) != nil
    }

    public func mediaURL(relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }
}
