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

    static let unmatchedSlotBase = 1_000_000

    /// One row per tab of every window, the active tab included, so each tab shows its own title and site icon;
    /// the window keeps its own row. An unmatched window's tabs are listed too, with no parent; their slots run
    /// on across all unmatched windows so each window's tabs stay together.
    static func wantedRefs(_ snapshot: BrowserSnapshot, matches: [String: CGWindowID]) -> [BrowserTabRef] {
        var refs = [BrowserTabRef]()
        var unmatchedSlot = unmatchedSlotBase
        for w in snapshot.windows {
            let wid = matches[w.scriptId]
            for (i, tab) in w.tabs.enumerated() {
                unmatchedSlot += wid == nil ? 1 : 0
                refs.append(BrowserTabRef(parentWid: wid, scriptWindowId: w.scriptId, dialect: snapshot.dialect,
                    tab: tab, slot: wid == nil ? unmatchedSlot : i + 1, stripIndex: i + 1))
            }
        }
        return refs
    }

    static func diff(existing: [String], wanted: [String]) -> Result {
        let existingSet = Set(existing), wantedSet = Set(wanted)
        return Result(keep: wanted.filter { existingSet.contains($0) },
            insert: wanted.filter { !existingSet.contains($0) },
            remove: existing.filter { !wantedSet.contains($0) })
    }
}
