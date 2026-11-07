import Foundation

/// A browser whose tabs can be listed: its bundle id, the dictionary it speaks, and a name for Settings.
struct SupportedBrowser: Equatable {
    let bundleId: String
    let name: String
    let dialect: BrowserDialect
    /// Under `~/Library/Application Support`: the folder holding the browser's profiles (`Default`, `Profile 1`…),
    /// each with its own `Favicons` cache.
    let dataDirectory: String
}

extension BrowserDialect {
    /// Another Chromium browser is one line here. Safari is left out on purpose: its dictionary has no way to
    /// tell a private window from a normal one, so its private tabs would be listed. Its dialect is kept (script
    /// and parser) for the day a reliable private-window signal is found.
    static let supported = [
        SupportedBrowser(bundleId: "net.imput.helium", name: "Helium", dialect: .chromium, dataDirectory: "net.imput.helium"),
        SupportedBrowser(bundleId: "com.brave.Browser", name: "Brave", dialect: .chromium, dataDirectory: "BraveSoftware/Brave-Browser"),
    ]

    static func browser(_ bundleId: String?) -> SupportedBrowser? {
        supported.first { $0.bundleId == bundleId }
    }

    /// Three handlers per dialect, called by name with descriptor arguments (`BrowserTabsReader.call`), so a
    /// tab's title or URL is never pasted into source. The bundle id is: it comes from `supported`, not from
    /// any browser, and a literal `tell application id` is what lets the dictionary's terms compile.
    ///
    /// `raiseWindow` brings the tab's window to the front of the browser's windows, for a row with no parent
    /// window for AltTab to focus. Both act handlers take it so `BrowserTabsReader.act` passes one argument list.
    ///
    /// `with timeout` caps each Apple Event: the default wait for a busy browser is about two minutes.
    /// Ids are compared `as text` because both Chromium dictionaries declare them text, but older builds
    /// answered integers.
    func scriptSource(bundleId: String) -> String {
        switch self {
        case .chromium: return Self.chromiumSource.replacingOccurrences(of: "BUNDLE_ID", with: bundleId)
        case .safari: return Self.safariSource.replacingOccurrences(of: "BUNDLE_ID", with: bundleId)
        }
    }

    private static let chromiumSource = """
    on readTabs()
        with timeout of 2 seconds
            tell application id "BUNDLE_ID"
                if (count of windows) is 0 then return {}
                return {id of every window, mode of every window, bounds of every window, active tab index of every window, id of every tab of every window, title of every tab of every window, URL of every tab of every window}
            end tell
        end timeout
    end readTabs

    on findWindow(windowId)
        tell application id "BUNDLE_ID"
            repeat with w in windows
                if (id of w as text) is windowId then return w
            end repeat
        end tell
        error "window not found"
    end findWindow

    on tabIndex(w, tabId)
        tell application id "BUNDLE_ID"
            set i to 0
            repeat with t in tabs of w
                set i to i + 1
                if (id of t as text) is tabId then return i
            end repeat
        end tell
        error "tab not found"
    end tabIndex

    on activateTab(windowId, tabId, stripIndex, tabURL, raiseWindow)
        with timeout of 2 seconds
            set w to findWindow(windowId)
            set i to tabIndex(w, tabId)
            tell application id "BUNDLE_ID"
                set active tab index of w to i
                if raiseWindow then
                    if minimized of w then set minimized of w to false
                    set index of w to 1
                end if
            end tell
        end timeout
        return true
    end activateTab

    on closeTab(windowId, tabId, stripIndex, tabURL, raiseWindow)
        with timeout of 2 seconds
            set w to findWindow(windowId)
            set i to tabIndex(w, tabId)
            tell application id "BUNDLE_ID" to close tab i of w
        end timeout
        return true
    end closeTab
    """

    /// Settings or Downloads windows have no current tab, so each window is read in a `try`. A tab is found
    /// by its index, falling back to its URL when tabs moved since the read.
    private static let safariSource = """
    on readTabs()
        set out to {}
        with timeout of 2 seconds
            tell application id "BUNDLE_ID"
                repeat with w in windows
                    try
                        set end of out to {id of w, bounds of w, index of current tab of w, name of tabs of w, URL of tabs of w}
                    end try
                end repeat
            end tell
        end timeout
        return out
    end readTabs

    on findTab(windowId, stripIndex, tabURL)
        tell application id "BUNDLE_ID"
            set w to (first window whose id is (windowId as integer))
            if URL of tab stripIndex of w is not tabURL then
                set stripIndex to index of (first tab of w whose URL is tabURL)
            end if
            return {w, stripIndex}
        end tell
    end findTab

    on activateTab(windowId, tabId, stripIndex, tabURL, raiseWindow)
        with timeout of 2 seconds
            set {w, i} to findTab(windowId, stripIndex, tabURL)
            tell application id "BUNDLE_ID"
                set current tab of w to tab i of w
                if raiseWindow then set index of w to 1
            end tell
        end timeout
        return true
    end activateTab

    on closeTab(windowId, tabId, stripIndex, tabURL, raiseWindow)
        with timeout of 2 seconds
            set {w, i} to findTab(windowId, stripIndex, tabURL)
            tell application id "BUNDLE_ID" to close tab i of w
        end timeout
        return true
    end closeTab
    """
}
