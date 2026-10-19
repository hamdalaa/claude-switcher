import CryptoKit
import Foundation

/// Anthropic's OAuth usage endpoint — the same numbers as Claude Code's `/usage`.
public enum UsageAPI {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let betaHeader = "oauth-2025-04-20"

    /// Claude Code's Keychain item for an account. A custom CLAUDE_CONFIG_DIR gets a suffix of the
    /// first 8 hex chars of SHA-256(config dir path), so each account has its own login.
    public static func keychainService(_ account: Account, paths: Paths) -> String {
        switch account {
        case .a: return "Claude Code-credentials"
        case .b:
            let dir = paths.configJSON(.b).deletingLastPathComponent().path(percentEncoded: false)
            let trimmed = dir.hasSuffix("/") ? String(dir.dropLast()) : dir
            let digest = SHA256.hash(data: Data(trimmed.utf8))
            return "Claude Code-credentials-" + digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        }
    }

    public enum ParseError: Error { case unexpected }

    /// Prefers the `limits` list (session / weekly_all); falls back to five_hour / seven_day.
    public static func parse(_ data: Data, now: Date = .now) throws -> Usage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.unexpected
        }
        var five: UsageWindow?
        var seven: UsageWindow?
        if let limits = root["limits"] as? [[String: Any]] {
            for limit in limits {
                let window = UsageWindow(
                    percent: (limit["percent"] as? NSNumber)?.intValue ?? 0,
                    resetsAt: date(limit["resets_at"])
                )
                switch limit["kind"] as? String {
                case "session": five = window
                case "weekly_all": seven = window
                default: break
                }
            }
        }
        five = five ?? legacy(root["five_hour"])
        seven = seven ?? legacy(root["seven_day"])
        guard five != nil || seven != nil else { throw ParseError.unexpected }
        return Usage(fiveHour: five, sevenDay: seven, updatedAt: now, isLive: true)
    }

    private static func legacy(_ value: Any?) -> UsageWindow? {
        guard let dict = value as? [String: Any], let used = dict["utilization"] as? NSNumber else { return nil }
        return UsageWindow(percent: Int(used.doubleValue.rounded(.down)), resetsAt: date(dict["resets_at"]))
    }

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? withFraction.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
    }
}

/// Claude Code's stored sign-in. Only the access token and expiry are used; never printed.
public struct Credentials: Sendable, CustomStringConvertible {
    public let accessToken: String
    public let expiresAt: Date?
    public let subscriptionType: String?
    public let rateLimitTier: String?

    /// "Max 20x", "Max 5x", "Pro", … — nil when Claude Code didn't record a plan.
    public var planLabel: String? { Plan.label(subscription: subscriptionType, tier: rateLimitTier) }

    public init?(json: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        accessToken = token
        expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        subscriptionType = oauth["subscriptionType"] as? String
        rateLimitTier = oauth["rateLimitTier"] as? String
    }

    /// The last minute counts as expired so a request never races the expiry.
    public func isExpired(at now: Date = .now) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) < 60
    }

    public var description: String { "Credentials(token: <redacted>)" }
}

public enum Plan {
    /// subscription "max" + tier "default_claude_max_20x" → "Max 20x"; "pro" → "Pro".
    public static func label(subscription: String?, tier: String?) -> String? {
        guard let subscription, !subscription.isEmpty else { return nil }
        let name = subscription.prefix(1).uppercased() + subscription.dropFirst().lowercased()
        if let tier, let range = tier.range(of: #"\d+x$"#, options: .regularExpression) {
            return "\(name) \(tier[range])"
        }
        return name
    }
}
