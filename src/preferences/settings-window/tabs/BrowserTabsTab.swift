import Cocoa

/// Settings → Browser tabs: one row per installed supported browser, with its Automation access and the one
/// button allowed to trigger the macOS prompt. Listing tabs is turned on per shortcut ("Browser tabs").
class BrowserTabsTab: NSObject {
    private static var shared: BrowserTabsTab?
    private static let automationSettingsUrl = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    private var rows = [(browser: SupportedBrowser, status: NSTextField, button: NSButton)]()

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
        return TableGroupSetView(originalViews: [table, hint], padding: 0, bottomPadding: 0)
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
