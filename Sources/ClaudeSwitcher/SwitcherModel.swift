import ClaudeSwitcherCore
import Observation
import ServiceManagement
import SwiftUI

@MainActor @Observable
final class SwitcherModel {
    private let store = AccountStore()
    private(set) var snapshot: Snapshot
    private(set) var message: String?
    private(set) var isSyncing = false
    private(set) var isRefreshing = false
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var recentProjects: [String] = []
    private(set) var plans: [Account: String] = [:]
    private(set) var avatars: [String: NSImage] = [:]
    private(set) var codex: CodexUsage?
    private(set) var codexError: String?
    private(set) var codexAvailable = false
    /// Why the last live read failed, per account. Cleared on success.
    private(set) var liveErrors: [Account: String] = [:]

    // Settings
    private(set) var installedTerminals: Set<TerminalApp> = []
    private(set) var terminalChoice: TerminalApp?          // nil = automatic
    private(set) var hookInstalled = false
    private(set) var cliState: Setup.CLIState = .missing
    private(set) var hookBannerDismissed: Bool
    var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notifications) }
    }

    /// Screenshot mode: fixed sample data, no reads or writes.
    let isDemo: Bool

    private var live: [Account: Usage] = [:]
    /// Which login the held live values belong to; a different login clears them.
    private var liveEmail: [Account: String] = [:]
    private let reader = LiveUsageReader()
    private let notifier = Notifier()
    private let avatarStore = AvatarStore()
    private var timer: Timer?
    private var poller: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    /// The usage endpoint rate-limits when polled faster than this.
    static let pollInterval: Duration = .seconds(180)
    private var history: URL { store.paths.home.appending(path: ".claude/history.jsonl") }

    private enum Keys {
        static let notifications = "notificationsEnabled"
        static let terminal = "terminal"
        static let hookBannerDismissed = "hookBannerDismissed"
    }

    /// The chosen terminal if it's still installed, else the automatic pick.
    var terminal: TerminalApp {
        if let terminalChoice, installedTerminals.contains(terminalChoice) { return terminalChoice }
        return TerminalApp.preferred(installed: installedTerminals)
    }
    var shellSupportsHook: Bool { Setup.hookFile != nil }
    var showsHookBanner: Bool {
        !isDemo && !hookInstalled && !hookBannerDismissed && shellSupportsHook && snapshot.state(.b).isSignedIn
    }

    init(demo: Bool = false) {
        isDemo = demo
        let defaults = UserDefaults.standard
        notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
        hookBannerDismissed = defaults.bool(forKey: Keys.hookBannerDismissed)
        terminalChoice = defaults.string(forKey: Keys.terminal).flatMap(TerminalApp.init(rawValue:))
        if demo {
            snapshot = DemoData.snapshot
            plans = DemoData.plans
            codex = DemoData.codex
            codexAvailable = true
            installedTerminals = [.terminal]
            recentProjects = ["~/code/web-app", "~/code/api"]
            return
        }
        snapshot = store.snapshot()
        avatars = Self.loadAvatars(avatarStore)
        installedTerminals = System.installedTerminals()
        Setup.updateCLIIfManaged()
        refreshSetup()
        Task {
            Setup.shellInfo = await System.shellInfo()
            refreshSetup()
        }
        Launcher.removeStaleScripts()
        if notificationsEnabled { notifier.requestPermission() }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshLive()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func refresh() {
        guard !isDemo else { return }
        snapshot = store.snapshot(live: freshest())
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func refreshSetup() {
        hookInstalled = Setup.hookInstalled()
        cliState = Setup.cliState()
    }

    /// Called when the panel opens: cheap local state now, live usage in the background.
    func panelOpened() {
        guard !isDemo else { return }
        recentProjects = RecentProjects.load(history: history)
        installedTerminals = System.installedTerminals()
        refreshSetup()
        refresh()
        Task { await refreshLive() }
    }

    // MARK: Live usage

    /// Reads both accounts (and Codex) live; the reader throttles repeat calls itself.
    /// Overlapping callers share the in-flight read instead of skipping it.
    func refreshLive() async {
        guard !isDemo else { return }
        if let inFlight { return await inFlight.value }
        let task = Task { await readAll() }
        inFlight = task
        isRefreshing = true
        await task.value
        inFlight = nil
        isRefreshing = false
    }

    private func readAll() async {
        async let codexRead: Void = readCodex()
        for account in Account.allCases {
            guard let email = store.email(account) else { forget(account); continue }
            if liveEmail[account] != email { forget(account); liveEmail[account] = email }
            plans[account] = await reader.plan(account)
            switch await reader.read(account) {
            case .success(let usage):
                // Diff against the previous live reading (not the merged snapshot, which a
                // running session's status line may already have moved past the threshold).
                let previous = live[account]?.normalized()
                live[account] = usage
                liveErrors[account] = nil
                try? store.record(usage, for: account)
                if notificationsEnabled, let alert = UsageAlert.between(old: previous, new: usage, account: account) {
                    refresh()
                    notifier.post(alert, snapshot: snapshot)
                }
            case .failure(let failure):
                liveErrors[account] = failure.message
            }
        }
        await codexRead
        refresh()
    }

    private func readCodex() async {
        codexAvailable = await CodexReader.isInstalled()
        guard codexAvailable else { codex = nil; return }
        do {
            codex = try await CodexReader.read()
            codexError = nil
        } catch {
            codexError = error.localizedDescription
        }
    }

    /// Signed out, or a different login in this slot: drop everything held for the old one.
    private func forget(_ account: Account) {
        live[account] = nil
        liveErrors[account] = nil
        plans[account] = nil
        liveEmail[account] = nil
    }

    /// Live reads win unless a running session has written newer numbers to the usage file since.
    /// Windows that have reset since the read count as 0%, so a failing refresh can't hold a
    /// stale "95%" past its reset (and mislead Auto).
    private func freshest() -> [Account: Usage] {
        let now = Date.now
        return live.filter { account, usage in
            guard let fileDate = store.usage(account)?.updatedAt, let liveDate = usage.updatedAt else { return true }
            return fileDate.timeIntervalSince(liveDate) < 5
        }.mapValues { $0.normalized(now: now) }
    }

    // MARK: Switching and launching

    func setMode(_ mode: Mode) {
        guard !isDemo else { return }
        if case .pinned(let account) = mode, !snapshot.state(account).isSignedIn {
            message = "Sign in to account \(account.label) before switching to it"
            return
        }
        do {
            try store.setMode(mode)
            message = nil
        } catch {
            message = "Couldn't save the switch: \(error.localizedDescription)"
        }
        refresh()
    }

    func open(_ account: Account, in directory: String? = nil) {
        perform { try Launcher.session(account, in: Self.expand(directory), terminal: terminal) }
    }

    func signIn(_ account: Account) {
        perform { try Launcher.signIn(account, terminal: terminal) }
    }

    func openWeb(_ account: Account) {
        perform { try Launcher.web(account) }
    }

    func openCodex(in directory: String? = nil) {
        perform { try Launcher.codex(in: Self.expand(directory), terminal: terminal) }
    }

    func openCodexWeb() {
        NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex")!)
    }

    private static func expand(_ directory: String?) -> String {
        guard let directory else { return System.home.path }
        return (directory as NSString).expandingTildeInPath
    }

    func sync() {
        isSyncing = true
        Task {
            do {
                try await Launcher.sync()
                message = "Account B re-synced with A's settings"
            } catch {
                message = "Sync failed: \(error.localizedDescription)"
            }
            isSyncing = false
            refresh()
        }
    }

    // MARK: Avatars

    private static func loadAvatars(_ store: AvatarStore) -> [String: NSImage] {
        Dictionary(uniqueKeysWithValues: ["a", "b", "codex"].compactMap { key in store.load(key).map { (key, $0) } })
    }

    func chooseAvatar(_ key: String) {
        guard !isDemo, let url = AvatarStore.pickImage() else { return }
        setAvatar(key, from: url)
    }

    func setAvatar(_ key: String, from url: URL) {
        guard !isDemo else { return }
        perform { try avatarStore.save(key, from: url) }
        avatars = Self.loadAvatars(avatarStore)
    }

    func removeAvatar(_ key: String) {
        guard !isDemo else { return }
        perform { try avatarStore.remove(key) }
        avatars = Self.loadAvatars(avatarStore)
    }

    // MARK: Settings

    func setTerminal(_ app: TerminalApp?) {
        terminalChoice = app
        UserDefaults.standard.set(app?.rawValue, forKey: Keys.terminal)
    }

    func setHook(_ enabled: Bool) {
        guard !isDemo else { return }
        perform { try Setup.setHook(enabled) }
        refreshSetup()
        if message == nil {
            message = enabled
                ? "Plain `claude` now follows the switch — open a new terminal tab"
                : "Plain `claude` is back to normal (new tabs)"
        }
    }

    func setCLIInstalled(_ installed: Bool) {
        guard !isDemo else { return }
        perform { installed ? try Setup.installCLI() : try Setup.removeCLI() }
        refreshSetup()
    }

    func dismissHookBanner() {
        hookBannerDismissed = true
        UserDefaults.standard.set(true, forKey: Keys.hookBannerDismissed)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isDemo else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            message = nil
        } catch {
            message = "Open at login: \(error.localizedDescription)"
        }
        refresh()
    }

    func setNotifications(_ enabled: Bool) {
        notificationsEnabled = enabled
        if enabled { notifier.requestPermission() }
    }

    func dismissMessage() { message = nil }

    private func perform(_ action: () throws -> Void) {
        guard !isDemo else { return }
        do {
            try action()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Fixed sample data for screenshots (`--demo`).
enum DemoData {
    static let snapshot: Snapshot = {
        let now = Date.now
        func usage(_ five: Int, _ fiveIn: Double, _ seven: Int, _ sevenIn: Double) -> Usage {
            Usage(fiveHour: UsageWindow(percent: five, resetsAt: now.addingTimeInterval(fiveIn * 60)),
                  sevenDay: UsageWindow(percent: seven, resetsAt: now.addingTimeInterval(sevenIn * 3600)),
                  updatedAt: now, isLive: true)
        }
        return Snapshot(states: [
            AccountState(account: .a, email: "work@example.com", usage: usage(92, 96, 58, 92)),
            AccountState(account: .b, email: "personal@example.com", usage: usage(21, 66, 34, 107)),
        ], mode: .auto, next: .b)
    }()
    static let plans: [Account: String] = [.a: "Max 5x", .b: "Max 20x"]
    static let codex = CodexUsage(
        email: "dev@example.com", plan: "Plus",
        windows: [.init(title: "Weekly", window: UsageWindow(percent: 27, resetsAt: .now.addingTimeInterval(5 * 86400)))],
        limitReached: false, updatedAt: .now)
}
