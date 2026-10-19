import Foundation

/// Folders Claude Code was recently used in, newest first, read from ~/.claude/history.jsonl.
public enum RecentProjects {
    public static func load(
        history: URL,
        limit: Int = 6,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [String] {
        guard let text = try? String(contentsOf: history, encoding: .utf8) else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for line in text.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let project = object["project"] as? String,
                  !project.isEmpty, seen.insert(project).inserted, exists(project)
            else { continue }
            result.append(project)
            if result.count == limit { break }
        }
        return result
    }
}

/// "4h 12m", "35m", "2d 5h" until `date`; nil once it has passed.
public func countdown(to date: Date, now: Date = .now) -> String? {
    let seconds = Int(date.timeIntervalSince(now))
    guard seconds > 0 else { return nil }
    let minutes = max(seconds / 60, 1)
    let (days, hours, mins) = (minutes / 1440, (minutes % 1440) / 60, minutes % 60)
    if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
    if hours > 0 { return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h" }
    return "\(mins)m"
}

/// Usage events worth a notification: an account filling up, or a full one freeing up.
public enum UsageAlert: Equatable, Sendable {
    case full(Account, percent: Int)
    case available(Account)

    public static func between(old: Usage?, new: Usage?, account: Account, limit: Int = AccountStore.limitPercent) -> UsageAlert? {
        guard let old, let new else { return nil }
        // Compare only windows both readings report; a missing window is "unknown", not 0%.
        let pairs = [(old.fiveHour, new.fiveHour), (old.sevenDay, new.sevenDay)]
            .compactMap { pair -> (Int, Int)? in
                guard let before = pair.0, let after = pair.1 else { return nil }
                return (before.percent, after.percent)
            }
        guard let before = pairs.map(\.0).max(), let after = pairs.map(\.1).max() else { return nil }
        if before < limit, after >= limit { return .full(account, percent: after) }
        if before >= limit, after < limit { return .available(account) }
        return nil
    }
}
