import XCTest

/// Pins which tab rows a snapshot wants and how they reconcile with existing rows. See `BrowserTabRowsDiffSpecs.md`.
final class BrowserTabRowsDiffTests: XCTestCase {
    private func snapshot(_ keys: [String], active: Int, dialect: BrowserDialect = .chromium) -> BrowserSnapshot {
        let tabs = keys.map { BrowserTab(key: $0, title: $0, url: "https://\($0)") }
        let window = BrowserScriptWindow(scriptId: "w1", bounds: .zero, activeTabIndex: active, tabs: tabs)
        return BrowserSnapshot(pid: 7, dialect: dialect, windows: [window])
    }

    private func ids(_ s: BrowserSnapshot) -> [String] {
        BrowserTabRowsDiff.wantedRefs(s, matches: ["w1": 100]).map { BrowserTabRowsDiff.rowId(pid: s.pid, $0) }
    }

    func testUnchangedKeepsAll() {
        let wanted = ids(snapshot(["a", "b", "c"], active: 1))
        XCTAssertEqual(BrowserTabRowsDiff.diff(existing: wanted, wanted: wanted),
            .init(keep: wanted, insert: [], remove: []))
    }

    func testNewTabIsInserted() {
        let old = ids(snapshot(["a", "b"], active: 1)), new = ids(snapshot(["a", "b", "c"], active: 1))
        XCTAssertEqual(BrowserTabRowsDiff.diff(existing: old, wanted: new),
            .init(keep: ["btab-7-w1-b"], insert: ["btab-7-w1-c"], remove: []))
    }

    func testClosedTabIsRemoved() {
        let old = ids(snapshot(["a", "b", "c"], active: 1)), new = ids(snapshot(["a", "b"], active: 1))
        XCTAssertEqual(BrowserTabRowsDiff.diff(existing: old, wanted: new),
            .init(keep: ["btab-7-w1-b"], insert: [], remove: ["btab-7-w1-c"]))
    }

    func testActiveTabChangeSwapsWhichTabHasARow() {
        let old = ids(snapshot(["a", "b", "c"], active: 1)), new = ids(snapshot(["a", "b", "c"], active: 2))
        XCTAssertEqual(BrowserTabRowsDiff.diff(existing: old, wanted: new),
            .init(keep: ["btab-7-w1-c"], insert: ["btab-7-w1-a"], remove: ["btab-7-w1-b"]))
    }

    func testSafariTabMovedIsRemoveAndInsert() {
        let s1 = BrowserSnapshot(pid: 7, dialect: .safari, windows: [BrowserScriptWindow(scriptId: "w1", bounds: .zero, activeTabIndex: 1,
            tabs: [BrowserTab(key: "1|https://x", title: "X", url: "https://x"), BrowserTab(key: "2|https://y", title: "Y", url: "https://y")])])
        let s2 = BrowserSnapshot(pid: 7, dialect: .safari, windows: [BrowserScriptWindow(scriptId: "w1", bounds: .zero, activeTabIndex: 2,
            tabs: [BrowserTab(key: "1|https://y", title: "Y", url: "https://y"), BrowserTab(key: "2|https://x", title: "X", url: "https://x")])])
        XCTAssertEqual(BrowserTabRowsDiff.diff(existing: ids(s1), wanted: ids(s2)),
            .init(keep: [], insert: ["btab-7-w1-1|https://y"], remove: ["btab-7-w1-2|https://y"]))
    }

    func testSlotsFollowStripOrderSkippingTheActiveTab() {
        let refs = BrowserTabRowsDiff.wantedRefs(snapshot(["a", "b", "c", "d"], active: 2), matches: ["w1": 100])
        XCTAssertEqual(refs.map { $0.tab.key }, ["a", "c", "d"])
        XCTAssertEqual(refs.map { $0.slot }, [1, 2, 3])
        XCTAssertEqual(refs.map { $0.stripIndex }, [1, 3, 4])
        XCTAssertEqual(Set(refs.map { $0.parentWid }), [100])
    }

    func testUnmatchedOrSingleTabWindowWantsNoRows() {
        XCTAssertEqual(BrowserTabRowsDiff.wantedRefs(snapshot(["a", "b"], active: 1), matches: [:]), [])
        XCTAssertEqual(BrowserTabRowsDiff.wantedRefs(snapshot(["a"], active: 1), matches: ["w1": 100]), [])
    }
}
