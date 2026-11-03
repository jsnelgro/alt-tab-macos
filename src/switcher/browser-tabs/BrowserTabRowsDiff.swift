import CoreGraphics

/// Which tab rows a fresh snapshot wants, and how they reconcile with the rows already in the list. Pure kernel.
enum BrowserTabRowsDiff {
    struct Result: Equatable {
        let keep: [String]
        let insert: [String]
        let remove: [String]
    }

    static func rowId(pid: pid_t, _ ref: BrowserTabRef) -> String {
        "btab-\(pid)-\(ref.scriptWindowId)-\(ref.tab.key)"
    }

    /// One row per tab of each matched window, except its active tab: the window's own row already is that
    /// tab. A window with a single tab adds nothing.
    static func wantedRefs(_ snapshot: BrowserSnapshot, matches: [String: CGWindowID]) -> [BrowserTabRef] {
        snapshot.windows.flatMap { w -> [BrowserTabRef] in
            guard let wid = matches[w.scriptId], w.tabs.count > 1 else { return [] }
            var slot = 0
            return w.tabs.enumerated().compactMap { i, tab in
                guard i + 1 != w.activeTabIndex else { return nil }
                slot += 1
                return BrowserTabRef(parentWid: wid, scriptWindowId: w.scriptId, dialect: snapshot.dialect,
                    tab: tab, slot: slot, stripIndex: i + 1)
            }
        }
    }

    static func diff(existing: [String], wanted: [String]) -> Result {
        let existingSet = Set(existing), wantedSet = Set(wanted)
        return Result(keep: wanted.filter { existingSet.contains($0) },
            insert: wanted.filter { !existingSet.contains($0) },
            remove: existing.filter { !wantedSet.contains($0) })
    }
}
