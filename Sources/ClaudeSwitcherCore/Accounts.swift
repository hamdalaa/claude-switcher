import Foundation

/// Up to four Claude Code accounts managed by `ccx`. A is Claude Code's normal ~/.claude; the
/// others live in ~/.claude-<letter> and exist once that folder does (i.e. after signing in).
public enum Account: String, CaseIterable, Sendable, Identifiable, Comparable {
    case a, b, c, d
    public var id: String { rawValue }
    public var label: String { rawValue.uppercased() }

    public static func < (lhs: Account, rhs: Account) -> Bool { lhs.rawValue < rhs.rawValue }
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

    /// Resets this close together are the same window (the API adds sub-second noise; files round).
    public static let sameWindowTolerance: TimeInterval = 600

    /// The more current of two readings of one limit. A later reset is a newer window; within the
    /// same window usage never goes down, so the higher percent is the newer reading. That keeps an
    /// idle session's status line from replaying an old number over a fresh one.
    public static func newer(_ lhs: UsageWindow?, _ rhs: UsageWindow?) -> UsageWindow? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        switch (lhs.resetsAt, rhs.resetsAt) {
        case (nil, nil): return lhs.percent >= rhs.percent ? lhs : rhs
        case (nil, _): return rhs
        case (_, nil): return lhs
        case let (l?, r?):
            if abs(l.timeIntervalSince(r)) < sameWindowTolerance { return lhs.percent >= rhs.percent ? lhs : rhs }
            return l > r ? lhs : rhs
        }
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

    /// Combines two readings of one account window by window (see `UsageWindow.newer`).
    public func merged(with other: Usage?) -> Usage {
        guard let other else { return self }
        let updated = [updatedAt, other.updatedAt].compactMap { $0 }.max()
        return Usage(fiveHour: UsageWindow.newer(fiveHour, other.fiveHour),
                     sevenDay: UsageWindow.newer(sevenDay, other.sevenDay),
                     updatedAt: updated, isLive: isLive)
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

    /// ~/.claude for A; ~/.claude-<letter> for the others (their CLAUDE_CONFIG_DIR).
    public func configDir(_ account: Account) -> URL {
        account == .a ? home.appending(path: ".claude") : home.appending(path: ".claude-\(account.rawValue)")
    }

    /// Claude Code keeps A's settings file in the home folder, the others' inside their config dir.
    public func configJSON(_ account: Account) -> URL {
        account == .a ? home.appending(path: ".claude.json") : configDir(account).appending(path: ".claude.json")
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

    /// A always; B–D once their config folder exists.
    public func configuredAccounts() -> [Account] {
        Account.allCases.filter { $0 == .a || FileManager.default.fileExists(atPath: paths.configDir($0).path) }
    }

    /// The next letter to add, if fewer than four accounts are set up.
    public func nextFreeAccount() -> Account? {
        let configured = Set(configuredAccounts())
        return Account.allCases.first { !configured.contains($0) }
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
        let states = configuredAccounts().map {
            AccountState(account: $0, email: email($0), usage: live[$0] ?? usage($0, now: now))
        }
        let mode = mode()
        let next = Self.pick(
            mode: mode,
            usage: Dictionary(uniqueKeysWithValues: states.compactMap { s in s.usage.map { (s.account, $0) } }),
            signedIn: Set(states.filter(\.isSignedIn).map(\.account)),
            configured: Set(states.map(\.account))
        )
        return Snapshot(states: states, mode: mode, next: next)
    }

    /// Same rule as `ccx pick`: a pin wins (if that account is set up); otherwise, among signed-in
    /// accounts, prefer ones that aren't full, then the lowest 5-hour use, then the lowest weekly
    /// use, then the earliest letter. Falls back to A.
    public static func pick(mode: Mode, usage: [Account: Usage], signedIn: Set<Account>,
                            configured: Set<Account> = Set(Account.allCases)) -> Account {
        if case .pinned(let account) = mode, configured.contains(account) || account == .a { return account }
        let candidates = signedIn.intersection(configured.union([.a])).sorted()
        guard !candidates.isEmpty else { return .a }
        func load(_ account: Account) -> (five: Int, seven: Int, full: Bool) {
            let five = usage[account]?.fiveHour?.percent ?? 0
            let seven = usage[account]?.sevenDay?.percent ?? 0
            return (five, seven, five >= limitPercent || seven >= limitPercent)
        }
        let open = candidates.filter { !load($0).full }
        let pool = open.isEmpty ? candidates : open
        return pool.min { lhs, rhs in
            let (l, r) = (load(lhs), load(rhs))
            if l.five != r.five { return l.five < r.five }
            if l.seven != r.seven { return l.seven < r.seven }
            return lhs < rhs
        } ?? .a
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
