import Foundation
import CoreServices

/// Turns a read handler's reply into script windows. Pure: only walks `NSAppleEventDescriptor` values, so tests
/// build replies with `NSAppleEventDescriptor.list()`.
///
/// Chromium replies with seven parallel lists (window ids, modes, bounds, active tab indexes, then per-window
/// lists of tab ids, titles and URLs). Safari replies with one list per window. Lists are 1-based.
enum BrowserTabReplyParser {
    static func parse(_ reply: NSAppleEventDescriptor, dialect: BrowserDialect) -> [BrowserScriptWindow] {
        switch dialect {
        case .chromium: return parseChromium(items(reply))
        case .safari: return items(reply).compactMap(parseSafariWindow)
        }
    }

    /// Only `"normal"` windows are kept, so incognito (and any mode a later version adds) never leaves here.
    private static func parseChromium(_ columns: [NSAppleEventDescriptor]) -> [BrowserScriptWindow] {
        guard columns.count == 7 else { return [] }
        let ids = items(columns[0]), modes = items(columns[1]), bounds = items(columns[2]), active = items(columns[3])
        let tabIds = items(columns[4]), titles = items(columns[5]), urls = items(columns[6])
        return ids.indices.compactMap { i in
            guard i < modes.count, text(modes[i]) == "normal", i < bounds.count, i < active.count,
                  i < tabIds.count, i < titles.count, i < urls.count else { return nil }
            let keys = items(tabIds[i]).map(text)
            return window(id: text(ids[i]), bounds: bounds[i], active: active[i],
                keys: keys, titles: items(titles[i]).map(text), urls: items(urls[i]).map(text))
        }
    }

    /// Safari has no tab id, so a tab is keyed by its position and URL.
    private static func parseSafariWindow(_ entry: NSAppleEventDescriptor) -> BrowserScriptWindow? {
        let fields = items(entry)
        guard fields.count == 5 else { return nil }
        let urls = items(fields[4]).map(text)
        let keys = urls.enumerated().map { "\($0.offset + 1)|\($0.element)" }
        return window(id: text(fields[0]), bounds: fields[1], active: fields[2],
            keys: keys, titles: items(fields[3]).map(text), urls: urls)
    }

    private static func window(id: String, bounds: NSAppleEventDescriptor, active: NSAppleEventDescriptor,
                               keys: [String], titles: [String], urls: [String]) -> BrowserScriptWindow? {
        guard !id.isEmpty, let rect = rect(bounds), let activeIndex = int(active),
              keys.count == titles.count, keys.count == urls.count, !keys.contains(where: { $0.isEmpty }) else { return nil }
        let tabs = keys.indices.map { BrowserTab(key: keys[$0], title: titles[$0], url: urls[$0]) }
        return BrowserScriptWindow(scriptId: id, bounds: rect, activeTabIndex: activeIndex, tabs: tabs)
    }

    /// `{left, top, right, bottom}`, top-left global, as both dictionaries report `bounds`.
    private static func rect(_ d: NSAppleEventDescriptor) -> CGRect? {
        let edges = items(d).compactMap(int)
        guard edges.count == 4 else { return nil }
        return CGRect(x: edges[0], y: edges[1], width: edges[2] - edges[0], height: edges[3] - edges[1])
    }

    private static func items(_ d: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        guard d.descriptorType == typeAEList else { return [] }
        return (0..<d.numberOfItems).compactMap { d.atIndex($0 + 1) }
    }

    /// `cMissingValue` ('msng'), which Swift doesn't import from AERegistry.h.
    private static let missingValue = OSType(0x6D73_6E67)

    /// `missing value` arrives as `typeNull` or as the `msng` type class, and reads as "".
    private static func text(_ d: NSAppleEventDescriptor) -> String {
        guard d.descriptorType != typeNull, !(d.descriptorType == typeType && d.typeCodeValue == missingValue) else { return "" }
        return d.stringValue ?? ""
    }

    private static func int(_ d: NSAppleEventDescriptor) -> Int? {
        d.coerce(toDescriptorType: typeSInt32).map { Int($0.int32Value) }
    }
}
