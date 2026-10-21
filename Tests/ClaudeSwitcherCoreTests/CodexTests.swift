import Foundation
import Testing
@testable import ClaudeSwitcherCore

@Test func parsesCodexLimitsAndAccount() throws {
    let limits = #"""
    {"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300,"resetsAt":1}},
     "rateLimitsByLimitId":{"codex":{"limitId":"codex",
       "primary":{"usedPercent":19.6,"windowDurationMins":10080,"resetsAt":1792901444},
       "secondary":{"usedPercent":40,"windowDurationMins":300,"resetsAt":1792390000},
       "spendControlReached":false,"planType":"prolite","rateLimitReachedType":null}}}
    """#
    let account = #"{"account":{"type":"chatgpt","email":"y@x.com","planType":"prolite"}}"#
    let usage = try CodexAPI.parse(limits: Data(limits.utf8), account: Data(account.utf8))
    #expect(usage.email == "y@x.com")
    #expect(usage.plan == "Pro Lite")
    #expect(usage.windows.map(\.title) == ["Weekly", "5-hour"])
    #expect(usage.windows[0].window.percent == 19)
    #expect(usage.windows[0].window.resetsAt == Date(timeIntervalSince1970: 1_792_901_444))
    #expect(usage.percentLeft == 60)
    #expect(!usage.limitReached)
}

@Test func codexLimitReachedAndFallbackBucket() throws {
    let limits = #"{"rateLimits":{"primary":{"usedPercent":100,"windowDurationMins":10080},"rateLimitReachedType":"primary","planType":"plus"}}"#
    let usage = try CodexAPI.parse(limits: Data(limits.utf8), account: nil)
    #expect(usage.limitReached)
    #expect(usage.plan == "Plus")
    #expect(usage.percentLeft == 0)
    #expect(usage.email == nil)
}

@Test func codexRejectsGarbage() {
    #expect(throws: (any Error).self) { try CodexAPI.parse(limits: Data("[]".utf8), account: nil) }
}

@Test func codexErrorsAreReadable() {
    let revoked = #"failed to fetch codex rate limits: GET https://chatgpt.com/backend-api/wham/usage failed: 401 Unauthorized; content-type=text/plain; body={"error":{"code":"token_revoked"}}"#
    #expect(CodexAPI.friendlyError(revoked) == "Signed out — run codex login")
    #expect(CodexAPI.friendlyError(nil) == "Sign in to Codex (codex login)")
    #expect(CodexAPI.friendlyError("failed to fetch codex rate limits: 500 Internal; body={}") == "Codex: failed to fetch codex rate limits: 500 Internal")
}
