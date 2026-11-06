import CoreGraphics

/// The two scripting dictionaries the supported browsers speak. Helium and Brave share Chrome's.
enum BrowserDialect: Equatable {
    case chromium
    case safari
}

/// "Tab" alone already means native window tabs in this codebase (`TabGroup`, `showTabsAsWindows`), so every
/// identifier of this feature carries the `BrowserTab` prefix.
struct BrowserTab: Equatable {
    /// Identity across reads. Chromium: the tab's `id`. Safari has no tab id: "index|URL".
    let key: String
    let title: String
    let url: String
}

struct BrowserScriptWindow: Equatable {
    /// The browser's own window id. Chromium declares it as text, and it is not a `CGWindowID`.
    let scriptId: String
    /// Top-left global coordinates, like `Window.position`/`size`.
    let bounds: CGRect
    /// 1-based, as the dictionaries count.
    let activeTabIndex: Int
    let tabs: [BrowserTab]

    var activeTab: BrowserTab? { tabs.indices.contains(activeTabIndex - 1) ? tabs[activeTabIndex - 1] : nil }
}

struct BrowserSnapshot: Equatable {
    let pid: pid_t
    let dialect: BrowserDialect
    let windows: [BrowserScriptWindow]
}

/// What a tab row carries. `parentWid` is looked up in `Windows.byWindowId` when needed, never held strongly.
struct BrowserTabRef: Equatable {
    /// nil when `BrowserWindowMatcher` couldn't pair the tab's window: the row is still listed, and switching to
    /// it goes through the script alone.
    let parentWid: CGWindowID?
    let scriptWindowId: String
    let dialect: BrowserDialect
    let tab: BrowserTab
    /// The order tab rows follow their window in: the 1-based position in the tab strip. Unmatched rows count on
    /// from `BrowserTabRowsDiff.unmatchedSlotBase`, so they sort after any matched rows.
    let slot: Int
    /// 1-based position in the tab strip at read time. Safari switches tabs by it.
    let stripIndex: Int
}
