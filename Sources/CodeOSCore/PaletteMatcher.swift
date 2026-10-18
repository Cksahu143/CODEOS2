import Foundation

/// Forgiving search for the command palette. Every typed letter must appear in order,
/// and names that start with the query rank first.
public enum PaletteMatcher {
    public static func matches(_ query: String, _ candidate: String) -> Bool {
        let needle = query.lowercased().filter { !$0.isWhitespace }
        let haystack = candidate.lowercased()
        var index = haystack.startIndex
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else { return false }
            index = haystack.index(after: found)
        }
        return true
    }

    public static func filter<T>(_ items: [T], query: String, title: (T) -> String) -> [T] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        let lowerQuery = trimmed.lowercased()
        var scored: [(item: T, rank: Int, position: Int)] = []
        for (position, item) in items.enumerated() {
            let name = title(item)
            guard matches(trimmed, name) else { continue }
            let lower = name.lowercased()
            let rank = lower.hasPrefix(lowerQuery) ? 0 : (lower.contains(lowerQuery) ? 1 : 2)
            scored.append((item: item, rank: rank, position: position))
        }
        scored.sort { ($0.rank, $0.position) < ($1.rank, $1.position) }
        return scored.map { $0.item }
    }
}
