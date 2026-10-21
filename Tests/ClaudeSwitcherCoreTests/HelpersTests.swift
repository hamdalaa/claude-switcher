import Foundation
import Testing
@testable import ClaudeSwitcherCore

@Test func recentProjectsNewestFirstUniqueAndExisting() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "h-\(UUID().uuidString).jsonl")
    try """
    {"project":"/old"}
    {"project":"/gone"}
    {"project":"/b"}
    not json
    {"project":"/a"}
    {"project":"/b"}
    """.write(to: url, atomically: true, encoding: .utf8)
    let projects = RecentProjects.load(history: url, limit: 3, exists: { $0 != "/gone" })
    #expect(projects == ["/b", "/a", "/old"])
}

@Test func countdownFormats() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(countdown(to: now.addingTimeInterval(-5), now: now) == nil)
    #expect(countdown(to: now.addingTimeInterval(20), now: now) == "1m")
    #expect(countdown(to: now.addingTimeInterval(35 * 60), now: now) == "35m")
    #expect(countdown(to: now.addingTimeInterval(4 * 3600 + 12 * 60), now: now) == "4h 12m")
    #expect(countdown(to: now.addingTimeInterval(3 * 3600), now: now) == "3h")
    #expect(countdown(to: now.addingTimeInterval(2 * 86400 + 5 * 3600), now: now) == "2d 5h")
}

@Test func alertsOnCrossingLimit() {
    func u(_ five: Int, _ seven: Int) -> Usage {
        Usage(fiveHour: UsageWindow(percent: five, resetsAt: nil), sevenDay: UsageWindow(percent: seven, resetsAt: nil), updatedAt: nil)
    }
    #expect(UsageAlert.between(old: u(80, 10), new: u(91, 10), account: .a) == .full(.a, percent: 91))
    #expect(UsageAlert.between(old: u(10, 95), new: u(10, 30), account: .b) == .available(.b))
    #expect(UsageAlert.between(old: u(10, 10), new: u(20, 10), account: .a) == nil)
    #expect(UsageAlert.between(old: nil, new: u(95, 10), account: .a) == nil)
}

@Test func alertIgnoresMissingWindows() {
    let full = Usage(fiveHour: UsageWindow(percent: 92, resetsAt: nil), sevenDay: UsageWindow(percent: 40, resetsAt: nil), updatedAt: nil)
    let onlyWeekly = Usage(fiveHour: nil, sevenDay: UsageWindow(percent: 40, resetsAt: nil), updatedAt: nil)
    #expect(UsageAlert.between(old: full, new: onlyWeekly, account: .a) == nil)
    let empty = Usage(fiveHour: nil, sevenDay: nil, updatedAt: nil)
    #expect(UsageAlert.between(old: full, new: empty, account: .a) == nil)
}

@Test func normalizedZeroesExpiredWindows() {
    let now = Date(timeIntervalSince1970: 1000)
    let usage = Usage(fiveHour: UsageWindow(percent: 95, resetsAt: now.addingTimeInterval(-1)),
                      sevenDay: UsageWindow(percent: 50, resetsAt: now.addingTimeInterval(60)), updatedAt: nil, isLive: true)
    let n = usage.normalized(now: now)
    #expect(n.fiveHour?.percent == 0)
    #expect(n.fiveHour?.resetsAt == nil)
    #expect(n.sevenDay?.percent == 50)
    #expect(n.isLive)
}

@Test func newerWindowKeepsHigherUseWithinOneWindow() {
    let reset = Date(timeIntervalSince1970: 18_000)
    let fresh = UsageWindow(percent: 43, resetsAt: reset.addingTimeInterval(0.2))   // API adds fractions
    let replayed = UsageWindow(percent: 25, resetsAt: reset)                          // idle session's old number
    #expect(UsageWindow.newer(fresh, replayed) == fresh)
    #expect(UsageWindow.newer(replayed, fresh) == fresh)
}

@Test func newerWindowPrefersLaterReset() {
    let old = UsageWindow(percent: 95, resetsAt: Date(timeIntervalSince1970: 18_000))
    let next = UsageWindow(percent: 3, resetsAt: Date(timeIntervalSince1970: 36_000))
    #expect(UsageWindow.newer(old, next) == next)
    #expect(UsageWindow.newer(next, old) == next)
    let reset = UsageWindow(percent: 0, resetsAt: nil)
    #expect(UsageWindow.newer(reset, next) == next)
    #expect(UsageWindow.newer(nil, next) == next)
    #expect(UsageWindow.newer(next, nil) == next)
}

@Test func mergedCombinesEachWindowAndKeepsLiveFlag() {
    let r5 = Date(timeIntervalSince1970: 18_000), r7 = Date(timeIntervalSince1970: 600_000)
    let live = Usage(fiveHour: UsageWindow(percent: 43, resetsAt: r5), sevenDay: UsageWindow(percent: 99, resetsAt: r7),
                     updatedAt: Date(timeIntervalSince1970: 100), isLive: true)
    let file = Usage(fiveHour: UsageWindow(percent: 25, resetsAt: r5), sevenDay: UsageWindow(percent: 100, resetsAt: r7),
                     updatedAt: Date(timeIntervalSince1970: 200))
    let merged = live.merged(with: file)
    #expect(merged.fiveHour?.percent == 43)
    #expect(merged.sevenDay?.percent == 100)
    #expect(merged.updatedAt == Date(timeIntervalSince1970: 200))
    #expect(merged.isLive)
    #expect(live.merged(with: nil) == live)
}
