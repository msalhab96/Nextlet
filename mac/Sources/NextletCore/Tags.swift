import Foundation

/// Optional labels on a task, such as "phone" or "errands". Same rules as the server.
public enum Tags {
    public static let maxCount = 20
    public static let maxLength = 40

    /// "  @Deep   work " → "Deep work": no leading @, single spaces, trimmed, at most 40 characters.
    public static func clean(_ tag: String) -> String {
        let cleaned = tag
            .replacingOccurrences(of: "^[\\s@]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return String(cleaned.prefix(maxLength))
    }

    /// Cleans every tag and drops repeats, ignoring case; the first spelling wins.
    public static func cleaned(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            let tag = clean(raw)
            let key = tag.lowercased()
            guard !tag.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(tag)
        }
        return Array(result.prefix(maxCount))
    }

    public static func same(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }

    public static func contains(_ tags: [String], _ tag: String) -> Bool {
        tags.contains { same($0, tag) }
    }

    /// The spelling already in use for `tag`, if any.
    public static func existing(_ tag: String, in known: [String]) -> String {
        known.first { same($0, tag) } ?? tag
    }
}
