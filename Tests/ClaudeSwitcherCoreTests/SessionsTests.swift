import Foundation
import Testing
@testable import ClaudeSwitcherCore

private func writeSession(_ projects: URL, folder: String, id: String, lines: [String], age: TimeInterval) throws {
    let dir = projects.appending(path: folder)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appending(path: "\(id).jsonl")
    try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-age)], ofItemAtPath: file.path)
}

@Test func recentSessionsNewestFirstWithTitles() throws {
    let projects = FileManager.default.temporaryDirectory.appending(path: "proj-\(UUID().uuidString)")
    try writeSession(projects, folder: "-work-api", id: "s1", lines: [
        #"{"type":"user","isMeta":true,"cwd":"/work/api","message":{"content":"<command-name>/init</command-name>"}}"#,
        #"{"type":"user","cwd":"/work/api","message":{"content":"Fix the   flaky\nlogin test"}}"#,
    ], age: 60)
    try writeSession(projects, folder: "-work-web", id: "s2", lines: [
        #"{"type":"summary","summary":"Redesign settings page"}"#,
        #"{"type":"user","cwd":"/work/web","message":{"content":[{"type":"text","text":"start"}]}}"#,
    ], age: 10)
    try writeSession(projects, folder: "-gone", id: "s3", lines: [
        #"{"type":"user","cwd":"/gone","message":{"content":"old"}}"#,
    ], age: 5)
    try writeSession(projects, folder: "-work-api", id: "agent-x", lines: [
        #"{"type":"user","cwd":"/work/api","message":{"content":"subagent"}}"#,
    ], age: 1)

    let sessions = RecentSessions.load(projects: projects, exists: { $0 != "/gone" })
    #expect(sessions.map(\.id) == ["s2", "s1"])
    #expect(sessions[0].title == "Redesign settings page")
    #expect(sessions[0].directory == "/work/web")
    #expect(sessions[1].title == "Fix the flaky login test")
}

@Test func sessionTitleSkipsToolResultsAndTruncates() {
    let long = String(repeating: "word ", count: 40)
    let head = Data("""
    {"type":"user","cwd":"/p","message":{"content":[{"type":"tool_result","content":"x"}]}}
    {"type":"user","cwd":"/p","message":{"content":"\(long)"}}
    """.utf8)
    let parsed = RecentSessions.parse(head: head)
    #expect(parsed?.directory == "/p")
    #expect(parsed?.title.hasSuffix("…") == true)
    #expect((parsed?.title.count ?? 0) <= 70)
    #expect(RecentSessions.parse(head: Data("not json".utf8)) == nil)
}

@Test func releaseParsing() {
    let json = #"{"tag_name":"v1.10.0","html_url":"https://github.com/o/r/releases/tag/v1.10.0","draft":false,"prerelease":false}"#
    let latest = ReleaseCheck.parse(Data(json.utf8))
    #expect(latest?.version == "1.10.0")
    #expect(latest?.url.absoluteString == "https://github.com/o/r/releases/tag/v1.10.0")
    #expect(ReleaseCheck.parse(Data(#"{"tag_name":"v2.0.0","html_url":"https://x","prerelease":true}"#.utf8)) == nil)
    #expect(ReleaseCheck.parse(Data("{}".utf8)) == nil)
}

@Test func versionComparison() {
    #expect(ReleaseCheck.isNewer("1.10.0", than: "1.9.2"))
    #expect(ReleaseCheck.isNewer("1.2", than: "1.1.9"))
    #expect(!ReleaseCheck.isNewer("1.2.0", than: "1.2"))
    #expect(!ReleaseCheck.isNewer("1.1.1", than: "1.2.0"))
    #expect(!ReleaseCheck.isNewer("dev", than: "1.0.0"))
}
