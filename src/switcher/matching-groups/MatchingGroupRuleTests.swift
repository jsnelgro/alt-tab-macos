import XCTest

/// Pins that stored matching groups are never lost: round-tripping, older shapes, corrupt entries, and the
/// reorder arithmetic the Settings list relies on.
///
/// Groups: A persistence · B reordering.
final class MatchingGroupRuleTests: XCTestCase {

    // MARK: - A. Persistence

    func testSaveThenReloadKeepsEveryField() throws {
        let rules = [MatchingGroupRule(name: "Comms", predicateFormat: "app ==[c] \"Messages\"", isEnabled: true),
                     MatchingGroupRule(name: "Projects", predicateFormat: "title BEGINSWITH[c] \"Project\"", isEnabled: false)]
        let json = String(data: try JSONEncoder().encode(rules), encoding: .utf8)!
        XCTAssertEqual(MatchingGroupRule.decodeList(json), rules)
    }

    func testOldShapeWithMissingFieldsGetsDefaults() {
        let decoded = MatchingGroupRule.decodeList(#"[{"predicateFormat":"app == \"A\""}]"#)
        XCTAssertEqual(decoded?.count, 1)
        XCTAssertEqual(decoded?.first?.name, "")
        XCTAssertEqual(decoded?.first?.isEnabled, true)
        XCTAssertEqual(decoded?.first?.predicateFormat, #"app == "A""#)
    }

    func testCorruptEntryIsDroppedAndTheOthersKept() {
        let json = #"[{"name":"A","predicateFormat":"app == \"A\""},{"name":"broken"},42,{"name":"B","predicateFormat":"app == \"B\""}]"#
        XCTAssertEqual(MatchingGroupRule.decodeList(json)?.map { $0.name }, ["A", "B"])
    }

    // MARK: - B. Reordering

    func testMovingDownCountsTheDestinationBeforeTheRemoval() {
        XCTAssertEqual(["a", "b", "c"].moved(from: 0, to: 2), ["b", "a", "c"])
        XCTAssertEqual(["a", "b", "c"].moved(from: 0, to: 3), ["b", "c", "a"])
    }

    func testMovingUp() {
        XCTAssertEqual(["a", "b", "c"].moved(from: 2, to: 0), ["c", "a", "b"])
    }

    func testDroppingOntoItselfChangesNothing() {
        XCTAssertEqual(["a", "b", "c"].moved(from: 1, to: 1), ["a", "b", "c"])
        XCTAssertEqual(["a", "b", "c"].moved(from: 1, to: 2), ["a", "b", "c"])
    }
}
