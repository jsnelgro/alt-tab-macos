import XCTest

/// Pins how read-handler replies become script windows. See `BrowserTabReplyParserSpecs.md`.
final class BrowserTabReplyParserTests: XCTestCase {
    private func list(_ items: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        let l = NSAppleEventDescriptor.list()
        for item in items { l.insert(item, at: l.numberOfItems + 1) }
        return l
    }

    private func s(_ v: String) -> NSAppleEventDescriptor { NSAppleEventDescriptor(string: v) }
    private func i(_ v: Int) -> NSAppleEventDescriptor { NSAppleEventDescriptor(int32: Int32(v)) }
    private func strings(_ v: [String]) -> NSAppleEventDescriptor { list(v.map(s)) }
    private func bounds(_ l: Int, _ t: Int, _ r: Int, _ b: Int) -> NSAppleEventDescriptor { list([i(l), i(t), i(r), i(b)]) }

    private func chromium(ids: [String], modes: [String], bounds b: [NSAppleEventDescriptor], active: [Int],
                          tabIds: [[String]], titles: [[String]], urls: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        list([strings(ids), strings(modes), list(b), list(active.map(i)), list(tabIds.map(strings)),
              list(titles.map(strings)), list(urls)])
    }

    func testChromiumReplyWithTwoWindowsZipsIntoTabs() {
        let reply = chromium(ids: ["1", "2"], modes: ["normal", "normal"],
            bounds: [bounds(0, 25, 800, 625), bounds(100, 100, 500, 400)], active: [2, 1],
            tabIds: [["10", "11"], ["20"]], titles: [["A", "B"], ["C"]],
            urls: [strings(["https://a", "https://b"]), strings(["https://c"])])
        let windows = BrowserTabReplyParser.parse(reply, dialect: .chromium)
        XCTAssertEqual(windows.map { $0.scriptId }, ["1", "2"])
        XCTAssertEqual(windows[0].tabs, [BrowserTab(key: "10", title: "A", url: "https://a"),
                                         BrowserTab(key: "11", title: "B", url: "https://b")])
        XCTAssertEqual(windows[0].activeTabIndex, 2)
        XCTAssertEqual(windows[0].activeTab?.key, "11")
        XCTAssertEqual(windows[1].tabs.map { $0.key }, ["20"])
    }

    func testEmptyReplyGivesNoWindows() {
        XCTAssertEqual(BrowserTabReplyParser.parse(list([]), dialect: .chromium), [])
        XCTAssertEqual(BrowserTabReplyParser.parse(list([]), dialect: .safari), [])
    }

    func testIncognitoOrUnknownModeWindowIsDropped() {
        let reply = chromium(ids: ["1", "2", "3"], modes: ["incognito", "normal", "guest"],
            bounds: [bounds(0, 0, 10, 10), bounds(0, 0, 10, 10), bounds(0, 0, 10, 10)], active: [1, 1, 1],
            tabIds: [["10"], ["20"], ["30"]], titles: [["secret"], ["B"], ["C"]],
            urls: [strings(["https://secret"]), strings(["https://b"]), strings(["https://c"])])
        let windows = BrowserTabReplyParser.parse(reply, dialect: .chromium)
        XCTAssertEqual(windows.map { $0.scriptId }, ["2"])
    }

    func testMissingValueUrlBecomesEmpty() {
        let reply = chromium(ids: ["1"], modes: ["normal"], bounds: [bounds(0, 0, 10, 10)], active: [1],
            tabIds: [["10"]], titles: [["New Tab"]], urls: [list([NSAppleEventDescriptor.null()])])
        XCTAssertEqual(BrowserTabReplyParser.parse(reply, dialect: .chromium).first?.tabs.first?.url, "")
    }

    func testMalformedWindowIsDroppedAndOthersKept() {
        let reply = chromium(ids: ["1", "2"], modes: ["normal", "normal"],
            bounds: [list([i(0), i(0)]), bounds(0, 0, 10, 10)], active: [1, 1],
            tabIds: [["10"], ["20"]], titles: [["A"], ["B"]],
            urls: [strings(["https://a"]), strings(["https://b"])])
        XCTAssertEqual(BrowserTabReplyParser.parse(reply, dialect: .chromium).map { $0.scriptId }, ["2"])
    }

    func testBoundsBecomeTopLeftRects() {
        let reply = chromium(ids: ["1"], modes: ["normal"], bounds: [bounds(100, 50, 900, 650)], active: [1],
            tabIds: [["10"]], titles: [["A"]], urls: [strings(["https://a"])])
        XCTAssertEqual(BrowserTabReplyParser.parse(reply, dialect: .chromium).first?.bounds,
            CGRect(x: 100, y: 50, width: 800, height: 600))
    }

    func testSafariReplyMissingOneWindowParsesTheRest() {
        let w1 = list([i(41), bounds(0, 0, 10, 10), i(2), strings(["A", "B"]), strings(["https://a", "https://b"])])
        let broken = list([i(42)])
        let windows = BrowserTabReplyParser.parse(list([w1, broken]), dialect: .safari)
        XCTAssertEqual(windows.map { $0.scriptId }, ["41"])
        XCTAssertEqual(windows[0].tabs.map { $0.key }, ["1|https://a", "2|https://b"])
        XCTAssertEqual(windows[0].activeTab?.title, "B")
    }
}
