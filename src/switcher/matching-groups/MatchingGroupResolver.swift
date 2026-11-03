import Foundation

/// What a matching-group rule can test. `NSPredicate` reads these key paths through KVC on the dictionary,
/// so the keys are the field names stored in `MatchingGroupRule.predicateFormat`.
enum MatchingGroupFacts {
    static let keys = ["title", "app", "bundleId", "url", "kind"]

    /// `url` is a browser tab row's URL ("" for windows); `kind` is `"tab"` for a browser tab row, else `"window"`.
    static func of(_ s: WindowState, _ app: ApplicationState, url: String? = nil, isBrowserTab: Bool = false) -> [String: String] {
        ["title": s.title, "app": app.localizedName ?? "", "bundleId": app.bundleIdentifier ?? "",
         "url": url ?? "", "kind": isBrowserTab ? "tab" : "window"]
    }
}

/// Assigns windows to matching groups and finds where the drawn sections start. Pure kernel.
///
/// A window's **rank** is the index of the first enabled group whose rule it matches, or the number of
/// enabled groups ("Other") when none do.
enum MatchingGroupResolver {
    /// The enabled rules in priority order, each with its parsed predicate. `parse` returns nil for a format
    /// that fails to load; such a rule keeps its slot but never matches.
    static func compile(_ rules: [MatchingGroupRule], parse: (String) -> NSPredicate?)
        -> [(rule: MatchingGroupRule, predicate: NSPredicate?)] {
        rules.filter { $0.isEnabled }.map { ($0, parse($0.predicateFormat)) }
    }

    /// Index of the first predicate that matches, or `predicates.count` ("Other"). nil never matches.
    static func rank(_ facts: [String: String], predicates: [NSPredicate?]) -> Int {
        predicates.firstIndex { $0?.evaluate(with: facts) == true } ?? predicates.count
    }

    /// Which candidate is pinned first during a search: the highest relevance, ties to the most recently
    /// focused. The caller passes only windows that match the query and pass the shortcut's filters.
    static func pinnedBestMatch(_ candidates: [(relevance: Double, lastFocusOrder: Int)]) -> Int? {
        candidates.indices.min {
            let a = candidates[$0], b = candidates[$1]
            if a.relevance != b.relevance { return a.relevance > b.relevance }
            return a.lastFocusOrder < b.lastFocusOrder
        }
    }

    /// Given the drawn tiles' ranks in display order, and whether tile 0 is the pinned best match, returns
    /// the positions that open a section (and so get a header). A single section draws no header, unless a
    /// pinned tile sits above it: then the header is what separates the pin from the rest.
    static func sectionStarts(ranks: [Int], firstIsPinned: Bool) -> [Int] {
        let first = firstIsPinned ? 1 : 0
        guard first < ranks.count else { return [] }
        let changes = (first + 1..<ranks.count).filter { ranks[$0] != ranks[$0 - 1] }
        guard !changes.isEmpty || firstIsPinned else { return [] }
        return [first] + changes
    }
}
