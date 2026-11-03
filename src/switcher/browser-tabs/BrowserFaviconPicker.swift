import Foundation

/// The pure half of reading a tab's icon from a Chromium browser's `Favicons` cache (`BrowserFavicons`).
///
/// The cache maps page URLs to icons (`icon_mapping`) and stores each icon at one or more sizes
/// (`favicon_bitmaps`, typically 16 and 32 px). A tab's icon is the one mapped to its exact URL, or else the one
/// mapped to the page of the same site closest to its root, since a page the browser hasn't cached yet usually
/// shares its site's icon.
enum BrowserFaviconPicker {
    struct Bitmap: Equatable {
        let id: Int64
        let width: Int
    }

    /// Tile icons are drawn at about 32 pt on a 2x screen. Chromium rarely keeps anything larger than 32 px.
    static let preferredWidth = 64

    /// The smallest bitmap at least `preferredWidth` wide, else the largest one.
    static func bestBitmap(_ bitmaps: [Bitmap], preferredWidth: Int = preferredWidth) -> Int64? {
        let largeEnough = bitmaps.filter { $0.width >= preferredWidth }
        if let best = largeEnough.min(by: { $0.width < $1.width }) { return best.id }
        return bitmaps.max { $0.width < $1.width }?.id
    }

    /// Key ranges `[lower, upper)` covering every cached page of `url`'s site, over both schemes and with or
    /// without "www.". Ranges rather than `LIKE`, so the lookup uses `icon_mapping`'s index on `page_url`.
    /// Empty for anything that isn't an http(s) URL with a host (`chrome://`, `about:blank`, files).
    static func siteRanges(_ url: String) -> [(lower: String, upper: String)] {
        guard let components = URLComponents(string: url), let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = components.host?.lowercased(), !host.isEmpty else { return [] }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return ["https", "http"].flatMap { s in [bare, "www." + bare].map { h -> (String, String) in
            let prefix = "\(s)://\(h)/"
            return (prefix, upperBound(prefix))
        } }
    }

    /// The first string after every string starting with `prefix`: its last character, incremented.
    static func upperBound(_ prefix: String) -> String {
        guard let last = prefix.unicodeScalars.last, let next = Unicode.Scalar(last.value + 1) else { return prefix + "\u{10FFFF}" }
        return String(prefix.unicodeScalars.dropLast()) + String(next)
    }
}
