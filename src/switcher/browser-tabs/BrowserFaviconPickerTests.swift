import XCTest

/// Pins which cached bitmap a tab gets and which URLs count as its site. See `BrowserFaviconPickerSpecs.md`.
final class BrowserFaviconPickerTests: XCTestCase {
    private func b(_ id: Int64, _ width: Int) -> BrowserFaviconPicker.Bitmap { .init(id: id, width: width) }

    func testSmallestBitmapAtLeastThePreferredWidthWins() {
        XCTAssertEqual(BrowserFaviconPicker.bestBitmap([b(1, 16), b(2, 128), b(3, 64)]), 3)
    }

    func testLargestBitmapWinsWhenAllAreSmaller() {
        XCTAssertEqual(BrowserFaviconPicker.bestBitmap([b(1, 16), b(2, 32)]), 2)
    }

    func testNoBitmapsNoPick() {
        XCTAssertNil(BrowserFaviconPicker.bestBitmap([]))
    }

    func testSiteRangesCoverBothSchemesWithAndWithoutWww() {
        let ranges = BrowserFaviconPicker.siteRanges("https://www.GitHub.com/apple/swift?tab=readme")
        XCTAssertEqual(ranges.map { $0.lower }, ["https://github.com/", "https://www.github.com/",
                                                  "http://github.com/", "http://www.github.com/"])
        XCTAssertEqual(ranges.first?.upper, "https://github.com0")
    }

    func testSiteRangesContainTheSitesPagesOnly() {
        let range = BrowserFaviconPicker.siteRanges("https://github.com/x")[0]
        for page in ["https://github.com/", "https://github.com/apple/swift"] {
            XCTAssertTrue(page >= range.lower && page < range.upper, page)
        }
        for page in ["https://github.community/", "https://github.co/", "https://gist.github.com/"] {
            XCTAssertFalse(page >= range.lower && page < range.upper, page)
        }
    }

    func testNonWebUrlsHaveNoSite() {
        for url in ["chrome://settings", "about:blank", "file:///tmp/a.html", "", "https:///nohost"] {
            XCTAssertTrue(BrowserFaviconPicker.siteRanges(url).isEmpty, url)
        }
    }
}
