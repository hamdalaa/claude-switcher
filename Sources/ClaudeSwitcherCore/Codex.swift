import Foundation

/// Codex CLI usage, read through `codex app-server` (account/read + account/rateLimits/read).
public struct CodexUsage: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        public let title: String
        public let window: UsageWindow

        public init(title: String, window: UsageWindow) {
            self.title = title
            self.window = window
        }
    }

    public init(email: String?, plan: String?, windows: [Window], limitReached: Bool, updatedAt: Date) {
        self.email = email
        self.plan = plan
        self.windows = windows
        self.limitReached = limitReached
        self.updatedAt = updatedAt
    }

    public let email: String?
    public let plan: String?
    public let windows: [Window]
    public let limitReached: Bool
    public let updatedAt: Date

    /// Percent left in the tightest window — what decides whether Codex can be used right now.
    public var percentLeft: Int? {
        windows.map { 100 - $0.window.percent }.min().map { max($0, 0) }
    }
}

public enum CodexAPI {
    public enum ParseError: Error { case unexpected }

    /// `limits` is the result of account/rateLimits/read; `account` of account/read (optional).
    public static func parse(limits: Data, account: Data?, now: Date = .now) throws -> CodexUsage {
        guard let root = try JSONSerialization.jsonObject(with: limits) as? [String: Any] else {
            throw ParseError.unexpected
        }
        let bucket = ((root["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any])
            ?? (root["rateLimits"] as? [String: Any])
        guard let bucket else { throw ParseError.unexpected }

        let windows: [CodexUsage.Window] = ["primary", "secondary"].compactMap { key in
            guard let raw = bucket[key] as? [String: Any],
                  let used = raw["usedPercent"] as? NSNumber else { return nil }
            let minutes = (raw["windowDurationMins"] as? NSNumber)?.intValue ?? 0
            let resets = (raw["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return .init(title: title(minutes: minutes),
                         window: UsageWindow(percent: Int(used.doubleValue.rounded(.down)), resetsAt: resets))
        }
        let reached = !(bucket["rateLimitReachedType"] is NSNull || bucket["rateLimitReachedType"] == nil)
            || (bucket["spendControlReached"] as? Bool) == true

        var email: String?
        var plan = bucket["planType"] as? String
        if let account, let object = try? JSONSerialization.jsonObject(with: account) as? [String: Any],
           let info = object["account"] as? [String: Any] {
            email = info["email"] as? String
            plan = (info["planType"] as? String) ?? plan
        }
        return CodexUsage(email: email, plan: plan.map(planLabel), windows: windows,
                          limitReached: reached, updatedAt: now)
    }

    static func title(minutes: Int) -> String {
        switch minutes {
        case 10080: "Weekly"
        case 1440: "Daily"
        case let m where m > 0 && m % 60 == 0: "\(m / 60)-hour"
        case let m where m > 0: "\(m)-min"
        default: "Limit"
        }
    }

    /// "prolite" → "Pro Lite", "plus" → "Plus", "team" → "Team".
    public static func planLabel(_ raw: String) -> String {
        let known = ["prolite": "Pro Lite", "plus": "Plus", "pro": "Pro", "free": "Free", "team": "Team",
                     "business": "Business", "enterprise": "Enterprise", "edu": "Edu"]
        return known[raw.lowercased()] ?? raw.prefix(1).uppercased() + raw.dropFirst()
    }
}

extension CodexAPI {
    /// app-server errors embed the raw HTTP response; show what the user can act on instead.
    public static func friendlyError(_ message: String?) -> String {
        guard let message, !message.isEmpty else { return "Sign in to Codex (codex login)" }
        let lower = message.lowercased()
        if ["401", "unauthorized", "token_revoked", "token_expired", "invalidated oauth", "not logged in", "login"]
            .contains(where: lower.contains) {
            return "Signed out — run codex login"
        }
        if lower.contains("429") || lower.contains("too many requests") { return "Codex is rate limiting — try again soon" }
        if ["timed out", "offline", "network", "connect"].contains(where: lower.contains) { return "Codex is offline" }
        let firstLine = message.split(separator: "\n").first.map(String.init) ?? message
        let short = firstLine.split(separator: ";").first.map(String.init) ?? firstLine
        return "Codex: " + String(short.prefix(80))
    }
}
