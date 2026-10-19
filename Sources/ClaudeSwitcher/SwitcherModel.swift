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
    private(set) var recentSessions: [RecentSession] = []
    /// Optional names ("Work", "Personal") shown instead of the email.
    private(set) var names: [Account: String] = [:]
    private(set) var update: ReleaseCheck.Latest?
    private(set) var installedWithHomebrew = false
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
    var checksForUpdates: Bool {
        didSet { UserDefaults.standard.set(checksForUpdates, forKey: Keys.updates) }
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
        static let updates = "checksForUpdates"
        static let welcomeShown = "welcomeShown"
        static func name(_ account: Account) -> String { "accountName.\(account.rawValue)" }
    }

    var canAddAccount: Bool { !isDemo && store.nextFreeAccount() != nil }
    func displayName(_ account: Account) -> String {
        names[account] ?? snapshot.state(account).email ?? "Account \(account.label)"
    }

    /// The chosen terminal if it's still installed, else the automatic pick.
    var terminal: TerminalApp {
        if let terminalChoice, installedTerminals.contains(terminalChoice) { return terminalChoice }
        return TerminalApp.preferred(installed: installedTerminals)
    }
    var shellSupportsHook: Bool { Setup.hookFile != nil }
    var showsHookBanner: Bool {
        !isDemo && !hookInstalled && !hookBannerDismissed && shellSupportsHook && snapshot.states.contains { $0.account != .a && $0.isSignedIn }
    }

    init(demo: Bool = false) {
        isDemo = demo
        let defaults = UserDefaults.standard
        notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
        checksForUpdates = defaults.object(forKey: Keys.updates) as? Bool ?? true
        names = Dictionary(uniqueKeysWithValues: Account.allCases.compactMap { account in
            defaults.string(forKey: Keys.name(account)).flatMap { $0.isEmpty ? nil : (account, $0) }
        })
        hookBannerDismissed = defaults.bool(forKey: Keys.hookBannerDismissed)
        terminalChoice = defaults.string(forKey: Keys.terminal).flatMap(TerminalApp.init(rawValue:))
        if demo {
            snapshot = DemoData.snapshot(mode: DemoData.requestedMode)
            plans = DemoData.plans
            codex = DemoData.codex
            codexAvailable = true
            installedTerminals = [.terminal]
            recentProjects = ["~/code/web-app", "~/code/api"]
            names = DemoData.names
            recentSessions = DemoData.sessions
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
        // Existing users (another account already set up) skip the welcome on upgrade.
        if store.configuredAccounts().count > 1 { defaults.set(true, forKey: Keys.welcomeShown) }
        if !defaults.bool(forKey: Keys.welcomeShown) {
            defaults.set(true, forKey: Keys.welcomeShown)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                if let self { WelcomeWindow.show(model: self) }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshLive()
                await self?.checkForUpdates()
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
        let projects = store.paths.home.appending(path: ".claude/projects")
        Task.detached(priority: .utility) {
            let sessions = RecentSessions.load(projects: projects)
            await MainActor.run { [weak self] in self?.recentSessions = sessions }
        }
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
        let configured = Set(store.configuredAccounts())
        for account in Account.allCases {
            // Re-check per account: one may have been removed while this read was in flight.
            guard configured.contains(account), store.configuredAccounts().contains(account),
                  let email = store.email(account) else { forget(account); continue }
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
    func forget(_ account: Account) {
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

    /// Resumes a conversation on `account` — e.g. carry on with B after A hit its limit.
    func continueSession(_ session: RecentSession, on account: Account) {
        perform { try Launcher.session(account, in: session.directory, terminal: terminal, arguments: ["--resume", session.id]) }
    }

    func addAccount() {
        // An earlier sign-in that was never finished leaves a signed-out row; finish that first.
        let unfinished = snapshot.states.first { $0.account != .a && !$0.isSignedIn }?.account
        guard let account = unfinished ?? store.nextFreeAccount() else { return }
        signIn(account)
        message = "Finish signing in account \(account.label) in the browser — it appears here when done"
    }

    func removeAccount(_ account: Account) {
        guard !isDemo, account != .a else { return }
        let alert = NSAlert()
        alert.messageText = "Remove account \(account.label)?"
        alert.informativeText = "Signs \(displayName(account)) out and moves ~/.claude-\(account.rawValue) to the Trash. Settings, skills and conversations shared from account A aren't affected."
        alert.addButton(withTitle: "Remove Account \(account.label)")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            if let inFlight { await inFlight.value }   // don't let a running refresh recreate it
            do {
                try await Launcher.removeAccount(account)
                forget(account)
                setName(nil, for: account)
                try? avatarStore.remove(account.rawValue)
                avatars = Self.loadAvatars(avatarStore)
                message = "Account \(account.label) removed"
            } catch {
                message = "Couldn't remove account \(account.label): \(error.localizedDescription)"
            }
            refresh()
        }
    }

    func rename(_ account: Account) {
        guard !isDemo else { return }
        let alert = NSAlert()
        alert.messageText = "Name account \(account.label)"
        alert.informativeText = "Shown instead of the email, e.g. Work or Personal. Leave empty to show the email."
        let field = NSTextField(string: names[account] ?? "")
        field.placeholderString = snapshot.state(account).email ?? "Account \(account.label)"
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setName(field.stringValue, for: account)
    }

    private func setName(_ name: String?, for account: Account) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        names[account] = trimmed.isEmpty ? nil : String(trimmed.prefix(40))
        UserDefaults.standard.set(names[account], forKey: Keys.name(account))
    }

    // MARK: Updates

    private static let releasesAPI = URL(string: "https://api.github.com/repos/hamdalaa/claude-switcher/releases/latest")!
    private static let lastUpdateCheckKey = "lastUpdateCheck"
    private static let updateInterval: TimeInterval = 86_400
    private static let latestVersionKey = "latestReleaseVersion"
    private static let latestURLKey = "latestReleaseURL"

    /// At most once a day (or when asked): one request to GitHub's public releases API.
    /// `announce` reports the result even when there's nothing new (for "Check Now").
    func checkForUpdates(force: Bool = false, announce: Bool = false) async {
        guard !isDemo, checksForUpdates || force else { return }
        let defaults = UserDefaults.standard
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        if !force, let last = defaults.object(forKey: Self.lastUpdateCheckKey) as? Date,
           Date.now.timeIntervalSince(last) < Self.updateInterval {
            // Checked recently: reuse what we found then, without another request.
            if update == nil, let version = defaults.string(forKey: Self.latestVersionKey),
               let url = defaults.string(forKey: Self.latestURLKey).flatMap(URL.init(string:)),
               ReleaseCheck.isNewer(version, than: current) {
                update = ReleaseCheck.Latest(version: version, url: url)
                installedWithHomebrew = await Self.isHomebrewInstall()
            }
            return
        }
        defaults.set(Date.now, forKey: Self.lastUpdateCheckKey)
        var request = URLRequest(url: Self.releasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeSwitcher", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = ReleaseCheck.parse(data) else {
            if announce { message = "Couldn't check for updates right now" }
            return
        }
        defaults.set(latest.version, forKey: Self.latestVersionKey)
        defaults.set(latest.url.absoluteString, forKey: Self.latestURLKey)
        update = ReleaseCheck.isNewer(latest.version, than: current) ? latest : nil
        installedWithHomebrew = await Self.isHomebrewInstall()
        if announce && update == nil { message = "Claude Switcher is up to date (\(current))" }
    }

    func installUpdate() {
        guard let update else { return }
        if installedWithHomebrew {
            perform { try Launcher.brewUpgrade(terminal: terminal) }
        } else {
            NSWorkspace.shared.open(update.url)
        }
    }

    func setChecksForUpdates(_ enabled: Bool) {
        checksForUpdates = enabled
        if enabled { Task { await checkForUpdates(force: true) } } else { update = nil }   // quiet
    }

    private static func isHomebrewInstall() async -> Bool {
        guard let brew = await System.which("brew") else { return false }
        let prefix = URL(filePath: brew).deletingLastPathComponent().deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: prefix.appending(path: "Caskroom/claude-switcher").path)
    }

    func showWelcome() { WelcomeWindow.show(model: self) }

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
                message = "Shared settings re-synced into every account"
            } catch {
                message = "Sync failed: \(error.localizedDescription)"
            }
            isSyncing = false
            refresh()
        }
    }

    // MARK: Avatars

    private static func loadAvatars(_ store: AvatarStore) -> [String: NSImage] {
        let keys = Account.allCases.map(\.rawValue) + ["codex"]
        return Dictionary(uniqueKeysWithValues: keys.compactMap { key in store.load(key).map { (key, $0) } })
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
    /// `--demo-mode auto|a|b` (default auto), for README frames.
    static var requestedMode: Mode {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--demo-mode"), i + 1 < args.count,
              let account = Account(rawValue: args[i + 1]) else { return .auto }
        return .pinned(account)
    }

    static func snapshot(mode: Mode) -> Snapshot {
        let now = Date.now
        func usage(_ five: Int, _ fiveIn: Double, _ seven: Int, _ sevenIn: Double) -> Usage {
            Usage(fiveHour: UsageWindow(percent: five, resetsAt: now.addingTimeInterval(fiveIn * 60)),
                  sevenDay: UsageWindow(percent: seven, resetsAt: now.addingTimeInterval(sevenIn * 3600)),
                  updatedAt: now, isLive: true)
        }
        let states = [
            AccountState(account: .a, email: "work@example.com", usage: usage(92, 96, 58, 92)),
            AccountState(account: .b, email: "personal@example.com", usage: usage(21, 66, 34, 107)),
        ]
        let next: Account = if case .pinned(let account) = mode { account } else { .b }
        return Snapshot(states: states, mode: mode, next: next)
    }

    static let plans: [Account: String] = [.a: "Max 5x", .b: "Max 20x"]
    static let names: [Account: String] = [.a: "Work", .b: "Personal"]
    static let sessions = [
        RecentSession(id: "demo-1", directory: "/Users/demo/code/web-app", title: "Fix the flaky login test", modified: .now),
        RecentSession(id: "demo-2", directory: "/Users/demo/code/api", title: "Add rate limiting to /v1/search", modified: .now),
    ]
    static let codex = CodexUsage(
        email: "dev@example.com", plan: "Plus",
        windows: [.init(title: "Weekly", window: UsageWindow(percent: 27, resetsAt: .now.addingTimeInterval(5 * 86400)))],
        limitReached: false, updatedAt: .now)
}
