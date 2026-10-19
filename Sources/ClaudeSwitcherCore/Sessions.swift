import Foundation

/// A recent Claude Code conversation that can be resumed — on any account, because every
/// account shares ~/.claude/projects.
public struct RecentSession: Equatable, Sendable, Identifiable {
    public let id: String          // session id, for `claude --resume <id>`
    public let directory: String   // the folder it ran in (resume must start there)
    public let title: String
    public let modified: Date

    public init(id: String, directory: String, title: String, modified: Date) {
        self.id = id
        self.directory = directory
        self.title = title
        self.modified = modified
    }
}

public enum RecentSessions {
    /// Bytes read from the start of each transcript; the folder and first prompt are near the top.
    static let headBytes = 256 * 1024
    /// Retry size when the first prompt is huge (e.g. a pasted image) and the head cut it off.
    static let maxHeadBytes = 4 * 1024 * 1024
    static let titleLength = 70

    /// Newest conversations first, from `<projects>/<encoded folder>/<session id>.jsonl`.
    public static func load(projects: URL, limit: Int = 8,
                            exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [RecentSession] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let folders = (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        let files = folders.flatMap { folder in
            ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []).filter {
                $0.pathExtension == "jsonl" && !$0.lastPathComponent.hasPrefix("agent-")
            }
        }
        let dated = files.compactMap { url -> (URL, Date)? in
            guard let date = try? url.resourceValues(forKeys: Set(keys)).contentModificationDate else { return nil }
            return (url, date)
        }.sorted { $0.1 > $1.1 }

        var result: [RecentSession] = []
        for (url, date) in dated.prefix(limit * 4) {
            guard let info = read(url, bytes: headBytes) ?? read(url, bytes: maxHeadBytes),
                  exists(info.directory) else { continue }
            result.append(RecentSession(id: url.deletingPathExtension().lastPathComponent,
                                        directory: info.directory, title: info.title, modified: date))
            if result.count == limit { break }
        }
        return result
    }

    static func read(_ url: URL, bytes: Int) -> (directory: String, title: String)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return parse(head: (try? handle.read(upToCount: bytes)) ?? Data())
    }

    /// The folder (`cwd`) and a title: the session summary if present, else the first real prompt.
    static func parse(head: Data) -> (directory: String, title: String)? {
        var directory: String?
        var summary: String?
        var prompt: String?
        for line in head.split(separator: UInt8(ascii: "\n")) {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { continue }
            if directory == nil, let cwd = object["cwd"] as? String, !cwd.isEmpty { directory = cwd }
            if summary == nil, object["type"] as? String == "summary", let text = object["summary"] as? String {
                summary = text
            }
            if prompt == nil, object["type"] as? String == "user", object["isMeta"] as? Bool != true,
               let message = object["message"] as? [String: Any] {
                prompt = promptText(message["content"])
            }
            // A summary is the best title; otherwise stop at the first prompt once we know the folder.
            if directory != nil, summary != nil || prompt != nil { break }
        }
        guard let directory, let title = clean(summary ?? prompt) else { return nil }
        return (directory, title)
    }

    /// Text the user typed: skips tool results and wrapped command/system text (starts with "<").
    static func promptText(_ content: Any?) -> String? {
        let text: String?
        if let string = content as? String {
            text = string
        } else if let parts = content as? [[String: Any]] {
            text = parts.first { $0["type"] as? String == "text" }?["text"] as? String
        } else {
            text = nil
        }
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("<") || trimmed.hasPrefix("Caveat:") { return nil }
        return trimmed
    }

    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let oneLine = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !oneLine.isEmpty else { return nil }
        return oneLine.count > titleLength ? String(oneLine.prefix(titleLength - 1)) + "…" : oneLine
    }
}

/// GitHub's latest release, for the "update available" row.
public enum ReleaseCheck {
    public struct Latest: Equatable, Sendable {
        public let version: String
        public let url: URL

        public init(version: String, url: URL) {
            self.version = version
            self.url = url
        }
    }

    /// Parses `GET /repos/<owner>/<repo>/releases/latest`.
    public static func parse(_ data: Data) -> Latest? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let page = (object["html_url"] as? String).flatMap(URL.init(string:)),
              object["draft"] as? Bool != true, object["prerelease"] as? Bool != true
        else { return nil }
        return Latest(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, url: page)
    }

    /// Numeric dotted comparison: "1.10.0" > "1.9.2"; non-numeric parts count as 0.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let (a, b) = (parts(candidate), parts(current))
        for i in 0..<max(a.count, b.count) {
            let (x, y) = (i < a.count ? a[i] : 0, i < b.count ? b[i] : 0)
            if x != y { return x > y }
        }
        return false
    }
}
