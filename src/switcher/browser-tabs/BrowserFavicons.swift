import Cocoa
import ImageIO
import SQLite3

/// Site icons for browser tab rows, read from each Chromium profile's `Favicons` SQLite cache: the icon the
/// browser itself shows, with no network. Lookups run on a utility queue and land in an in-memory map that
/// `Window.icon` reads; a row falls back to the browser's icon until its site's icon lands.
///
/// **macOS may guard a browser's data folder** ("Operation not permitted", measured on Brave, not on Helium),
/// and the first touch can raise the "access data from other apps" prompt. So a browser's cache is only read
/// once Settings' "Show site icons" checked it (`checkInstalledBrowsers`), a step that follows the user's click.
enum BrowserFavicons {
    private static let queue = DispatchQueue(label: "browser-favicons", qos: .utility)
    /// Bookkeeping rather than a user preference: the bundle ids whose folder a Settings click already touched,
    /// so TCC has answered for them and reading can never be what raises a prompt.
    private static let checkedKey = "browserTabFaviconsCheckedBrowsers"
    private static var icons = [String: CGImage]()
    private static var inFlight = Set<String>()
    /// Bundle ids whose data folder macOS refused this launch. Shown in Settings.
    private(set) static var blocked = Set<String>()
    /// Queue-confined. Per bundle id: the newest cache modification date at the last read and the URLs that read
    /// didn't find, so they aren't looked up again until the browser writes its cache.
    private static var misses = [String: (stamp: Date, urls: Set<String>)]()

    static var isEnabled: Bool { Preferences.browserTabFavicons }

    static func icon(_ url: String) -> CGImage? {
        isEnabled ? icons[url] : nil
    }

    private static var checkedBrowsers: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: checkedKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: checkedKey) }
    }

    /// Looks up the icons of `urls` not known yet. One lookup per browser at a time; the next snapshot asks again.
    static func request(_ urls: [String], _ browser: SupportedBrowser) {
        guard isEnabled, checkedBrowsers.contains(browser.bundleId), !blocked.contains(browser.bundleId),
              !inFlight.contains(browser.bundleId) else { return }
        let wanted = Set(urls.filter { icons[$0] == nil && !BrowserFaviconPicker.siteRanges($0).isEmpty })
        guard !wanted.isEmpty else { return }
        inFlight.insert(browser.bundleId)
        queue.async {
            let result = read(browser, wanted)
            DispatchQueue.main.async { landed(browser, result) }
        }
    }

    private static func landed(_ browser: SupportedBrowser, _ result: (icons: [String: CGImage], blocked: Bool)) {
        inFlight.remove(browser.bundleId)
        if result.blocked { blocked.insert(browser.bundleId) }
        guard isEnabled, !result.icons.isEmpty else { return }
        icons.merge(result.icons) { _, new in new }
        App.refreshOpenUiAfterExternalEvent([])
    }

    /// Only the icons of rows still listed are kept.
    static func prune(keeping urls: Set<String>) {
        icons = icons.filter { urls.contains($0.key) }
    }

    /// Settings: touch every installed browser's data folder not touched yet, so whatever macOS asks, it asks
    /// now. Blocked ones are tried again too: once TCC has answered it doesn't ask twice, and access may have been
    /// granted in System Settings since. Then re-read the tabs so their icons land.
    static func checkInstalledBrowsers(_ done: @escaping () -> Void) {
        let checked = checkedBrowsers
        let toCheck = BrowserDialect.supported.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleId) != nil
                && (!checked.contains($0.bundleId) || blocked.contains($0.bundleId))
        }
        queue.async {
            let results = toCheck.map { ($0.bundleId, isPermissionError(listProfiles($0).error)) }
            DispatchQueue.main.async {
                for (id, isBlocked) in results {
                    checkedBrowsers.insert(id)
                    if isBlocked { blocked.insert(id) } else { blocked.remove(id) }
                }
                done()
                BrowserTabs.refreshAll()
            }
        }
    }

    static func preferenceChanged() {
        guard !isEnabled else { return }
        icons.removeAll()
        App.refreshOpenUiAfterExternalEvent([])
    }

    // MARK: - Reading (on `queue`)

    private static func read(_ browser: SupportedBrowser, _ urls: Set<String>) -> (icons: [String: CGImage], blocked: Bool) {
        let listing = listProfiles(browser)
        guard listing.error == nil else { return ([:], isPermissionError(listing.error)) }
        let stamp = listing.caches.compactMap(newestModification).max() ?? .distantPast
        if let m = misses[browser.bundleId], m.stamp == stamp, urls.isSubset(of: m.urls) { return ([:], false) }
        var found = [String: CGImage]()
        for cache in listing.caches {
            let remaining = urls.subtracting(found.keys)
            guard !remaining.isEmpty else { break }
            found.merge(readCopy(of: cache, remaining)) { old, _ in old }
        }
        misses[browser.bundleId] = (stamp, urls.subtracting(found.keys))
        Logger.debug { "browserFavicons \(browser.name) found=\(found.count)/\(urls.count)" }
        return (found, false)
    }

    private static func profileRoot(_ browser: SupportedBrowser) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(browser.dataDirectory, isDirectory: true)
    }

    /// `Default` first, then `Profile N`: tabs don't say which profile they belong to, so every one is asked.
    private static func listProfiles(_ browser: SupportedBrowser) -> (caches: [URL], error: Error?) {
        do {
            let root = profileRoot(browser)
            let profiles: [String] = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("Profile ") }.sorted()
            let caches = (["Default"] + profiles).map { root.appendingPathComponent($0).appendingPathComponent("Favicons") }
            return (caches.filter { FileManager.default.fileExists(atPath: $0.path) }, nil)
        } catch {
            return ([], error)
        }
    }

    /// A browser never launched has no folder, which is not a refusal.
    private static func isPermissionError(_ error: Error?) -> Bool {
        guard let error = error as NSError? else { return false }
        if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError { return true }
        let posix = (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code ?? (error.domain == NSPOSIXErrorDomain ? error.code : 0)
        return posix == Int(EPERM) || posix == Int(EACCES)
    }

    /// Writes can sit in the rollback journal or the WAL rather than the main file.
    private static func newestModification(_ cache: URL) -> Date? {
        ["", "-journal", "-wal"].compactMap {
            try? FileManager.default.attributesOfItem(atPath: cache.path + $0)[.modificationDate] as? Date
        }.max()
    }

    /// The browser keeps the live file open, so a copy is read: with its journal or WAL next to it, SQLite opening
    /// the copy recovers exactly what the browser had committed, and nothing touches the original.
    private static func readCopy(of cache: URL, _ urls: Set<String>) -> [String: CGImage] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("alttab-favicons-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return [:] }
        let copy = dir.appendingPathComponent("Favicons")
        for suffix in ["", "-journal", "-wal"] where FileManager.default.fileExists(atPath: cache.path + suffix) {
            try? FileManager.default.copyItem(atPath: cache.path + suffix, toPath: copy.path + suffix)
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return [:]
        }
        defer { sqlite3_close(db) }
        var imagesByIcon = [Int64: CGImage]()
        var found = [String: CGImage]()
        for url in urls {
            guard let iconId = exactIcon(db, url) ?? siteIcon(db, url) else { continue }
            if imagesByIcon[iconId] == nil { imagesByIcon[iconId] = image(db, iconId) }
            found[url] = imagesByIcon[iconId]
        }
        return found
    }

    private static func exactIcon(_ db: OpaquePointer, _ url: String) -> Int64? {
        query(db, "SELECT icon_id FROM icon_mapping WHERE page_url = ? LIMIT 1", [url]) { sqlite3_column_int64($0, 0) }.first
    }

    /// The site page closest to the root, over every range of the site.
    private static func siteIcon(_ db: OpaquePointer, _ url: String) -> Int64? {
        BrowserFaviconPicker.siteRanges(url).flatMap { range in
            query(db, "SELECT icon_id, length(page_url) FROM icon_mapping WHERE page_url >= ? AND page_url < ? ORDER BY length(page_url) LIMIT 1",
                  [range.lower, range.upper]) { (iconId: sqlite3_column_int64($0, 0), length: sqlite3_column_int64($0, 1)) }
        }.min { $0.length < $1.length }?.iconId
    }

    private static func image(_ db: OpaquePointer, _ iconId: Int64) -> CGImage? {
        let bitmaps = query(db, "SELECT id, width FROM favicon_bitmaps WHERE icon_id = ? AND length(image_data) > 0", [iconId]) {
            BrowserFaviconPicker.Bitmap(id: sqlite3_column_int64($0, 0), width: Int(sqlite3_column_int($0, 1)))
        }
        guard let bitmapId = BrowserFaviconPicker.bestBitmap(bitmaps) else { return nil }
        let data = query(db, "SELECT image_data FROM favicon_bitmaps WHERE id = ?", [bitmapId]) { statement -> Data? in
            guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        }.first ?? nil
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func query<T>(_ db: OpaquePointer, _ sql: String, _ args: [Any], _ row: (OpaquePointer) -> T) -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, arg) in args.enumerated() {
            if let s = arg as? String { sqlite3_bind_text(statement, Int32(i + 1), s, -1, transient) }
            if let n = arg as? Int64 { sqlite3_bind_int64(statement, Int32(i + 1), n) }
        }
        var rows = [T]()
        while sqlite3_step(statement) == SQLITE_ROW { rows.append(row(statement)) }
        return rows
    }
}
