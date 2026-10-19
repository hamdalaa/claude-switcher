import Foundation
import Testing
@testable import ClaudeSwitcherCore

private func tempHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "cs-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

private func usage(_ five: Int, _ seven: Int) -> Usage {
    let later = Date.now.addingTimeInterval(3600)
    return Usage(
        fiveHour: UsageWindow(percent: five, resetsAt: later),
        sevenDay: UsageWindow(percent: seven, resetsAt: later),
        updatedAt: nil
    )
}

@Test func readsEmailsFromEachConfig() throws {
    let home = try tempHome()
    let store = AccountStore(paths: Paths(home: home))
    try write(#"{"oauthAccount":{"emailAddress":"a@x.com"}}"#, to: store.paths.configJSON(.a))
    try write(#"{"mcpServers":{}}"#, to: store.paths.configJSON(.b))

    #expect(store.email(.a) == "a@x.com")
    #expect(store.email(.b) == nil)
}

@Test func expiredWindowCountsAsZero() throws {
    let home = try tempHome()
    let store = AccountStore(paths: Paths(home: home))
    try write(
        #"{"five_hour":{"used_percentage":88.7,"resets_at":9999999999},"seven_day":{"used_percentage":70,"resets_at":1}}"#,
        to: store.paths.usageFile(.a)
    )

    let read = try #require(store.usage(.a))
    #expect(read.fiveHour?.percent == 88)
    #expect(read.sevenDay?.percent == 0)
    #expect(read.updatedAt != nil)
    #expect(store.usage(.b) == nil)
}

@Test func modeRoundTripsThroughPinFile() throws {
    let store = AccountStore(paths: Paths(home: try tempHome()))
    #expect(store.mode() == .auto)

    try store.setMode(.pinned(.b))
    #expect(store.mode() == .pinned(.b))
    #expect(try String(contentsOf: store.paths.pinFile, encoding: .utf8) == "b\n")

    try store.setMode(.auto)
    #expect(store.mode() == .auto)
}

private func pick(_ mode: Mode, _ usage: [Account: Usage], signedIn: Set<Account>,
                  configured: Set<Account> = Set(Account.allCases)) -> Account {
    AccountStore.pick(mode: mode, usage: usage, signedIn: signedIn, configured: configured)
}

@Test func pickHonoursPin() {
    #expect(pick(.pinned(.b), [.a: usage(0, 0), .b: usage(99, 99)], signedIn: [.a, .b]) == .b)
}

@Test func pinToUnconfiguredAccountFallsBackToAuto() {
    #expect(pick(.pinned(.c), [.a: usage(10, 10), .b: usage(5, 5)], signedIn: [.a, .b], configured: [.a, .b]) == .b)
}

@Test func pickStaysOnAWhenBNotSignedIn() {
    #expect(pick(.auto, [.a: usage(95, 95)], signedIn: [.a]) == .a)
}

@Test func pickAvoidsFullAccount() {
    #expect(pick(.auto, [.a: usage(10, 92), .b: usage(60, 10)], signedIn: [.a, .b]) == .b)
    #expect(pick(.auto, [.a: usage(60, 10), .b: usage(90, 10)], signedIn: [.a, .b]) == .a)
}

@Test func pickPrefersLowerFiveHourThenWeekly() {
    #expect(pick(.auto, [.a: usage(40, 10), .b: usage(20, 80)], signedIn: [.a, .b]) == .b)
    #expect(pick(.auto, [.a: usage(20, 50), .b: usage(20, 40)], signedIn: [.a, .b]) == .b)
    #expect(pick(.auto, [.a: usage(20, 40), .b: usage(20, 40)], signedIn: [.a, .b]) == .a)
}

@Test func pickAcrossFourAccounts() {
    let all: [Account: Usage] = [.a: usage(95, 10), .b: usage(30, 99), .c: usage(50, 20), .d: usage(40, 60)]
    #expect(pick(.auto, all, signedIn: [.a, .b, .c, .d]) == .d)          // a, b full → lowest 5h of c, d
    #expect(pick(.auto, all, signedIn: [.a, .b, .c]) == .c)
    #expect(pick(.auto, all, signedIn: [.a, .b]) == .b)                   // all full → lowest 5h
    #expect(pick(.auto, [:], signedIn: []) == .a)
}

@Test func configuredAccountsFollowFolders() throws {
    let home = try tempHome()
    let store = AccountStore(paths: Paths(home: home))
    #expect(store.configuredAccounts() == [.a])
    #expect(store.nextFreeAccount() == .b)
    try FileManager.default.createDirectory(at: home.appending(path: ".claude-c"), withIntermediateDirectories: true)
    #expect(store.configuredAccounts() == [.a, .c])
    #expect(store.nextFreeAccount() == .b)
    #expect(store.paths.configJSON(.c).path == home.appending(path: ".claude-c/.claude.json").path)
    #expect(store.snapshot().states.map(\.account) == [.a, .c])
}
