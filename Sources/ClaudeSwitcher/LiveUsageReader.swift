import ClaudeSwitcherCore
import Foundation
import os

/// Reads each account's exact usage from Anthropic, using the access token Claude Code already
/// stored. Read-only: it never refreshes or writes a token (that would rotate it and sign
/// Claude Code out). If a token has expired it asks Claude Code itself to renew it.
actor LiveUsageReader {
    private static let log = Logger(subsystem: System.subsystem, category: "usage")
    /// Forced reads (opening the panel) within this window reuse the last answer.
    static let minimumInterval: TimeInterval = 30
    static let maximumBackoff: TimeInterval = 900
    static let renewInterval: TimeInterval = 600

    enum Failure: Error, Equatable {
        case notSignedIn, expired, rejected
        case rateLimited(until: Date)
        case unavailable(String)

        var message: String {
            switch self {
            case .notSignedIn: "Signed out of Claude Code"
            case .expired: "Sign-in expired — open a session to renew"
            case .rejected: "Sign-in rejected — open a session to renew"
            case .rateLimited(let until): "Rate limited until \(until.formatted(date: .omitted, time: .shortened))"
            case .unavailable(let reason): reason
            }
        }
    }

    private struct State {
        var last: (at: Date, usage: Usage)?
        var blockedUntil: Date?
        var backoff: TimeInterval = 60
        var lastRenew: Date?
    }

    private let paths: Paths
    private var states: [Account: State] = [:]
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()
    /// The usage response is ~2 KB; anything far larger is not what we asked for.
    static let maximumResponseBytes = 256_000

    init(paths: Paths = Paths()) {
        self.paths = paths
    }

    func read(_ account: Account, now: Date = .now) async -> Result<Usage, Failure> {
        var state = states[account] ?? State()
        defer { states[account] = state }

        if let until = state.blockedUntil, now < until { return .failure(.rateLimited(until: until)) }
        if let last = state.last, now.timeIntervalSince(last.at) < Self.minimumInterval {
            return .success(last.usage)
        }
        guard var credentials = await loadCredentials(account) else { return .failure(.notSignedIn) }
        if credentials.isExpired(at: now) {
            guard let renewed = await renew(account, state: &state, now: now) else { return .failure(.expired) }
            credentials = renewed
        }

        var request = URLRequest(url: UsageAPI.endpoint)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(UsageAPI.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeSwitcher/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch {
            return .failure(.unavailable("Offline"))
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200:
            state.blockedUntil = nil
            state.backoff = 60
        case 401, 403:
            Self.log.notice("usage \(account.rawValue, privacy: .public): HTTP \(code, privacy: .public)")
            return .failure(.rejected)
        case 429:
            let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
            let wait = min(max(header.flatMap(TimeInterval.init) ?? state.backoff, 30), Self.maximumBackoff)
            state.blockedUntil = now.addingTimeInterval(wait)
            state.backoff = min(state.backoff * 2, Self.maximumBackoff)
            return .failure(.rateLimited(until: now.addingTimeInterval(wait)))
        default:
            return .failure(.unavailable("HTTP \(code)"))
        }
        guard data.count <= Self.maximumResponseBytes, let usage = try? UsageAPI.parse(data, now: now) else {
            return .failure(.unavailable("Unexpected response"))
        }
        state.last = (now, usage)
        Self.log.info("usage \(account.rawValue, privacy: .public): 5h \(usage.fiveHour?.percent ?? -1) 7d \(usage.sevenDay?.percent ?? -1)")
        return .success(usage)
    }

    /// The account's plan as Claude Code recorded it at sign-in.
    func plan(_ account: Account) async -> String? {
        await loadCredentials(account)?.planLabel
    }

    /// `security` is on the item's access list (Claude Code writes it with that tool), so no
    /// prompt. The token arrives over a pipe — never in process arguments or on disk.
    private func loadCredentials(_ account: Account) async -> Credentials? {
        let service = UsageAPI.keychainService(account, paths: paths)
        // Match Claude Code's item exactly (service + this user's account name); older Claude
        // Code versions may have used another account name, so fall back to service only.
        for args in [["find-generic-password", "-s", service, "-a", NSUserName(), "-w"],
                     ["find-generic-password", "-s", service, "-w"]] {
            let result = await System.run("/usr/bin/security", args, environment: System.cleanEnvironment(), timeout: 10)
            if result.status == 0, let credentials = Credentials(json: Data(result.output.utf8)) { return credentials }
        }
        return nil
    }

    /// `claude auth status` makes Claude Code refresh its own token if needed. Throttled.
    private func renew(_ account: Account, state: inout State, now: Date) async -> Credentials? {
        if let last = state.lastRenew, now.timeIntervalSince(last) < Self.renewInterval { return nil }
        state.lastRenew = now
        var extra: [String: String] = [:]
        if account == .b { extra["CLAUDE_CONFIG_DIR"] = paths.configJSON(.b).deletingLastPathComponent().path }
        var env = await System.toolEnvironment(extra: extra)
        if account == .a { env["CLAUDE_CONFIG_DIR"] = nil }
        _ = await System.run("/usr/bin/env", ["claude", "auth", "status"], environment: env)
        guard let fresh = await loadCredentials(account), !fresh.isExpired() else { return nil }
        Self.log.info("usage \(account.rawValue, privacy: .public): Claude Code renewed its sign-in")
        return fresh
    }
}

/// The request carries a bearer token; following a redirect could hand it to another host.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
