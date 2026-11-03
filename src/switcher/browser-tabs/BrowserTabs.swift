import Cocoa

/// Main-thread owner of the browser tab rows in `Windows.list`. Reads go through `BrowserTabsReader`'s queue and
/// land back here; rows are only ever inserted and removed by this type, never through `Windows.appendWindow` /
/// `removeWindows`, which are model operations (MRU ranks, window-set versions, WindowServer subscriptions).
///
/// There are no tab-change notifications, so freshness comes from signals AltTab already gets: a summon, a
/// browser window's title change (a tab switch, navigation or close all retitle the window), and browser windows
/// appearing or leaving. There is no timer.
enum BrowserTabs {
    private static var inFlight = Set<pid_t>()
    private static var rereadQueued = Set<pid_t>()
    /// A page load retitles its window several times; one read after the burst is enough.
    private static let refreshThrottler = ThrottlerWithKey(delayInMs: 300)
    /// Last answer from TCC per bundle id, for Settings.
    private(set) static var access = [String: BrowserAccess]()

    /// Tabs are only read while at least one shortcut lists them.
    static var isEnabled: Bool {
        (0...Preferences.maxShortcutCount).contains { Preferences.browserTabs($0) == .show }
    }

    static func parent(of row: Window) -> Window? {
        row.browserTab.flatMap { Windows.byWindowId[$0.parentWid] }
    }

    /// Read every running supported browser. Called after the summon's first render.
    static func refreshAll() {
        guard isEnabled else { return }
        for app in Applications.list where BrowserDialect.browser(app.bundleIdentifier) != nil {
            refresh(app.pid)
        }
    }

    static func scheduleRefresh(_ pid: pid_t) {
        guard isEnabled, let app = Applications.list.first(where: { $0.pid == pid }),
              BrowserDialect.browser(app.bundleIdentifier) != nil else { return }
        refreshThrottler.throttleOrProceed(key: "\(pid)") { refresh(pid) }
    }

    /// One read per browser at a time: a hung browser holds the serial queue, so piling more reads behind it
    /// would only delay the other browsers. A request during a read becomes one re-read after it.
    private static func refresh(_ pid: pid_t) {
        guard isEnabled, let app = Applications.list.first(where: { $0.pid == pid }), !app.isTerminated,
              let browser = BrowserDialect.browser(app.bundleIdentifier) else { return }
        guard !inFlight.contains(pid) else { rereadQueued.insert(pid); return }
        inFlight.insert(pid)
        BrowserTabsReader.queue.async {
            let access = BrowserTabsReader.access(browser.bundleId)
            let windows = access == .allowed ? BrowserTabsReader.read(browser) : nil
            DispatchQueue.main.async { landed(pid, browser, access, windows) }
        }
    }

    private static func landed(_ pid: pid_t, _ browser: SupportedBrowser, _ access: BrowserAccess, _ windows: [BrowserScriptWindow]?) {
        inFlight.remove(pid)
        self.access[browser.bundleId] = access
        if access != .allowed {
            forget(pid)
        } else if let windows {
            apply(BrowserSnapshot(pid: pid, dialect: browser.dialect, windows: windows))
        }
        if rereadQueued.remove(pid) != nil { refresh(pid) }
    }

    static func apply(_ snapshot: BrowserSnapshot) {
        guard isEnabled, Applications.list.contains(where: { $0.pid == snapshot.pid }) else { return }
        let refs = BrowserTabRowsDiff.wantedRefs(snapshot, matches: BrowserWindowMatcher.match(snapshot.windows, trackedWindows(snapshot.pid)))
        var wanted = [String: BrowserTabRef]()
        var wantedIds = [String]()
        for ref in refs {
            let id = BrowserTabRowsDiff.rowId(pid: snapshot.pid, ref)
            guard wanted[id] == nil else { continue }
            wanted[id] = ref
            wantedIds.append(id)
        }
        let existing = rows(snapshot.pid)
        let result = BrowserTabRowsDiff.diff(existing: existing.map { $0.id }, wanted: wantedIds)
        let updated = update(existing, wanted)
        let removed = Set(result.remove)
        Windows.removeBrowserTabRows(existing.filter { removed.contains($0.id) })
        let inserted = insert(result.insert.compactMap { wanted[$0] })
        guard updated || !removed.isEmpty || inserted else { return }
        App.refreshOpenUiAfterExternalEvent([])
    }

    private static func trackedWindows(_ pid: pid_t) -> [BrowserWindowMatcher.Tracked] {
        Windows.list.compactMap { w in
            guard w.application.pid == pid, w.browserTab == nil, !w.isWindowlessApp,
                  let wid = w.cgWindowId, let frame = w.frame else { return nil }
            return BrowserWindowMatcher.Tracked(wid: wid, frame: frame, title: w.title)
        }
    }

    private static func rows(_ pid: pid_t) -> [Window] {
        Windows.list.filter { $0.browserTab != nil && $0.application.pid == pid }
    }

    private static func update(_ existing: [Window], _ wanted: [String: BrowserTabRef]) -> Bool {
        var changed = false
        for row in existing {
            guard let ref = wanted[row.id], ref != row.browserTab else { continue }
            row.updateBrowserTab(ref)
            changed = true
        }
        return changed
    }

    private static func insert(_ refs: [BrowserTabRef]) -> Bool {
        let rows = refs.compactMap { ref in Windows.byWindowId[ref.parentWid].map { Window(browserTab: ref, parent: $0) } }
        guard !rows.isEmpty else { return false }
        Windows.list.append(contentsOf: rows)
        TilesView.growPoolToCoverWindows()
        return true
    }

    /// Drop a browser's rows, e.g. when it quits or its access is revoked.
    static func forget(_ pid: pid_t) {
        refreshThrottler.removeEntry(withKey: "\(pid)")
        let existing = rows(pid)
        guard !existing.isEmpty else { return }
        Windows.removeBrowserTabRows(existing)
        App.refreshOpenUiAfterExternalEvent([])
    }

    /// "Browser tabs" was turned off on every shortcut, or back on: rows go, and come back on the next read.
    static func preferenceChanged() {
        guard !isEnabled else { return refreshAll() }
        let existing = Windows.list.filter { $0.browserTab != nil }
        guard !existing.isEmpty else { return }
        Windows.removeBrowserTabRows(existing)
        App.refreshOpenUiAfterExternalEvent([])
    }

    /// Switches the browser to the tab, then runs `then` on main whether that worked or not, so a failed switch
    /// (the tab was closed meanwhile) still brings the window forward. A failure re-reads the browser.
    static func activate(_ ref: BrowserTabRef, pid: pid_t, then: @escaping () -> Void) {
        guard let browser = browser(pid) else { return then() }
        BrowserTabsReader.queue.async {
            let ok = BrowserTabsReader.act("activateTab", browser, ref)
            DispatchQueue.main.async {
                then()
                refresh(pid)
                if !ok { Logger.debug { "browserTabs activate failed for \(ref.tab.key)" } }
            }
        }
    }

    /// No optimistic removal, like closing a window: the row goes when the re-read confirms the tab is gone.
    static func close(_ ref: BrowserTabRef, pid: pid_t) {
        guard let browser = browser(pid) else { return NSSound.beep() }
        BrowserTabsReader.queue.async {
            _ = BrowserTabsReader.act("closeTab", browser, ref)
            DispatchQueue.main.async { refresh(pid) }
        }
    }

    private static func browser(_ pid: pid_t) -> SupportedBrowser? {
        BrowserDialect.browser(Applications.list.first { $0.pid == pid }?.bundleIdentifier)
    }

    /// Settings: re-check every supported browser's access, asking only for `ask`. Results land on main.
    static func checkAccess(ask bundleIdToAsk: String? = nil, _ done: @escaping () -> Void) {
        let running = Set(Applications.list.compactMap { $0.bundleIdentifier })
        BrowserTabsReader.queue.async {
            let results = BrowserDialect.supported.map { b -> (String, BrowserAccess) in
                guard running.contains(b.bundleId) else { return (b.bundleId, .unknown) }
                return (b.bundleId, BrowserTabsReader.access(b.bundleId, ask: b.bundleId == bundleIdToAsk))
            }
            DispatchQueue.main.async {
                for (id, value) in results where value != .unknown || access[id] == nil { access[id] = value }
                done()
                if bundleIdToAsk != nil { refreshAll() }
            }
        }
    }
}
