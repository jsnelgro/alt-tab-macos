import Foundation

/// The stored matching groups, parsed once per change so `NSPredicate(format:)` stays off the show path.
enum MatchingGroups {
    /// Enabled rules in priority order. `predicate` is nil when the stored format failed to load.
    private(set) static var compiled: [(rule: MatchingGroupRule, predicate: NSPredicate?)] = []
    private(set) static var predicates: [NSPredicate?] = []

    static func reload() {
        compiled = MatchingGroupResolver.compile(Preferences.matchingGroups, parse: parse)
        predicates = compiled.map { $0.predicate }
    }

    /// `NSPredicate(format:)` raises an Objective-C exception on a malformed string, which Swift can't catch.
    static func parse(_ format: String) -> NSPredicate? {
        var predicate: NSPredicate?
        guard ObjCExceptionCatcher.attempt({ predicate = NSPredicate(format: format) }) else { return nil }
        return predicate
    }

    static func sectionName(_ rank: Int) -> String {
        guard rank < compiled.count else { return "Other" }
        return compiled[rank].rule.name
    }
}
