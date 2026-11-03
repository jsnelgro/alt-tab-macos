import XCTest

/// Pins how script windows are paired with tracked windows. See `BrowserWindowMatcherSpecs.md`.
final class BrowserWindowMatcherTests: XCTestCase {
    private let frameA = CGRect(x: 0, y: 25, width: 800, height: 600)
    private let frameB = CGRect(x: 900, y: 25, width: 600, height: 500)

    private func script(_ id: String, _ frame: CGRect, active: String) -> BrowserScriptWindow {
        BrowserScriptWindow(scriptId: id, bounds: frame, activeTabIndex: 1,
            tabs: [BrowserTab(key: id + "-t", title: active, url: "")])
    }

    private func tracked(_ wid: CGWindowID, _ frame: CGRect, _ title: String) -> BrowserWindowMatcher.Tracked {
        BrowserWindowMatcher.Tracked(wid: wid, frame: frame, title: title)
    }

    func testFrameAndTitleMatch() {
        let m = BrowserWindowMatcher.match([script("1", frameA, active: "GitHub")], [tracked(10, frameA.offsetBy(dx: 1, dy: 0), "GitHub")])
        XCTAssertEqual(m, ["1": 10])
    }

    func testTitleWithProfileSuffixMatches() {
        let m = BrowserWindowMatcher.match([script("1", frameA, active: "GitHub"), script("2", frameA, active: "Mail")],
            [tracked(10, frameA, "GitHub - Work"), tracked(11, frameA, "Mail - Work")])
        XCTAssertEqual(m, ["1": 10, "2": 11])
    }

    func testTwoWindowsWithOneFrameToldApartByTitle() {
        let m = BrowserWindowMatcher.match([script("1", frameA, active: "A"), script("2", frameA, active: "B")],
            [tracked(10, frameA, "B"), tracked(11, frameA, "A")])
        XCTAssertEqual(m, ["1": 11, "2": 10])
    }

    func testFrameOnlyMatchWhenUnique() {
        let m = BrowserWindowMatcher.match([script("1", frameA, active: "Loading…")], [tracked(10, frameA, "Old title"), tracked(11, frameB, "Other")])
        XCTAssertEqual(m, ["1": 10])
    }

    func testTitleOnlyMatchWhenUnique() {
        let moved = CGRect(x: 300, y: 300, width: 800, height: 600)
        let m = BrowserWindowMatcher.match([script("1", moved, active: "Docs")], [tracked(10, frameA, "Docs"), tracked(11, frameB, "Mail")])
        XCTAssertEqual(m, ["1": 10])
    }

    func testAmbiguousStaysUnmatched() {
        let m = BrowserWindowMatcher.match([script("1", frameA, active: "X")], [tracked(10, frameA, "Y"), tracked(11, frameA, "Z")])
        XCTAssertEqual(m, [:])
    }

    func testEachTrackedWindowMatchedAtMostOnce() {
        let m = BrowserWindowMatcher.match([script("1", frameA, active: "X"), script("2", frameA, active: "Y")], [tracked(10, frameA, "Z")])
        XCTAssertEqual(m, [:])
    }

    func testNoCandidatesNoMatches() {
        XCTAssertEqual(BrowserWindowMatcher.match([script("1", frameA, active: "X")], []), [:])
    }
}
