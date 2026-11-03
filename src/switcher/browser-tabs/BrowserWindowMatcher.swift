import CoreGraphics

/// Pairs a browser's script windows with the windows AltTab tracks for the same pid. Chromium's window id is
/// its own internal number, not a `CGWindowID`, so the pairing goes by frame and title. Pure kernel.
///
/// A wrong pair would switch the wrong window's tab, so anything ambiguous stays unmatched and its tabs
/// aren't listed. Each rule is a pass over the script windows still unmatched, and each tracked window is
/// used at most once.
enum BrowserWindowMatcher {
    struct Tracked: Equatable {
        let wid: CGWindowID
        let frame: CGRect
        let title: String
    }

    static let frameTolerance = CGFloat(2)

    /// scriptId → wid.
    static func match(_ script: [BrowserScriptWindow], _ tracked: [Tracked]) -> [String: CGWindowID] {
        var result = [String: CGWindowID]()
        let rules: [(BrowserScriptWindow, Tracked) -> Bool] = [
            { sameFrame($0, $1) && titleMatches($0, $1) },
            { sameFrame($0, $1) },
            { titleMatches($0, $1) },
        ]
        for rule in rules {
            pass(script, tracked, &result, rule)
        }
        return result
    }

    /// A pair is taken only when it is unique both ways: one free tracked window fits the script window, and
    /// no other unmatched script window fits that tracked window.
    private static func pass(_ script: [BrowserScriptWindow], _ tracked: [Tracked], _ result: inout [String: CGWindowID],
                             _ fits: (BrowserScriptWindow, Tracked) -> Bool) {
        let used = Set(result.values)
        let freeTracked = tracked.filter { !used.contains($0.wid) }
        let freeScript = script.filter { result[$0.scriptId] == nil }
        for s in freeScript {
            let candidates = freeTracked.filter { fits(s, $0) }
            guard candidates.count == 1, let t = candidates.first,
                  freeScript.filter({ fits($0, t) }).count == 1 else { continue }
            result[s.scriptId] = t.wid
        }
    }

    private static func sameFrame(_ s: BrowserScriptWindow, _ t: Tracked) -> Bool {
        abs(s.bounds.minX - t.frame.minX) <= frameTolerance && abs(s.bounds.minY - t.frame.minY) <= frameTolerance
            && abs(s.bounds.maxX - t.frame.maxX) <= frameTolerance && abs(s.bounds.maxY - t.frame.maxY) <= frameTolerance
    }

    /// Chromium can append a profile name (" - Work") to the window title, hence the prefix match.
    private static func titleMatches(_ s: BrowserScriptWindow, _ t: Tracked) -> Bool {
        guard let active = s.activeTab?.title, !active.isEmpty else { return false }
        return t.title == active || t.title.hasPrefix(active)
    }
}
