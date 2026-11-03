import Cocoa

/// Settings → Browser tabs: one row per installed supported browser, with its Automation access and the one
/// button allowed to trigger the macOS prompt. Listing tabs is turned on per shortcut ("Browser tabs"). Below it,
/// "Show site icons", the one place that touches the browsers' icon caches for the first time (`BrowserFavicons`).
class BrowserTabsTab: NSObject {
    private static var shared: BrowserTabsTab?
    private static let automationSettingsUrl = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    private static let fullDiskAccessUrl = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    private var rows = [(browser: SupportedBrowser, status: NSTextField, button: NSButton)]()
    private let showIcons = NSButton(checkboxWithTitle: "Show site icons", target: nil, action: nil)
    private let blockedHint = NSTextField(wrappingLabelWithString: "")
    private let openFullDiskAccess = NSButton(title: "Open Full Disk Access…", target: nil, action: nil)

    static func initTab() -> NSView {
        let tab = BrowserTabsTab()
        shared = tab
        return tab.makeView()
    }

    static func cleanup() {
        shared = nil
    }

    private func makeView() -> NSView {
        let table = TableGroupView(width: SettingsWindow.contentWidth)
        let installed = BrowserDialect.supported.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleId) != nil }
        for browser in installed {
            let status = NSTextField(labelWithString: "")
            status.textColor = .secondaryLabelColor
            let button = NSButton(title: "Grant access…", target: self, action: #selector(grantClicked(_:)))
            button.tag = rows.count
            rows.append((browser, status, button))
            table.addRow(TableGroupView.Row(leftTitle: browser.name, rightViews: [status, button]))
        }
        if installed.isEmpty { table.addRow(leftText: "No supported browser (Helium, Brave) is installed.") }
        let hint = NSTextField(wrappingLabelWithString: "Turn on \"Browser tabs\" for a shortcut in Controls to list the tabs of these browsers. A browser has to be running to be granted access. Incognito windows are never read.")
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = SettingsWindow.contentWidth - TableGroupSetView.leftRightPadding
        refresh()
        BrowserTabs.checkAccess { [weak self] in self?.refresh() }
        if Preferences.browserTabFavicons { BrowserFavicons.checkInstalledBrowsers { [weak self] in self?.refresh() } }
        return TableGroupSetView(originalViews: [table, hint, makeIconsTable()], padding: 0, bottomPadding: 0)
    }

    /// Icons come from each browser's own cache on disk. macOS guards some browsers' data folders, so ticking
    /// the box may raise its "access data from other apps" prompt; refusing it leaves that browser's icon.
    private func makeIconsTable() -> NSView {
        showIcons.state = Preferences.browserTabFavicons ? .on : .off
        showIcons.target = self
        showIcons.action = #selector(showIconsChanged)
        openFullDiskAccess.target = self
        openFullDiskAccess.action = #selector(openFullDiskAccessClicked)
        blockedHint.textColor = .secondaryLabelColor
        blockedHint.preferredMaxLayoutWidth = SettingsWindow.contentWidth - 200
        let table = TableGroupView(width: SettingsWindow.contentWidth)
        table.addRow(TableGroupView.Row(leftTitle: "Tab icons", subTitle: "Read from each browser's icon cache, never from the network.", rightViews: [showIcons]))
        table.addRow(TableGroupView.Row(leftTitle: "", rightViews: [blockedHint, openFullDiskAccess]))
        return table
    }

    @objc private func showIconsChanged() {
        Preferences.set("browserTabFavicons", String(showIcons.state == .on))
        guard showIcons.state == .on else { return refresh() }
        BrowserFavicons.checkInstalledBrowsers { [weak self] in self?.refresh() }
    }

    @objc private func openFullDiskAccessClicked() {
        NSWorkspace.shared.open(Self.fullDiskAccessUrl)
    }

    private func refresh() {
        let running = Set(Applications.list.compactMap { $0.bundleIdentifier })
        for row in rows {
            let access = BrowserTabs.access[row.browser.bundleId] ?? .unknown
            let isRunning = running.contains(row.browser.bundleId)
            row.status.stringValue = Self.label(access, isRunning: isRunning)
            row.button.title = access == .denied ? "Open System Settings…" : "Grant access…"
            row.button.isEnabled = access == .denied || (access != .allowed && isRunning)
        }
        refreshIconsStatus()
    }

    private func refreshIconsStatus() {
        let blocked = rows.map { $0.browser }.filter { BrowserFavicons.blocked.contains($0.bundleId) }.map { $0.name }
        let shown = Preferences.browserTabFavicons && !blocked.isEmpty
        blockedHint.stringValue = shown ? "macOS blocks reading \(blocked.joined(separator: " and "))'s icons. Allow AltTab in Full Disk Access, then open this page again." : ""
        blockedHint.isHidden = !shown
        openFullDiskAccess.isHidden = !shown
    }

    private static func label(_ access: BrowserAccess, isRunning: Bool) -> String {
        switch access {
        case .allowed: return "Allowed"
        case .denied: return "Denied"
        case .notAsked: return "Not asked"
        case .unknown: return isRunning ? "Unknown" : "Not running"
        }
    }

    /// "Denied" can only be undone in System Settings; TCC doesn't prompt twice.
    @objc private func grantClicked(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag) else { return }
        let browser = rows[sender.tag].browser
        if BrowserTabs.access[browser.bundleId] == .denied {
            NSWorkspace.shared.open(Self.automationSettingsUrl)
            return
        }
        BrowserTabs.checkAccess(ask: browser.bundleId) { [weak self] in self?.refresh() }
    }
}
