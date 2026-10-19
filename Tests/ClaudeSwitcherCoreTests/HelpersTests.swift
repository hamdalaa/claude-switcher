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
