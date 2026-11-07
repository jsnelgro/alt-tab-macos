# Browser tabs in the switcher list

Status: implemented for Helium and Brave (`src/switcher/browser-tabs/`). Safari's script and parser exist, but
Safari is left out of `BrowserDialect.supported` until a reliable private-window signal is found (see "Private
windows in Safari"). Both installed dictionaries declare window and tab `id` as **text**, not integer, so ids
are `String` throughout and the scripts compare them `as text`. Read durations (step 1) are logged at debug
level (`browserTabs read …`) but not yet measured.

This document is for an engineer who knows Swift and AppKit but has never seen this codebase. Part 1 explains
the feature. Part 2 explains the parts of the codebase it touches. Part 3 compares the ways to build it and
gives the design. Part 4 is the step-by-step plan.

---

# Part 1: The feature

## Background: AltTab and the Titles style

AltTab is a macOS window switcher. While the user holds a shortcut (⌥⇥ by default), a panel shows every open
window. Each press of ⇥ moves the highlight, and releasing ⌥ focuses the highlighted window. The user can also
type to search the list.

This repository is a personal fork with one user:

- Only the **Titles** style matters (one full-width row per window: app icon and title). Ignore Thumbnails and
  App Icons.
- Only the Debug build matters.
- Pro/licensing gating is irrelevant. Ignore any `Pro…` checks.
- Localization is not needed. English strings are fine.
- Keep it simple and low-maintenance. Prefer built-in Apple components over custom machinery.
- **Browsers in scope: Helium and Brave** (both Chromium-based, used daily), and **Safari** (used rarely, so
  lower priority). Other browsers aren't needed.
- **Incognito and private windows are out of scope.** Their tabs are never listed.

## Goal

Today a browser window is one row, titled after its **active** tab. Its other tabs are invisible to AltTab, so
"jump to the GitHub tab" means switching to the browser and then hunting through the tab strip.

Add the browser's **tabs** to the list as rows of their own. They can be selected, searched, grouped and
focused like any window:

```
 ▸ Pull request #12 — GitHub              ← the Helium window
 ▸ Pull request #12 — GitHub              ← its tabs, in tab-strip order (the active one too)
 ▸ Inbox (3) — Gmail
 ▸ Swift Forums
 ▸ Project Alpha — Xcode
 ▸ Apple Developer Documentation          ← a Brave window
 ▸ Hacker News
```

The list stays flat. Tab rows look like any other row. Structure comes from matching groups, for example a
"Tabs" section:

```
 BROWSERS
   ▸ Pull request #12 — GitHub
   ▸ Apple Developer Documentation
 TABS
   ▸ Inbox (3) — Gmail
   ▸ Swift Forums
   ▸ Hacker News
 OTHER
   ▸ Project Alpha — Xcode
```

Selecting a tab row and releasing ⌥ switches the browser to that tab and focuses its window.

This is what [Supasidebar](https://supasidebar.com) does in its "Live Tabs" list and its tab search: a native
app (not a browser extension) reads every running browser's tabs through macOS **Automation** (Apple Events /
AppleScript), and needs one Automation permission per browser.

### "Tabs from other apps"

There are three kinds of "tabs" on macOS. Only one of them needs new work:

| Kind | Examples | Status |
| --- | --- | --- |
| **Native window tabs** (`NSWindow` tabbing, "Merge All Windows") | Finder, Terminal, TextEdit, Preview, Xcode windows | **Already supported.** Each tab is a real window to the WindowServer. AltTab tracks them (`TabGroups`, `TabGroupResolver`), and the per-shortcut setting `showTabsAsWindows` lists them as separate rows. This is the "Apple API" for app tabs. Nothing to build. |
| **Browser tabs** | Helium, Brave, Safari | Not windows: one window draws many tabs. **This feature.** |
| **Custom in-app tabs** | VS Code editor tabs, iTerm2, Slack channels | Not windows, and there is no common API. Some expose an `AXTabGroup` to Accessibility. A generic Accessibility reader is a possible later phase (Part 3, Phase 3). |

## Exact behavior

1. **Per-shortcut switch.** A new per-shortcut setting, "Browser tabs" (Hide / Show), default Hide. Tabs are
   read only while at least one shortcut shows them.
2. **Every tab gets a row, and the window keeps its own.** A browser window stays exactly as it is today, so
   focus order, the hidden/minimized/fullscreen filters and focusing all keep working unchanged. Each tab, the
   active one included, gets one extra row with its own title and site icon. (An earlier version let the window
   row stand for the active tab, but that row shows the browser's window title, which can be a custom window
   name, and the browser icon.)
3. **Flat rows, ordered by their window.** Tab rows are drawn exactly like window rows, with no indentation
   or tree. Matching groups are the only source of structure in the list. A tab row sorts as if it were its
   window, then by tab-strip position, so a window's tabs sit right after it when they're in the same section,
   and in a predictable order when they're in a different one. The window's own position is unchanged (most
   recently used, by default).
4. **Tabs inherit their window's visibility.** A tab row is shown exactly when its window's row would be shown.
   If the window is filtered out (another Space, minimized and hidden by the shortcut, an excluded app, "one
   window per app" mode), its tabs are hidden too.
5. **Search** matches tab rows by title (and later by URL), and ranks them against windows by relevance like
   any row. While searching, tabs are not kept next to their window.
6. **Matching groups** see tab rows like windows, with two extra facts, `url` and `kind` (`"window"` / `"tab"`).
   With them a user can build sections such as "Tabs" (`kind == "tab"`) or "GitHub" (`url CONTAINS
   "github.com"`). A tab row's section is decided by its own facts, not its window's, so a tab can be in a
   different section from its window. The ordering rule (3) applies within each section.
7. **A quick ⌥⇥ still returns to the previous window.** Tab rows are never the default selection, even though
   the current window's tabs now sit between it and the previous window.
8. **Focusing a tab row** switches the browser to that tab, then focuses its window with the existing focus
   path.
9. **Actions on a tab row.** Close (W) closes **that tab**. Minimize, fullscreen, hide and quit act on the
   parent window or app, as they would on the window row.
10. **No surprise prompts.** AltTab never triggers a macOS permission prompt while the switcher is open. A
    browser AltTab has no Automation permission for is skipped silently. Settings shows which browsers are
    allowed and has a "Grant access…" button for each.
11. **Never launch a browser.** Only running browsers are queried.
12. **No incognito or private tabs.** Tabs of incognito (Helium, Brave) and private (Safari) windows are never
    read into rows. The window itself still appears as a normal window row, as it does today.
13. **Showing the switcher never waits for a browser.** The list is drawn at once from the last known tabs, and
    is corrected in place when a fresh read lands.

## Non-goals (for now)

- Favicons over the network. The scripting interfaces don't expose icons, so they're read instead from each
  Chromium profile's own `Favicons` cache, opt-in (Settings → Browser tabs → "Show site icons"). See
  `BrowserFaviconPickerSpecs.md`. Tab rows fall back to the browser's app icon.
- Ordering tabs by when they were last used. See "Tab recency" in Part 3.
- Thumbnails and App Icons styles.
- Browser extensions.
- Incognito and private windows' tabs.
- Browsers other than Helium, Brave and Safari. Other Chromium browsers (Chrome, Edge, Vivaldi) would only need
  a bundle id added to the table, but they aren't tested. Firefox has no tab scripting at all (see A2/Phase 3).
- Custom in-app tabs (VS Code, …), until Phase 3.

---

# Part 2: The parts of the codebase you need

## Conventions (from `AGENTS.md`, read it)

- Pure Swift 5.8 and AppKit, built in code. No SwiftUI, no Interface Builder.
- Keep code compact, use `guard` for early exits, and split long methods into small helpers instead of adding
  inline comments.
- Logic lives in pure **kernels**: enums with static functions that take plain data and return plain data, with
  no AppKit and no globals. AppKit classes call into them.
- Kernels follow the **triad** pattern: `Foo.swift`, `FooSpecs.md` (behavior and a list of test scenarios) and
  `FooTests.swift` (XCTest, one test per scenario), all in the same folder.
- **Latency matters most.** Nothing that can stall may run on the main thread before the work the user is
  waiting for. Use observers, not polling. `src/main-thread-ipc.md` explains which cross-process calls are
  allowed where. An Apple Event to a browser is a cross-process call that can block for seconds. It must
  never run on the main thread.
- To build, run `ai/build.sh`. To run the unit tests, run `ai/test.sh`. Don't use `scripts/run_tests.sh`.
- **The `unit-tests` target has its own source list** in `alt-tab-macos.xcodeproj`, and it does not build the
  app target. Every new kernel file, and every file a test references, must be added to **both** targets.

## The two jobs of `Windows.list`

This is the most important fact for this feature.

`Windows.list: [Window]` (`src/switcher/state/Windows.swift`) has two jobs:

1. **It is the switcher's display list.** `TilesView.recycledViews[i]` draws `Windows.list[i]` (same index),
   and selection, hover, cycling, search, sorting and every window action index into it.
2. **It is the window-tracking model.** A pure reducer (`WindowEventReducer`, state type `TrackedWindowState`)
   turns OS events into changes to that model. `TrackedWindowStateBridge.snapshot()` copies **every** entry of
   `Windows.list` into the reducer's state, and `apply()` writes the results back by `id`. The ranks in
   `lastFocusOrder` are a shared numbering across the whole list. `Windows.removeWindows` even uses
   `lastFocusOrder` to decide which entries to remove.

There is already one kind of entry that isn't a real window: the **windowless-app placeholder**
(`Window.init(_ application:)`, `id = "pid-N"`, `cgWindowId == nil`, `isWindowlessApp == true`), which shows an
app that has no windows. It is a model entry: it holds an MRU slot, and the reducer manages it.

A tab row must be an entry for job 1 and **invisible** to job 2. Part 3 is mostly about how to achieve that.

## How a switcher frame is built

```
user presses the shortcut                       (App.showUiOrCycleSelection)
        │
        ▼
Windows.updatesBeforeShowing()                  (src/switcher/state/Windows.swift)
  • window.shouldShowTheUser = WindowFilterResolver.shouldShow(...) for every window
  • refreshWhichWindowsToShowTheUser()          ("one window per app" mode)
  • sort()
        │
        ▼
Windows.sort()
  • builds one OrderWindow per entry (WindowState + ApplicationState + search score + matching-group rank)
  • sorts Windows.list in place with WindowOrderResolver.isOrderedBefore   ← pure kernel
  • applyUngroupedPositions: the order without matching groups, used by the default selection
        │
        ▼
TilesView.layoutTileViews / fillTiles           (src/switcher/main-window/TilesView.swift)
  • for each index: Windows.shouldDisplay(w) ? TileView.updateRecycledCellWithNewContent(w, …) : frame = .zero
  • TileGridLayout.compute places the tiles     ← pure kernel
        │
        ▼
Selection                                       (SelectionResolver, pure kernel; inputs built in Windows.swift)
  • default pick = "the second visible row", judged in the ungrouped order
        │
        ▼
user releases ⌥ → App.focusTarget() → App.focusSelectedWindow(w) → beginHideUi → w.focus(onFronted)
```

Other places that matter:

- `Window.focus(_:)` (`src/switcher/state/Window.swift`) is the one place that brings a window forward. For a
  real window it runs a careful sequence off the main thread (front the process, make the window key, raise
  it, repair the origin Space). Reuse it. Don't write another one.
- `Window.close()`, `minDemin()`, `toggleFullscreen()` are the tile actions, called through
  `ShortcutAction.onSelectedWindow` (`src/switcher/ShortcutAction.swift`).
- `Search.matches` / `Search.relevance` (`src/switcher/Search.swift`) match `window.title` and the app name.
- `TileView.updateValues` (`src/switcher/main-window/TileView.swift`) fills a row from a `Window`.
- `App.refreshOpenUiAfterExternalEvent([])` is how background work asks for an open switcher to be redrawn.
  It re-runs `updatesBeforeShowing()` and the layout, coalesced.
- `MatchingGroupFacts.of(_:_:)` builds the dictionary the matching-group predicates are evaluated against.
- `Throttler` (used throughout `Applications.swift`) coalesces bursts of events.

## Preferences

Same system as matching groups (see that doc's "Preferences" section). Per-shortcut settings are one key per
shortcut (`windowOrder`, `windowOrder2`, …), registered in the `(0...maxShortcutCount)` loop in
`Preferences.swift`, with a `MacroPreference` enum in `MacroPreferences.swift`, and a `ShortcutBoundDropdown`
row in `ShortcutEditor.swift`.

**Naming collision to avoid:** "tab" already means native window tabs here: `showTabsAsWindows`,
`GroupTabsPreference`, `TabGroup`, `TabGroups`, `TabGroupResolver`, `TabReadPolicy`, `isTabbed`. Every identifier
in this feature uses the **`BrowserTab`** prefix, so the two meanings never mix.

## Signing, entitlements, Info.plist

- `config/base.xcconfig` sets `ENABLE_HARDENED_RUNTIME = YES`. A hardened app **cannot send Apple Events at
  all** unless it has the `com.apple.security.automation.apple-events` entitlement. Without it, every send
  fails with `errAEEventNotPermitted` (-1743) and no prompt is ever shown.
- `alt_tab_macos.entitlements` doesn't have that entitlement today. `Info.plist` has no
  `NSAppleEventsUsageDescription`, which is the text macOS shows in the Automation prompt.
- The Debug build is signed with a stable local identity ("Local Self-Signed"), so an Automation grant survives
  rebuilds, like the Accessibility grant does. To test the prompt again:
  `tccutil reset AppleEvents com.lwouis.alt-tab-macos`.

---

# Part 3: Design

There are two independent questions:

- **A. How do we read and control a browser's tabs?**
- **B. How does a tab become a row in the switcher?**

## A. Reading tabs: the options

### A1. Automation: Apple Events / AppleScript (recommended)

Safari and every Chromium browser publish a scripting dictionary with windows, tabs, titles, URLs and the
active tab, and commands to switch and close tabs. Supasidebar works this way.

- ✅ Gives **URLs** and, for Chromium, **stable tab ids**.
- ✅ Gives the active tab of each window, and a way to switch to any tab.
- ✅ One read per browser returns every window and tab in a few Apple Events. It is cheap.
- ✅ Covers every browser in scope with two "dialects": Chromium (Helium and Brave share Chrome's dictionary)
  and Safari.
- ❌ Needs one Automation permission per browser, plus the entitlement and usage string.
- ❌ **Firefox has no tab scripting.** It can't be covered this way. Firefox is out of scope, so this doesn't
  matter here.
- ❌ The browser's window id is not a `CGWindowID` (at least in Chromium), so script windows have to be
  matched to AltTab's windows (see "Matching script windows to AltTab windows").
- ❌ No change notifications, so we have to decide when to re-read (see "Freshness").

### A2. Accessibility (AX) tree

Read each browser window's AX tree, find the `AXTabGroup` that holds the tab strip, and read its
`AXRadioButton` children. Switch tabs with `AXPress`.

- ✅ No new permission: AltTab already has Accessibility.
- ✅ The parent window is known for free: AltTab already holds each window's `AXUIElement`.
- ✅ Could cover Firefox and some non-browser apps with tab bars (neither is in scope).
- ❌ **No URLs** and no stable tab ids. A tab is identified by its title and position only.
- ❌ **Expensive.** `TabReadPolicy.swift` documents that walking children costs one cross-process round trip per
  element, and that this was the most expensive thing AltTab did per show. A browser's tab strip is many
  levels deep, so finding it costs more than the native-tab read that already had to be rationed.
- ❌ Fragile: the tree layout is an internal detail of each browser and changes between versions. Arc's
  sidebar and Chrome's vertical tabs aren't an `AXTabGroup` at all.

### A3. Browser extension + native messaging

A WebExtension in each browser pushes tab events to AltTab through a native-messaging host.

- ✅ Real-time events (`tabs.onActivated`, …), `lastAccessed` for true tab recency, favicons, and Firefox.
- ❌ An extension to build, install and maintain per browser family, a native-messaging host manifest, an IPC
  channel into AltTab, and a Safari Web Extension that needs its own app extension target. That's a lot to
  maintain for a personal fork.

### A4. Reading the browsers' session files

Chrome's `Current Session` (SNSS format) and Safari's `LastSession.plist`.

- ❌ Undocumented binary formats, written lazily (stale by seconds to minutes), and no way to switch tabs. Safari's
  files are behind Full Disk Access. Rejected.

### Choice

**A1 (Automation).** All three browsers in scope support it. One Chromium script covers Helium and Brave, which
are the browsers used daily, and Safari only needs a second, small script. A1 gives the most data (URLs, ids,
active tab, incognito flag) for the least code and runtime cost, and is proven by Supasidebar. A2's main
advantage (no permission prompt) doesn't outweigh its cost and fragility. It stays only as a possible Phase 3
for non-browser apps. A3 would be the upgrade path if true tab recency ever matters more than simplicity.

## B. Getting tab rows into the list: the options

### B1. Tab rows are `Window` objects in `Windows.list`, hidden from the model (recommended)

Add a new kind of `Window`, a **tab row**, that carries a `BrowserTabRef` and no `cgWindowId`. It sits in
`Windows.list` next to the real windows, so everything on the display side (tiles, selection, search, sorting,
matching groups, layout, hover, the tile pool) works with no change. The model side is changed in a few known
places so it never sees tab rows: the reducer snapshot, the windowless-placeholder logic, and `removeWindows`
(listed in "Keeping tab rows out of the model").

- ✅ Small change to the display side, and the UI keeps a single list and a single index space.
- ✅ The model-side guards are a short, auditable checklist (~8 sites), most of them one-line filters.
- ✅ Small footprint in upstream files, so merging upstream releases into the fork stays easy.
- ❌ It goes against the grain of `Window`, which is a heavy class built around a tracked window. A missed guard
  could let the model act on a tab row. The checklist and a debug assertion in the bridge (below) cover this.

### B2. A `SwitcherItem` abstraction

Split the two jobs of `Windows.list`. The model keeps `[Window]`. The switcher displays `[SwitcherItem]`, an
enum `{ case window(Window), case browserTab(BrowserTabRow) }`, and every display-side API takes a
`SwitcherItem`.

- ✅ The cleanest separation, and the type system enforces it.
- ❌ A large refactor: about 40 display-side call sites in `Windows.swift`, `TilesView.swift`, `TileView.swift`,
  `Search.swift`, `App.swift`, `ShortcutAction.swift`, `CliEvents.swift` and others, many in the busiest
  upstream files. Every upstream release would then conflict.
- ❌ Many of the 40 sites would just unwrap `.window` again, because most of the switcher only needs a title, an
  icon and a `focus()`.

### B3. A separate tabs list or panel

Show tabs in their own panel or a dedicated "tabs only" shortcut, with their own data source.

- ✅ No interaction with the window model at all.
- ❌ Duplicates the panel, search, selection and layout, or still needs B1/B2 to reuse them. It also misses
  the point, which is one list where a tab and a window compete on equal terms.

### Choice

**B1.** It delivers the feature with the least code and the smallest footprint in upstream files. Its one real
risk, a model path touching a tab row, is limited to a short list of sites that can each be checked, and a
debug assertion catches anything missed. B2 is the right move if tab rows ever need behavior that diverges
from `Window` a lot (for example, many kinds of non-window rows). B1 doesn't block moving to B2 later.

## Architecture

```
                      triggers (events, summon)
                                │
                                ▼
 ┌──────────────────────── BrowserTabs (main thread) ──────────────────────────┐
 │  cache: [pid: BrowserSnapshot]                                              │
 │  refresh(pid) ──▶ BrowserTabsReader (serial background queue) ──┐           │
 │                   • permission check, never prompts             │           │
 │                   • runs the dialect's compiled script          │           │
 │                   • parses the reply → BrowserSnapshot          │           │
 │  ◀──────────────────────── main.async ──────────────────────────┘           │
 │  BrowserWindowMatcher   (kernel) script windows → tracked wids              │
 │  BrowserTabRowsDiff     (kernel) old rows vs snapshot → keep/insert/remove  │
 │  apply to Windows.list, then App.refreshOpenUiAfterExternalEvent([])        │
 │  activate(row, then:) / close(row) ──▶ BrowserTabsReader                    │
 └─────────────────────────────────────────────────────────────────────────────┘
```

New folder: `src/switcher/browser-tabs/`.

| File | Kind | Purpose |
| --- | --- | --- |
| `BrowserTab.swift` | model | The plain value types below. |
| `BrowserDialect.swift` | model | Bundle id → dialect, and each dialect's script source. |
| `BrowserTabsReader.swift` | IO | The serial Apple Events queue: permission check, run handler, parse reply. |
| `BrowserTabs.swift` | coordinator | Main-thread cache, triggers, applying rows to `Windows.list`, activate/close. |
| `BrowserWindowMatcher.swift` (+ Specs, Tests) | kernel | Matches script windows to tracked windows. |
| `BrowserTabRowsDiff.swift` (+ Specs, Tests) | kernel | Reconciles existing tab rows with a fresh snapshot. |
| `BrowserTabReplyParser.swift` (+ Specs, Tests) | kernel | `NSAppleEventDescriptor` → snapshot. Testable by building descriptors in the test. |

## Data model

```swift
enum BrowserDialect { case chromium, safari }   // later: .arc, .accessibility

struct BrowserTab: Equatable {
    /// Identity across reads. Chromium: the tab's `id`. Safari has no tab id: "index|URL".
    let key: String
    let title: String
    let url: String
}

struct BrowserScriptWindow: Equatable {
    /// The browser's own window id (Chromium), or its scripting `id` (Safari). Not a CGWindowID in Chromium.
    let scriptId: Int
    /// Top-left global coordinates, like `Window.position`/`size`.
    let bounds: CGRect
    /// 1-based, as the dictionaries count.
    let activeTabIndex: Int
    let tabs: [BrowserTab]
}

struct BrowserSnapshot: Equatable {
    let pid: pid_t
    let dialect: BrowserDialect
    let windows: [BrowserScriptWindow]
}

/// What a tab row carries. `parentWid` is looked up in `Windows.byWindowId` when needed, never held strongly.
struct BrowserTabRef: Equatable {
    let parentWid: CGWindowID
    let scriptWindowId: Int
    let dialect: BrowserDialect
    let tab: BrowserTab
    /// 1-based position in the tab strip, skipping the active tab: the order tab rows follow their window in.
    let slot: Int
}
```

On `Window`:

```swift
/// Non-nil exactly for a browser tab row. A tab row is display-only: the model never sees it.
var browserTab: BrowserTabRef?

/// A display-only row for a browser's background tab.
init(browserTab ref: BrowserTabRef, parent: Window)
```

The new init:

- sets `tracked = TrackedWindow(id: "btab-\(parent.application.pid)-\(ref.scriptWindowId)-\(ref.tab.key)", wid: nil, pid: …)`;
- sets `application = parent.application` and `title = WindowTitle.singleLine(ref.tab.title)`;
- sets `lastFocusOrder = Int.max`, so it never collides with a real MRU rank;
- does **not** call `removeWindowlessAppWindow`, `ensureAxUiElement`, `checkIfFocused` or
  `mirrorAxElementForDestroyMatching`. Those are model behaviors. It does call `application.fetchAppIcon()`.

The id prefix `btab-` keeps tab-row ids apart from `wid-N` and `pid-N`. Selection follows rows by id
(`SwitcherSession.selectedTarget`), so a tab row keeps its selection across re-reads as long as its key is
stable.

## Supported browsers

| Browser | Bundle id | Dialect | Priority |
| --- | --- | --- | --- |
| Helium | `net.imput.helium` | chromium | daily use |
| Brave | `com.brave.Browser` | chromium | daily use |
| Safari | `com.apple.Safari` | safari | rare use, last in the plan |

The table is one dictionary literal in `BrowserDialect.swift`, so adding another Chromium browser later is a
one-line change.

- **Helium** is Chromium-based and keeps Chromium's AppleScript dictionary, including the stable tab `id`
  (the Raycast Helium extension relies on both). Recent Helium builds also add a `select` command on tabs,
  which focuses the tab and moves to its window's Space. It is Helium-only, so this design doesn't depend on
  it: `activateTab` uses `active tab index`, which every Chromium browser has, and AltTab's own
  `Window.focus()` handles Spaces.
- **Verify each dialect against the installed browser's dictionary before relying on it.** Open it in Script
  Editor → File → Open Dictionary, and run the read script from Script Editor once. Confirm the bundle ids
  with `osascript -e 'id of app "Helium"'`.

## Reading tabs

### Scripts, compiled once, called as handlers

Each dialect is one AppleScript source with three handlers. It is compiled once (`NSAppleScript(source:)` +
`compileAndReturnError`), and handlers are called with `executeAppleEvent(_:error:)` and a subroutine event
(`kASAppleScriptSuite`/`kASSubroutineEvent`, handler name in `keyASSubroutineName`, arguments as a list
descriptor in `keyDirectObject`). Arguments are passed as descriptors, never pasted into the source, so a tab
URL or title can never break or inject into the script. The target app is chosen with `tell application id
<bundleId>`, where the bundle id is passed as a handler argument too.

Chromium dialect, for Helium and Brave. The read gets everything in seven Apple Events, whatever the number of
windows. `mode` is `"normal"` or `"incognito"`. The parser drops incognito windows, so their tabs never leave
the reader:

```applescript
on readTabs(bundleId)
    tell application id bundleId
        if (count of windows) is 0 then return {}
        return {id of every window, mode of every window, bounds of every window, active tab index of every window, ¬
            id of every tab of every window, title of every tab of every window, URL of every tab of every window}
    end tell
end readTabs

on activateTab(bundleId, windowId, tabId)
    tell application id bundleId
        set w to (first window whose id is windowId)
        set i to 0
        repeat with t in tabs of w
            set i to i + 1
            if id of t is tabId then
                set active tab index of w to i
                return true
            end if
        end repeat
        return false
    end tell
end activateTab

on closeTab(bundleId, windowId, tabId)
    tell application id bundleId to close (first tab of (first window whose id is windowId) whose id is tabId)
end closeTab
```

Safari dialect. Safari's Settings or Downloads windows have no `current tab`, so each window is read in a `try`.

**Private windows in Safari:** Safari's dictionary has no "private" property, so a private window can't be
told apart through scripting. During the step 1 spike, check what Safari returns for a private window. If it
lists one, find another signal: for example, the tracked window's Accessibility attributes, or Safari's title
for private windows. Then make the reader skip those windows. If no reliable signal exists, the fallback is to
skip Safari entirely while any private window is open, rather than risk listing private tabs. Safari is rarely
used, so that fallback is acceptable.

```applescript
on readTabs(bundleId)
    set out to {}
    tell application id bundleId
        repeat with w in windows
            try
                set end of out to {id of w, bounds of w, index of current tab of w, name of tabs of w, URL of tabs of w}
            end try
        end repeat
    end tell
    return out
end readTabs

on activateTab(bundleId, windowId, tabIndex, tabURL)
    tell application id bundleId
        set w to (first window whose id is windowId)
        -- the index may have shifted since the read; trust the URL
        if URL of tab tabIndex of w is not tabURL then
            set tabIndex to index of (first tab of w whose URL is tabURL)
        end if
        set current tab of w to tab tabIndex of w
    end tell
end activateTab
```

`closeTab` for Safari follows the same index-then-URL rule. A handler that fails (the tab or window is gone)
returns an error. The coordinator treats that as "re-read this browser".

### The reader queue

`BrowserTabsReader` owns one **serial** `DispatchQueue` (QoS `.userInitiated`). Every script compile and call
runs on it, and nothing else touches the `NSAppleScript` instances.

- **Thread safety.** Apple's thread-safety summary lists `NSAppleScript` as main-thread-only, while the
  AppleScript component has been usable from secondary threads since Mac OS X 10.6, provided one instance is
  never used from two threads at once. Running every call on one serial queue satisfies that condition. Check
  it early (step 1): run with the Main Thread Checker on, and do many reads in a row. If it misbehaves, the
  fallback is `/usr/bin/osascript` through `Process` on the same queue. That is safe on any thread and only
  costs a process launch per call. Never fall back to the main thread.
- **Timeouts.** A busy or hung browser can keep an Apple Event waiting for up to the default ~2 minutes. Wrap
  each handler body in `with timeout of 2 seconds … end timeout`. A browser that times out is skipped for that
  read. Because the queue is serial, a hung browser delays the others: read each browser as its own work item,
  and drop work items for a browser that already has one waiting.
- **Never prompt, never launch.** Before every call:
  1. The browser must be in `Applications.list` (i.e. running). Otherwise skip it. `tell application id`
     launches a browser that isn't running.
  2. `AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, false)` (target: an
     `NSAppleEventDescriptor(bundleIdentifier:)`'s `aeDesc`) must return `noErr`. A return of
     `errAEEventWouldRequireUserConsent` (-1744) means "not decided yet", and `errAEEventNotPermitted` (-1743)
     means "denied". In both cases, skip the browser and record the status for Settings. This call can block,
     which is one more reason it runs on this queue. Cache the result per bundle id, and check again when
     Settings is opened or after a "Grant access…" click.
  3. Settings' "Grant access…" button is the only place that calls it with `askUserIfNeeded: true`. That is the
     only way the prompt appears.

### Parsing the reply (kernel)

`BrowserTabReplyParser.parse(_ reply: NSAppleEventDescriptor, dialect:) -> [BrowserScriptWindow]` walks the
nested list descriptors (`numberOfItems`, `atIndex(_:)`, which are 1-based, `int32Value`, `stringValue`). For
Chromium it zips the seven parallel lists, and drops every window whose `mode` isn't `"normal"`. That way an
unknown future mode is excluded too. Bounds `{left, top, right, bottom}` become `CGRect(x: left, y: top,
width: right - left, height: bottom - top)`. A missing value (`missing value` comes back as `typeNull`) becomes
an empty string. A malformed window entry drops only that window. This is pure Foundation, so tests can build
descriptors with `NSAppleEventDescriptor.list()` and `insert(_:at:)`.

## Matching script windows to AltTab windows (kernel)

A Chromium window id is the browser's internal id, not a `CGWindowID`. AltTab windows know their pid, `position`,
`size` and `title`, so:

```swift
enum BrowserWindowMatcher {
    struct Tracked: Equatable { let wid: CGWindowID; let frame: CGRect; let title: String }
    /// scriptId → wid. Each tracked window is used at most once.
    static func match(_ script: [BrowserScriptWindow], activeTitles: [Int: String], _ tracked: [Tracked]) -> [Int: CGWindowID]
}
```

Only candidates from the **same pid** are passed in. The rules, in order:

1. **Frame equal** (each edge within 2 pt) **and** the title of the script window's active tab equals the tracked
   title, or the tracked title begins with it. Chromium can add a profile suffix such as " - Work" to the window
   title.
2. **Frame equal**, if exactly one tracked candidate has that frame.
3. **Title equal**, if exactly one candidate has that title.
4. Otherwise unmatched. Being wrong here would mean focusing the wrong window. The unmatched window's tabs are
   still listed, after the browser's least recently used shown window, and switching to one has the script
   raise its window (`set index of w to 1`) before the browser is activated. The match only decides placement
   and which window AltTab focuses.

Safari: check during step 1 whether `id of window` equals the `CGWindowID` (it's AppKit's scripting `uniqueID`,
which is commonly the window number). If it does, match Safari windows by id and skip the heuristic. If not,
Safari uses the same matcher.

Edge cases to test: two windows with the same frame (stacked, or both fullscreen on one screen) told apart by
title; a minimized window, whose frame is still its last frame in both sources; Chromium PWA windows, which
belong to a different pid and must never match; and a window that exists in the script reply but isn't tracked
yet, which stays unmatched until the next read.

## Turning a snapshot into rows (kernel + coordinator)

`BrowserTabRowsDiff.diff(existing: [String], wanted: [String]) -> (keep, insert, remove)`, by row id. Then
`BrowserTabs.apply(snapshot)` on main:

1. Match windows (above). For each matched window with more than one tab, build a `BrowserTabRef` for every
   tab **except** the active one, with `slot` in strip order.
2. Diff against that browser's existing tab rows by id. For kept rows, update `browserTab` and `title`. Create
   new rows with `Window(browserTab:parent:)`. Remove gone rows.
3. Insert and remove tab rows in `Windows.list` **only through `BrowserTabs`**: `list.append` and
   `list.removeAll { $0 === row }`. Never call `Windows.appendWindow` or `Windows.removeWindows`, which are
   model operations (MRU ranks, the app window-set version, WindowServer subscriptions).
4. Call `TilesView.growPoolToCoverWindows()`, then `App.refreshOpenUiAfterExternalEvent([])` if anything
   changed. That redraw is coalesced and re-sorts.

Also remove tab rows when:

- **their parent window leaves the model.** In `Windows.removeWindows`, after the existing loop, drop the tab
  rows whose `parentWid` was removed;
- **their app quits.** `Applications` removes an app's windows by `runningApplication`. Tab rows of that app
  must go at the same time. Cleanest is to remove them in `removeWindows` by pid when the removal comes from
  termination, or to call `BrowserTabs.forget(pid)` from the termination path;
- **"Browser tabs" is turned off on every shortcut.** Clear all rows and the cache.

## Keeping tab rows out of the model

This is the checklist for option B1. Each line is a site that reads `Windows.list` (or relies on its
invariants) for **model** purposes:

| Site | Change |
| --- | --- |
| `TrackedWindowStateBridge.snapshot()` | `Windows.list.filter { $0.browserTab == nil }`. In `#if DEBUG`, `assert` in `apply()` that no reduced window id has the `btab-` prefix. |
| `TrackedWindowStateBridge.apply()` `byId` map | Nothing to do: tab-row ids never appear in the reduced state. |
| `Windows.removeWindows` | Remove by identity (`===`), not by `lastFocusOrder`. Only shift the `lastFocusOrder` of non-tab rows. Then drop orphaned tab rows (above). |
| `Windows.appendWindow` | `window.lastFocusOrder = list.count { $0.browserTab == nil }`, so tab rows don't inflate the next MRU rank. |
| `Application.canShowWindowlessPlaceholder` | `ownWindows` excludes tab rows, otherwise a tab row could count as "has a non-phantom window". |
| `Applications.discoverInactiveTabs` `appWindowCount` | Count non-tab rows only. That count describes *native* tabs. |
| `Applications.reviewExistingWindows`, the phantom sweeps, `WindowServerEvents` tracked sets | Already skip entries with `cgWindowId == nil`. Nothing to do, but re-check while implementing. |
| `Window.isPhantom`, `isTabbed`, `tabbedSiblingWids` | Never consulted for tab rows (see filtering below). Return `false`/`nil` early when `browserTab != nil` anyway, as a belt-and-braces guard. |
| `CliEvents` window list / focus by `lastFocusOrder` | Skip tab rows (they have no wid, and their `lastFocusOrder` is meaningless). |
| `SearchDiscoveryHint` window counts | Count non-tab rows, so tabs don't trigger the search hint. |

When implementing, grep `Windows.list` and `\.list\b` in `Windows.swift` again and classify every hit as
"display" (fine) or "model" (add a guard). The table above is the result of that audit at the time of writing.

## Filtering

In `Windows.updatesBeforeShowing()`, tab rows skip `WindowFilterResolver` entirely. Their parent's verdict
decides:

```swift
for window in list where window.browserTab == nil { window.shouldShowTheUser = shouldShowTheUser(window, filters) }
refreshWhichWindowsToShowTheUser()                 // "one window per app" may hide the parent
let tabsShown = Preferences.browserTabs(shortcutIndex) == .show
for row in list where row.browserTab != nil {
    row.shouldShowTheUser = tabsShown && (parent(of: row)?.shouldShowTheUser ?? false)
}
```

`refreshWhichWindowsToShowTheUser` groups by pid. Exclude tab rows from its candidates, so a tab row can never
be picked as an app's representative. In "one window per app" mode, also hide tab rows (one row per app means
one row).

To keep the row's status icons (Space number, minimized, fullscreen) right, copy the parent's `spaceIds`,
`spaceIndexes`, `isOnAllSpaces`, `isMinimized` and `isFullscreen` onto the tab row in the same loop. It's
display data only.

## Ordering: changes to `WindowOrderResolver`

A tab row should sort as if it were its parent, then by `slot`. Add one field to `OrderWindow`, as a `var` with a
default so existing tests and call sites still compile:

```swift
/// 0 for windows; a tab row's 1-based tab-strip slot. A tab row's `state` is its parent's (see Windows.orderWindow).
var browserTabSlot = 0
```

In `Windows.orderWindow`, a tab row uses **its parent's** `state` and `app`, so every bucket and sort key (MRU,
created, alphabetical, Space, at-the-end buckets) puts it exactly where its parent is. Its search score and
matching-group facts use the **tab's own** title and URL. Because the parent and its tab rows then have the same
`state.id`, one tiebreak line keeps the family together in strip order:

```swift
// non-search branch, first line after the matching-group rank check:
if a.state.id == b.state.id { return a.browserTabSlot < b.browserTabSlot }
```

In the search branch, add `browserTabSlot` as the final tiebreak, after `lastFocusOrder`. Siblings share their
parent's `lastFocusOrder`, and Swift's sort isn't stable.

Matching-group rank is compared before this tiebreak, so sections always win. If a tab row and its parent are
in the same section, the tab row follows its parent. If a tab is in another section (for example "Tabs"), it
sorts within that section by its parent's position, then by slot. So a "Tabs" section lists the tabs of the most
recently used window first, in strip order, then the next window's tabs, and so on.

## Selection: tab rows are never the default pick

The default pick is "the second visible row" in the ungrouped order. With the current window's tabs right
after it, that would be one of its own tabs, and a quick ⌥⇥ would switch tabs instead of windows (rule 7).

Add `var isBrowserTabRow = false` to `SelectionWindow`, set it in `Windows.selectionSnapshot()`, and make
`SelectionResolver.initialPickIndex` run its default pick over the non-tab rows only, then map the answer back
to a list index. This is the same technique `ungroupedOrder` already uses. `visibleCountAtSummon` counts
non-tab rows only, so tab rows that appear after the summon (a re-read landing) are never "newcomers" that
lengthen the list.

Everything else in selection needs no change. Cycling with ⇥ visits tab rows like any row. Search jumps to the
best match, which can be a tab row.

## Freshness: when tabs are read

There are no tab-change notifications, so the cache is refreshed by the signals AltTab already receives, plus one
read per summon. **There is no timer.**

| Trigger | Why it covers what | Where to hook |
| --- | --- | --- |
| **The switcher is summoned** | Catches everything else, such as tabs opened in the background or tabs moved between windows. The rows are drawn at once from the cache, and the read lands tens of ms later and corrects them in place. | `App.showUiOrCycleSelection`, after the first render. The first-render work comes first (`AGENTS.md`). |
| **A browser window's title changes** | A tab switch, a page navigation or a tab close all change the window's title, which AltTab already tracks (`AXTitleChanged`, `AxTitleNotificationPolicy`). | Where a tracked window's title is updated: if its app is a supported browser, `BrowserTabs.scheduleRefresh(pid)`. |
| **A browser window is created or destroyed** | New windows, closed windows, tabs dragged out into a window. | `Windows.appendWindow` / `removeWindows` for a supported browser's pid. |
| **AltTab activated or closed a tab** | We know the outcome. Update the cache optimistically, then confirm with a read. | `BrowserTabs.activate` / `close`. |

`scheduleRefresh(pid)` goes through a per-pid `Throttler` with a trailing call (~300 ms), so a burst of title
changes during a page load causes one read. Reads only happen while at least one shortcut has "Browser tabs"
set to Show, and only for browsers with Automation access.

### Tab recency

Tabs follow their window in strip order, not in order of use. True per-tab recency isn't available through
Automation. We could derive it: each title-change read tells us which tab just became active, so we could keep
`lastActivatedAt[tabKey]`. That's cheap for Chromium (stable ids) and approximate for Safari. It's left for a
later phase. The strip order is predictable, and matching groups already give the user control.

## Focusing and actions

`Window.focus(_:)` gets a first branch:

```swift
if let ref = browserTab {
    guard let parent = Windows.byWindowId[ref.parentWid] else { return NSSound.beep() }
    BrowserTabs.activate(ref) { parent.focus(onFronted) }   // `then` runs on main
    return
}
```

`BrowserTabs.activate` runs the dialect's `activateTab` on the reader queue and calls `then` on main when it
returns, **whether it succeeded or not**, so a failed switch still brings the window forward. The tab switch is
done first so the window appears with the right tab already showing. Measure the delay before the window
moves. If it's noticeable, run `parent.focus` at the same time as the tab switch instead (the old tab may show
for a frame). `TilesPanel.orderOutOnceFronted` keeps the panel up until the parent is fronted, so the flow
already handles the wait.

`moveCursorToSelectedWindow` and anything else that reads `position`/`size` for a tab row should use the parent's
(`referenceWindowForTabbedWindow()` can return the parent for tab rows).

Actions (`ShortcutAction`):

- **Close:** `Window.close()` for a tab row calls `BrowserTabs.close(ref)` (the dialect's `closeTab`), then a
  re-read. `canBeClosed()` is true. Like windows, there is no optimistic removal: the row goes away when the
  re-read confirms it.
- **Minimize / fullscreen / hide / quit:** forward to the parent window or app. `canBeMinDeminOrFullscreened()`
  delegates to the parent.
- **The preview panel and thumbnails** key on `cgWindowId`, which is nil for tab rows, so they already skip them.

## Search

`Search` already matches `window.title` and the app name, so tab rows are searchable with no change. In Phase 2,
also match the URL's host. Add an optional `secondaryText` to `Search.ensureCache`, set from
`browserTab?.tab.url` host (for example "github.com"), scored like the title. Then "github" finds a GitHub tab
whose title doesn't mention GitHub.

This combines well with the "bangs" idea in `README.md` (`@tabs query`): with the `kind` fact below, a bang can
be a quick filter to `kind == "tab"`.

## Matching groups

Extend `MatchingGroupFacts.of` with two keys, and add them to the `NSPredicateEditor` field list in
`MatchingGroupsTab`:

```swift
"url": window.browserTab?.tab.url ?? "",
"kind": window.browserTab == nil ? "window" : "tab",
```

`MatchingGroupFacts.of` currently takes `(WindowState, ApplicationState)`. Give it an overload that takes the
`Window`, or two optional parameters, so the existing callers don't change.

## Drawing

No drawing changes. A tab row is drawn by the unchanged `TileView` like any row: the browser's icon and the tab
title. The Space label and status icons use the facts copied from the parent (see "Filtering"), so they look
like the parent's.

Indenting tab rows under their window (a "tree") was considered and rejected. Matching groups already give the
list its structure, and a second hierarchy conflicts with them. A tab whose section differs from its window's
would be indented under an unrelated row, a tab in its window's section would show two levels of structure,
and search breaks up the families anyway. Sections are the one way to structure the list.

## Settings UI

1. **Per-shortcut dropdown.** `ShortcutBoundDropdown(baseName: "browserTabs", cases: BrowserTabsPreference.allCases)`,
   labeled "Browser tabs", with values "Hide" and "Show", default Hide. Put it in `ShortcutEditor.swift` next to
   "Matching groups", and bind it in `bind(toShortcut:)`.
2. **Browser access list.** A small "Browser tabs" section in Settings, next to Groups. It has one row per
   *installed* supported browser (Helium, Brave, Safari) (found with `NSWorkspace.urlForApplication(withBundleIdentifier:)`), showing
   the access status (Allowed / Not asked / Denied) and a "Grant access…" button. The button runs
   `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: true)` on the reader queue, which shows the
   macOS prompt. The browser must be running for the prompt to appear, so the button is disabled with a hint
   when it isn't. "Denied" can only be undone in System Settings, so for that state the button opens
   `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`.

### Preference keys

| Key | Type / default | Where |
| --- | --- | --- |
| `browserTabs`, `browserTabs2`, … | `BrowserTabsPreference` (`hide`, `show`), default `hide` | the `(0...maxShortcutCount)` loop |

There are no stored lists. Access status lives in TCC, not in our preferences.

## Performance budget

- **The show path does no new blocking work.** Applying cached rows is O(rows) of in-memory work. The re-read
  runs on the reader queue.
- A read costs one handler call per browser: about six Apple Events for Chromium, and about five per window for
  Safari. Log each read's duration at debug level, and look at real numbers with many windows and tabs before
  tuning anything. If one read is consistently slow, the summon-time read is the one to drop. The event
  triggers already keep the cache close to current.
- **Row count.** Someone with 200 tabs gets 200 extra rows. The tile pool grows to cover them
  (`growPoolToCoverWindows`), and the Titles layout handles long lists by scrolling. Watch
  `MainThreadStall.step()` in `layoutTileViews` with a large tab count.

---

# Part 4: Implementation plan

Do the steps in order. Each one ends with `ai/build.sh` and `ai/test.sh` passing.

| # | Step | Done when |
| --- | --- | --- |
| 1 | **Spike: reading.** Add the entitlement and the usage string. Write `BrowserTabsReader` with the Chromium script, the permission check and the parser. Temporarily log every browser's snapshot from the Debug menu. Check the thread-safety question and the read durations, and that Helium's and Brave's dictionaries match the script (including `mode`). | A debug action logs correct windows and tabs for Helium and Brave, with incognito windows dropped and no prompt unless one is asked for. Record the measured durations in this doc. |
| 2 | **Kernels.** `BrowserTabReplyParser`, `BrowserWindowMatcher`, `BrowserTabRowsDiff`, each with Specs and Tests, added to both targets. | The test scenarios below pass. |
| 3 | **Tab rows in the model, behind the flag.** `Window.browserTab` and its init, `BrowserTabs` (cache, apply, removal), the model-side checklist, the bridge assertion, the preference key and `MacroPreference`. Read on summon only. | With `defaults write com.lwouis.alt-tab-macos browserTabs show`, tab rows appear (unsorted is fine). Closing a browser window or quitting the browser removes its rows. Debug assertions stay quiet through a normal session. |
| 4 | **Filtering, ordering, selection.** The parent-based filtering, `browserTabSlot` and the tiebreaks, `isBrowserTabRow` in selection. | `WindowOrderResolver` and `SelectionResolver` tests pass. Tabs follow their window. A quick ⌥⇥ returns to the previous window. |
| 5 | **Focus and actions.** `activate` / `close`, the `Window.focus` branch, and actions forwarded to the parent. | Releasing on a tab row shows that tab in its window, across Spaces too. W closes the tab. |
| 6 | **Freshness.** Title-change and window create/destroy triggers, throttled. | Switching tabs in Helium and summoning AltTab shows the new active tab with no visible correction. |
| 7 | **Settings.** The per-shortcut dropdown and the browser access list. | Access can be granted from Settings, and the dropdown turns tabs on and off per shortcut. |
| 8 | **Safari.** The Safari script, the window `id` check (exact match if it equals the `CGWindowID`), and the private-window check (see "Private windows in Safari"). | Safari tabs appear, and no private window's tabs ever do. |
| 9 | **Polish (Phase 2).** URL host in search, `url`/`kind` matching-group facts, optional tab recency. | Each item works on its own and can be dropped. |

**Phase 3 (not planned):** an Accessibility reader as a second `BrowserDialect` (`.accessibility`) for apps with
a standard `AXTabGroup`. It's only worth building if a non-browser app's tabs are ever wanted. It would be opt-in per bundle id, read only on the event
triggers (never on summon), and limited per show the way `TabReadPolicy` limits native-tab reads. Its tabs have
no URL and are identified by `"index|title"`.

## Test scenarios to put in the Specs files

- **`BrowserTabReplyParser`:**
  - a Chromium reply with two windows zips into the right tabs;
  - an empty reply gives no windows;
  - an incognito window (or any mode other than "normal") is dropped, and its tabs with it;
  - `missing value` for a URL becomes "";
  - one malformed window is dropped and the rest are kept;
  - bounds become top-left rects;
  - a Safari reply missing one window (`try` skipped) parses the rest.
- **`BrowserWindowMatcher`:**
  - frame + title match;
  - title with a profile suffix;
  - two windows with one frame, told apart by title;
  - frame-only match when unique;
  - title-only match when unique;
  - ambiguous → unmatched;
  - each tracked window matched at most once;
  - no candidates → no matches.
- **`BrowserTabRowsDiff`:**
  - unchanged → keep all;
  - new tab → insert;
  - closed tab → remove;
  - the active tab changed → every row is kept;
  - a Safari tab moved (index key changed) → remove and insert.
- **`WindowOrderResolver`:**
  - a tab row sorts right after its parent in slot order, for every sort type;
  - at-the-end buckets move a minimized parent with its tabs;
  - matching-group rank separates a tab from its parent;
  - with search, siblings with equal relevance tiebreak on slot.
- **`SelectionResolver`:**
  - with the current window's tabs between it and the previous window, the default pick is the previous
    window;
  - tab rows appearing after the summon don't move the default pick;
  - cycling visits tab rows.
- **Model guard (live test or debug assertion):** a reducer pass never contains a `btab-` id. `removeWindows` on a
  window keeps unrelated tab rows and drops that window's own tab rows.

## Edge cases to keep in mind

- **A tab is closed in the browser while the switcher is open, and the user then focuses it.** `activateTab`
  fails, `then` still focuses the parent, and the re-read removes the row.
- **A tab is dragged to another window.** Its key stays the same (Chromium), but its `parentWid` and
  `scriptWindowId` change, so its row id changes. It becomes a remove plus an insert. That's acceptable.
- **Browser windows on other Spaces.** Apple Events see them. Their rows follow the parent's Space filtering.
  Focusing goes through the parent's cross-Space focus path.
- **Minimized browser windows.** Chromium still lists their tabs. The rows follow the parent's minimized
  handling ("show at the end" moves the family together).
- **Fullscreen browser windows** are matched by frame (screen-sized), so two fullscreen windows on the same
  screen fall back to the title rule.
- **Incognito and private windows** are excluded at the reader (`mode` for Helium and Brave; see "Private
  windows in Safari"). Their window row is unaffected. Because they're unmatched, they also can't be wrongly
  matched to a normal window with the same frame. Pass only non-incognito script windows to the matcher.
- **The browser is quitting** while a read is in flight. The reply is an error. Drop it, and the quit removes the
  rows anyway.
- **Automation access is revoked** in System Settings. The next permission check fails, the cache for that
  browser is cleared, and its rows disappear.
- **Native tab setting interplay.** `showTabsAsWindows` (native window tabs) is unrelated and unchanged. Safari
  doesn't use native window tabs, so the two never describe the same tab.

## Open questions for the owner

Resolved: the browsers are Helium and Brave (daily) and Safari (rare). Incognito and private windows are out of
scope.

1. Should the window row be hidden now that the active tab has its own row ("replace" instead of "expand")?
   The design keeps the window row, because hiding real windows affects focus order, filters and the default
   selection.
