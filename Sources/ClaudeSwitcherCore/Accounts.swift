import Foundation

/// The two Claude Code accounts managed by `ccx`. A lives in ~/.claude, B in ~/.claude-b.
public enum Account: String, CaseIterable, Sendable, Identifiable {
    case a, b
    public var id: String { rawValue }
    public var label: String { rawValue.uppercased() }
}

/// Which account a new `ccx` session starts on. Mirrors ~/.claude-accounts/default.
public enum Mode: Equatable, Sendable {
    case auto
    case pinned(Account)
}

/// One rate-limit window as last reported by Claude Code's status line.
public struct UsageWindow: Equatable, Sendable {
    public let percent: Int
    public let resetsAt: Date?

    public init(percent: Int, resetsAt: Date?) {
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

/// Last-known usage for an account. `updatedAt` is when a session last recorded it.
public struct Usage: Equatable, Sendable {
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?
    public let updatedAt: Date?
    /// True when read from Anthropic just now; false when it's the last value a session recorded.
    public let isLive: Bool

    public init(fiveHour: UsageWindow?, sevenDay: UsageWindow?, updatedAt: Date?, isLive: Bool = false) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.updatedAt = updatedAt
        self.isLive = isLive
    }

    /// Windows whose reset time has passed count as 0% — a held value must never outlive its window.
    public func normalized(now: Date = .now) -> Usage {
        func clean(_ window: UsageWindow?) -> UsageWindow? {
            guard let window else { return nil }
            guard let resets = window.resetsAt, resets <= now else { return window }
            return UsageWindow(percent: 0, resetsAt: nil)
        }
        return Usage(fiveHour: clean(fiveHour), sevenDay: clean(sevenDay), updatedAt: updatedAt, isLive: isLive)
    }
}

public struct AccountState: Equatable, Sendable, Identifiable {
    public let account: Account
    public let email: String?
    public let usage: Usage?
    public var id: Account { account }
    public var isSignedIn: Bool { email != nil }

    public init(account: Account, email: String?, usage: Usage?) {
        self.account = account
        self.email = email
        self.usage = usage
    }
}

public struct Snapshot: Equatable, Sendable {
    public let states: [AccountState]
    public let mode: Mode
    public let next: Account

    public init(states: [AccountState], mode: Mode, next: Account) {
        self.states = states
        self.mode = mode
        self.next = next
    }

    public func state(_ account: Account) -> AccountState {
        states.first { $0.account == account } ?? AccountState(account: account, email: nil, usage: nil)
    }
}

/// File locations shared with the `ccx` script and the status line.
public struct Paths: Sendable {
    public let home: URL

    /// $HOME when set (standard Unix behaviour; lets tests isolate everything), else the user's home.
    public static var defaultHome: URL {
        if let home = ProcessInfo.processInfo.environment["HOME"], home.hasPrefix("/") {
            return URL(filePath: home, directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public init(home: URL = Paths.defaultHome) {
        self.home = home
    }

    public func configJSON(_ account: Account) -> URL {
        switch account {
        case .a: home.appending(path: ".claude.json")
        case .b: home.appending(path: ".claude-b/.claude.json")
        }
    }

    public var stateRoot: URL { home.appending(path: ".claude-accounts") }
    public var pinFile: URL { stateRoot.appending(path: "default") }
    public func usageFile(_ account: Account) -> URL {
        stateRoot.appending(path: "usage/\(account.rawValue).json")
    }
}

/// Reads and writes the same state `ccx` uses. Never touches credentials.
public struct AccountStore: Sendable {
    public let paths: Paths
    public static let limitPercent = 90

    public init(paths: Paths = Paths()) {
        self.paths = paths
    }

    public func email(_ account: Account) -> String? {
        guard let object = readJSON(paths.configJSON(account)),
              let oauth = object["oauthAccount"] as? [String: Any],
              let email = oauth["emailAddress"] as? String, !email.isEmpty
        else { return nil }
        return email
    }

    /// Expired windows count as 0%, matching `ccx`.
    public func usage(_ account: Account, now: Date = .now) -> Usage? {
        let url = paths.usageFile(account)
        guard let object = readJSON(url) else { return nil }
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return Usage(
            fiveHour: Self.window(object["five_hour"], now: now),
            sevenDay: Self.window(object["seven_day"], now: now),
            updatedAt: modified
        )
    }

    /// Writes usage in the status line's format so `ccx` auto-pick and the status line see it too.
    public func record(_ usage: Usage, for account: Account) throws {
        func window(_ w: UsageWindow?) -> Any {
            guard let w, let resets = w.resetsAt else { return NSNull() }
            return ["used_percentage": w.percent, "resets_at": Int(resets.timeIntervalSince1970)]
        }
        let object: [String: Any] = ["five_hour": window(usage.fiveHour), "seven_day": window(usage.sevenDay)]
        let url = paths.usageFile(account)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: url, options: .atomic)
    }

    public func mode() -> Mode {
        guard let raw = try? String(contentsOf: paths.pinFile, encoding: .utf8),
              let account = Account(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return .auto }
        return .pinned(account)
    }

    public func setMode(_ mode: Mode) throws {
        switch mode {
        case .auto:
            if FileManager.default.fileExists(atPath: paths.pinFile.path) {
                try FileManager.default.removeItem(at: paths.pinFile)
            }
        case .pinned(let account):
            try FileManager.default.createDirectory(at: paths.stateRoot, withIntermediateDirectories: true)
            try "\(account.rawValue)\n".write(to: paths.pinFile, atomically: true, encoding: .utf8)
        }
    }

    /// `live` usage, when present, replaces the last-known file value for that account.
    public func snapshot(now: Date = .now, live: [Account: Usage] = [:]) -> Snapshot {
        let states = Account.allCases.map {
            AccountState(account: $0, email: email($0), usage: live[$0] ?? usage($0, now: now))
        }
        let mode = mode()
        let next = Self.pick(
            mode: mode,
            a: states[0].usage,
            b: states[1].usage,
            bSignedIn: states[1].isSignedIn
        )
        return Snapshot(states: states, mode: mode, next: next)
    }

    /// Same rule as `ccx pick`: pin wins; else the account with more headroom.
    public static func pick(mode: Mode, a: Usage?, b: Usage?, bSignedIn: Bool) -> Account {
        if case .pinned(let account) = mode { return account }
        guard bSignedIn else { return .a }
        let (a5, a7) = (a?.fiveHour?.percent ?? 0, a?.sevenDay?.percent ?? 0)
        let (b5, b7) = (b?.fiveHour?.percent ?? 0, b?.sevenDay?.percent ?? 0)
        let aFull = a5 >= limitPercent || a7 >= limitPercent
        let bFull = b5 >= limitPercent || b7 >= limitPercent
        if aFull && !bFull { return .b }
        if bFull && !aFull { return .a }
        if a5 != b5 { return a5 < b5 ? .a : .b }
        return a7 <= b7 ? .a : .b
    }

    static func window(_ value: Any?, now: Date) -> UsageWindow? {
        guard let dict = value as? [String: Any], !dict.isEmpty else { return nil }
        let resets = (dict["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        guard let resets, resets > now else { return UsageWindow(percent: 0, resetsAt: nil) }
        let percent = (dict["used_percentage"] as? NSNumber)?.doubleValue ?? 0
        return UsageWindow(percent: Int(percent.rounded(.down)), resetsAt: resets)
    }

    private func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
