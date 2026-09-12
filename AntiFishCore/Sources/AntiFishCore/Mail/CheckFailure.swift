import Foundation

public enum CheckFailureKind: String, Sendable, Codable, CaseIterable {
    case notConfigured, quotaReached, offline, failed

    public var defaultMessage: String {
        switch self {
        case .notConfigured:
            "Checking is switched off. It needs SightEngine keys, and it sends the picture to their service."
        case .quotaReached:
            "The daily limit on the free SightEngine plan has been used up. It resets tomorrow."
        case .offline:
            "No internet connection, so the picture could not be sent for checking."
        case .failed:
            "The check did not complete, so nothing is known about this picture."
        }
    }
}

/// Why a check did not happen. Carried all the way to the interface, because a silent failure that
/// looks like a pass is worse than no feature at all.
public struct CheckFailure: Sendable, Codable, Equatable {
    public let kind: CheckFailureKind
    public let message: String

    public init(kind: CheckFailureKind, message: String) {
        self.kind = kind
        self.message = message
    }

    public static func from(errorText: String) -> CheckFailure {
        let text = errorText.lowercased()
        let kind: CheckFailureKind
        if text.contains("credential") || text.contains("api_user") {
            kind = .notConfigured
        } else if text.contains("usage limit") || text.contains("quota") || text.contains("upgrade your plan") {
            kind = .quotaReached
        } else if text.contains("offline") || text.contains("urlerror") || text.contains("timed out")
                    || text.contains("nodename nor servname") {
            kind = .offline
        } else {
            kind = .failed
        }
        return CheckFailure(kind: kind, message: kind.defaultMessage)
    }
}
