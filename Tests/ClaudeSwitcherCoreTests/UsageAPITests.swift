import Foundation
import Testing
@testable import ClaudeSwitcherCore

@Test func keychainServiceMatchesClaudeCodeNaming() {
    let paths = Paths(home: URL(filePath: "/Users/alice"))
    #expect(UsageAPI.keychainService(.a, paths: paths) == "Claude Code-credentials")
    // Claude Code names the item "Claude Code-credentials-" + sha256(config dir).prefix(8 hex);
    // expected value from: printf %s /Users/alice/.claude-b | shasum -a 256
    #expect(UsageAPI.keychainService(.b, paths: paths) == "Claude Code-credentials-4e8feb03")
}

@Test func parsesLimitsList() throws {
    let json = #"""
    {"five_hour":{"utilization":99,"resets_at":"2026-10-19T03:20:00.839098+00:00"},
     "limits":[
      {"kind":"session","percent":32,"resets_at":"2026-10-19T03:20:00.839098+00:00"},
      {"kind":"weekly_all","percent":54,"resets_at":"2026-10-22T22:00:00+00:00"},
      {"kind":"weekly_scoped","percent":0,"resets_at":"2026-10-22T22:00:00+00:00"}]}
    """#
    let usage = try UsageAPI.parse(Data(json.utf8))
    #expect(usage.fiveHour?.percent == 32)
    #expect(usage.sevenDay?.percent == 54)
    #expect(usage.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_792_380_000.839098))
    #expect(usage.sevenDay?.resetsAt == Date(timeIntervalSince1970: 1_792_706_400))
    #expect(usage.isLive)
}

@Test func fallsBackToLegacyWindows() throws {
    let json = #"{"five_hour":{"utilization":8.7,"resets_at":"2026-10-19T02:50:00+00:00"},"seven_day":{"utilization":59.0,"resets_at":"2026-10-23T13:00:00+00:00"}}"#
    let usage = try UsageAPI.parse(Data(json.utf8))
    #expect(usage.fiveHour?.percent == 8)
    #expect(usage.sevenDay?.percent == 59)
}

@Test func rejectsUnexpectedBody() {
    #expect(throws: (any Error).self) { try UsageAPI.parse(Data(#"{"error":"nope"}"#.utf8)) }
}

@Test func recordedUsageReadsBackForCcx() throws {
    let home = FileManager.default.temporaryDirectory.appending(path: "cs-\(UUID().uuidString)")
    let store = AccountStore(paths: Paths(home: home))
    let later = Date(timeIntervalSince1970: 9_999_999_999)
    try store.record(Usage(fiveHour: UsageWindow(percent: 41, resetsAt: later),
                           sevenDay: UsageWindow(percent: 77, resetsAt: later), updatedAt: .now), for: .b)
    let read = try #require(store.usage(.b))
    #expect(read.fiveHour?.percent == 41)
    #expect(read.sevenDay?.percent == 77)
}

@Test func credentialsExpiry() throws {
    let soon = Int((Date.now.timeIntervalSince1970 + 30) * 1000)
    let creds = try #require(Credentials(json: Data(#"{"claudeAiOauth":{"accessToken":"t","expiresAt":\#(soon)}}"#.utf8)))
    #expect(creds.isExpired())
    #expect(!creds.description.contains("t)"))
}

@Test func planLabels() throws {
    #expect(Plan.label(subscription: "max", tier: "default_claude_max_20x") == "Max 20x")
    #expect(Plan.label(subscription: "max", tier: "default_claude_max_5x") == "Max 5x")
    #expect(Plan.label(subscription: "pro", tier: "default_claude_ai") == "Pro")
    #expect(Plan.label(subscription: nil, tier: "x") == nil)
    let creds = try #require(Credentials(json: Data(#"{"claudeAiOauth":{"accessToken":"t","subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}"#.utf8)))
    #expect(creds.planLabel == "Max 20x")
}
