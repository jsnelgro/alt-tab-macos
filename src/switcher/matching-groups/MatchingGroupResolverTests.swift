import XCTest

/// Pins matching-group assignment (`rank`, `compile`), best-match pinning, and where sections start.
///
/// Groups: A ranks · B best-match pinning · C section starts.
final class MatchingGroupResolverTests: XCTestCase {
    private func facts(title: String = "", app: String? = "", bundleId: String? = nil) -> [String: String] {
        let state = WindowState(id: "w", isPhantom: false, isWindowlessApp: false, isFullscreen: false,
                                isMinimized: false, isTabbed: false, isOnAllSpaces: false, spaceIds: [],
                                spaceIndexes: [], lastFocusOrder: 0, creationOrder: 0, title: title)
        let application = ApplicationState(pid: 0, bundleIdentifier: bundleId, localizedName: app, isHidden: false)
        return MatchingGroupFacts.of(state, application)
    }

    private func p(_ format: String) -> NSPredicate { NSPredicate(format: format) }

    private func rule(_ format: String, enabled: Bool = true) -> MatchingGroupRule {
        MatchingGroupRule(name: format, predicateFormat: format, isEnabled: enabled)
    }

    // MARK: - A. Ranks

    func testFirstMatchWinsWhenTwoRulesMatch() {
        let predicates = [p("app ==[c] 'Messages'"), p("title CONTAINS[c] 'inbox'")]
        XCTAssertEqual(MatchingGroupResolver.rank(facts(title: "Inbox", app: "Messages"), predicates: predicates), 0)
    }

    func testDisabledRulesAreSkipped() {
        let compiled = MatchingGroupResolver.compile([rule("app == 'A'", enabled: false), rule("app == 'B'")]) { NSPredicate(format: $0) }
        XCTAssertEqual(compiled.map { $0.rule.predicateFormat }, ["app == 'B'"])
        XCTAssertEqual(MatchingGroupResolver.rank(facts(app: "B"), predicates: compiled.map { $0.predicate }), 0)
    }

    func testNilPredicateNeverMatches() {
        let compiled = MatchingGroupResolver.compile([rule("broken"), rule("app == 'B'")]) { _ in nil }
        XCTAssertEqual(compiled.count, 2)
        XCTAssertEqual(MatchingGroupResolver.rank(facts(app: "B"), predicates: [nil, p("app == 'B'")]), 1)
    }

    func testNoMatchIsOther() {
        XCTAssertEqual(MatchingGroupResolver.rank(facts(app: "C"), predicates: [p("app == 'A'"), p("app == 'B'")]), 2)
    }

    func testEmptyListRanksEveryoneZero() {
        XCTAssertEqual(MatchingGroupResolver.rank(facts(app: "C"), predicates: []), 0)
    }

    func testMatchesIsAFullStringMatch() {
        let alpha = facts(title: "Project Alpha")
        XCTAssertEqual(MatchingGroupResolver.rank(alpha, predicates: [p("title MATCHES[c] 'Project'")]), 1)
        XCTAssertEqual(MatchingGroupResolver.rank(alpha, predicates: [p("title MATCHES[c] '^Project.*'")]), 0)
    }

    func testComparisonsIgnoreCase() {
        XCTAssertEqual(MatchingGroupResolver.rank(facts(title: "INBOX (3)"), predicates: [p("title BEGINSWITH[c] 'inbox ('")]), 0)
    }

    func testNilAppNameEvaluatesAsEmpty() {
        let windowless = facts(app: nil, bundleId: "com.example")
        XCTAssertEqual(windowless["app"], "")
        XCTAssertEqual(MatchingGroupResolver.rank(windowless, predicates: [p("bundleId == 'com.example'")]), 0)
    }

    // MARK: - B. Best-match pinning

    func testPinnedBestMatchIsTheHighestRelevance() {
        XCTAssertEqual(MatchingGroupResolver.pinnedBestMatch([(1, 0), (3, 2), (2, 1)]), 1)
    }

    func testPinnedBestMatchTiesGoToTheMostRecentlyFocused() {
        XCTAssertEqual(MatchingGroupResolver.pinnedBestMatch([(2, 5), (2, 1), (2, 3)]), 1)
    }

    func testPinnedBestMatchIsNilWithoutCandidates() {
        XCTAssertNil(MatchingGroupResolver.pinnedBestMatch([]))
    }

    // MARK: - C. Section starts

    func testAllTilesInOneRankDrawNoHeaders() {
        XCTAssertEqual(MatchingGroupResolver.sectionStarts(ranks: [1, 1, 1], firstIsPinned: false), [])
    }

    func testEachRankChangeOpensASection() {
        XCTAssertEqual(MatchingGroupResolver.sectionStarts(ranks: [0, 0, 1, 2], firstIsPinned: false), [0, 2, 3])
    }

    func testPinnedAndTheRestInOneRankHeadsTheRest() {
        XCTAssertEqual(MatchingGroupResolver.sectionStarts(ranks: [0, 2, 2], firstIsPinned: true), [1])
    }

    func testPinnedTilesOwnGroupContinuingGetsAHeaderAfterThePin() {
        XCTAssertEqual(MatchingGroupResolver.sectionStarts(ranks: [1, 1, 2], firstIsPinned: true), [1, 2])
    }

    func testASinglePinnedTileDrawsNoHeaders() {
        XCTAssertEqual(MatchingGroupResolver.sectionStarts(ranks: [0], firstIsPinned: true), [])
    }
}
