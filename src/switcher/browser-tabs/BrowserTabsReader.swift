import Cocoa
import Carbon

/// Automation access to one browser, as TCC reports it. Never asked for except by Settings' "Grant access…".
enum BrowserAccess: Equatable {
    case allowed
    case notAsked
    case denied
    /// The browser isn't running, so TCC can't be asked about it.
    case unknown
}

/// The only code that talks to browsers. Every Apple Event is a cross-process call that can block for seconds,
/// so everything here runs on one serial queue, never on main.
///
/// `NSAppleScript` is listed main-thread-only in Apple's thread-safety summary, but the AppleScript component
/// has been usable off-main since 10.6 provided one instance is never used from two threads at once; the serial
/// queue is what guarantees that, and nothing else touches `scripts`.
enum BrowserTabsReader {
    static let queue = DispatchQueue(label: "browser-tabs", qos: .userInitiated)
    private static var scripts = [String: NSAppleScript]()

    /// Checks access without ever prompting. `ask` is true only from Settings' button, the one place the macOS
    /// prompt may appear. The browser must be running: TCC can't evaluate a target that isn't.
    static func access(_ bundleId: String, ask: Bool = false) -> BrowserAccess {
        dispatchPrecondition(condition: .onQueue(queue))
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleId)
        guard let desc = target.aeDesc else { return .unknown }
        switch AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask) {
        case noErr: return .allowed
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .unknown
        }
    }

    /// nil when the read failed (timeout, browser quitting, access revoked mid-read).
    static func read(_ browser: SupportedBrowser) -> [BrowserScriptWindow]? {
        let start = DispatchTime.now().uptimeNanoseconds
        guard let reply = call(browser, "readTabs", []) else { return nil }
        let windows = BrowserTabReplyParser.parse(reply, dialect: browser.dialect)
        Logger.debug { "browserTabs read \(browser.name) windows=\(windows.count) tabs=\(windows.reduce(0) { $0 + $1.tabs.count }) in \((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)ms" }
        return windows
    }

    /// Switches (`activateTab`) or closes (`closeTab`) one tab. Returns whether the handler succeeded.
    static func act(_ handler: String, _ browser: SupportedBrowser, _ ref: BrowserTabRef, raiseWindow: Bool = false) -> Bool {
        let args = [NSAppleEventDescriptor(string: ref.scriptWindowId), NSAppleEventDescriptor(string: ref.tab.key),
                    NSAppleEventDescriptor(int32: Int32(ref.stripIndex)), NSAppleEventDescriptor(string: ref.tab.url),
                    NSAppleEventDescriptor(boolean: raiseWindow)]
        return call(browser, handler, args) != nil
    }

    /// Calls a handler of the browser's compiled script with a subroutine event. Handler names go lowercase:
    /// that is how AppleScript stores them.
    private static func call(_ browser: SupportedBrowser, _ handler: String, _ args: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor? {
        dispatchPrecondition(condition: .onQueue(queue))
        // `tell application id` launches a browser that isn't running, and a quit can land between the
        // caller's check and here. `NSRunningApplication` is thread safe.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleId).isEmpty,
              let script = compiled(browser) else { return nil }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: .currentProcess(), returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setDescriptor(NSAppleEventDescriptor(string: handler.lowercased()), forKeyword: AEKeyword(keyASSubroutineName))
        let list = NSAppleEventDescriptor.list()
        for arg in args { list.insert(arg, at: list.numberOfItems + 1) }
        event.setDescriptor(list, forKeyword: keyDirectObject)
        var error: NSDictionary?
        let reply = script.executeAppleEvent(event, error: &error)
        if let error { Logger.debug { "browserTabs \(browser.name) \(handler) failed: \(error)" } }
        return error == nil ? reply : nil
    }

    /// Compiled once per browser, on first use. Compiling resolves the dictionary from the app bundle; callers
    /// only get here for a running browser, so it never launches one.
    private static func compiled(_ browser: SupportedBrowser) -> NSAppleScript? {
        if let script = scripts[browser.bundleId] { return script }
        guard let script = NSAppleScript(source: browser.dialect.scriptSource(bundleId: browser.bundleId)) else { return nil }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else {
            Logger.error { "browserTabs \(browser.name) script didn't compile: \(error ?? [:])" }
            return nil
        }
        scripts[browser.bundleId] = script
        return script
    }
}
