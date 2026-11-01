# Matching Groups for the Titles layout

Status: implemented. The selection section below describes what was built, which differs from the original design.

This document is for an engineer who knows Swift and AppKit but has never seen this codebase. Part 1
explains the feature. Part 2 explains the parts of the codebase it touches. Part 3 is the design.
Part 4 is the step-by-step plan.

---

# Part 1: The feature

## Background: AltTab and the Titles style

AltTab is a macOS window switcher. While the user holds a shortcut (⌥⇥ by default), a panel shows every
open window. Each press of ⇥ moves the highlight, and releasing ⌥ focuses the highlighted window.

The panel has three visual **styles**: Thumbnails, App Icons and **Titles**. This feature is for
**Titles only**. In that style, each window is one full-width row containing an app icon and the window title:

```
 ▸ Messages
 ▸ Project Alpha — Xcode
 ▸ Inbox (3) — Mail
 ▸ Finder
 ▸ Project Beta — Terminal
```

Today this list is flat, and its order comes from the shortcut's **Window order** setting, which is "recently
focused first" by default.

This repository is a personal fork. Pro and licensing checks are irrelevant here, because every feature is
available. Ignore any `Pro…` gating you see in the code.

## Goal

Let the user split the Titles list into named sections. For each section they define a rule, and they order
the sections to say what matters most:

```
 COMMS
   ▸ Messages
   ▸ Inbox (3) — Mail
 PROJECTS
   ▸ Project Alpha — Xcode
   ▸ Project Beta — Terminal
 OTHER
   ▸ Finder
```

The user configures this in Settings as an ordered list of **matching groups**. Each matching group has:

- a **name**, shown as the section header ("Comms");
- a **rule**, built with dropdowns, for example *Any of: App name is "Messages", Title begins with "Inbox ("*;
- an **enabled** switch.

The order of the list does two things. It is the order the sections are drawn in, and it is the priority when
a window matches more than one rule. Dragging Comms above Projects moves the Comms section up, and a window
that matches both rules goes into Comms.

## Exact behavior

1. **First match wins.** Each window goes into the first *enabled* group whose rule it matches, from the top
   of the list. A window is never in two groups.
2. **Other.** Windows that match no group go into a final section, always named "Other".
3. **Empty sections are not drawn.** A group header appears only if at least one window is under it.
4. **One section means no headers.** If every displayed window ends up in the same section, no headers are
   drawn, and the list looks the same as it does today. One exception, during search: if a best match is
   pinned (rule 6) and the remaining windows share one section, that section still gets its header, so the
   pinned tile is visibly separated from them.
5. **Order inside a section** is the shortcut's normal Window order setting. Today's "show at the end" options
   (windowless apps, hidden windows, minimized windows) push those windows to the end **of their section**.
6. **Search keeps the sections, except for the best match.** The user can type to filter the list. While they
   do, the window with the best search score is pinned first, with no header. All other matching windows
   stay in their sections, ordered by search score within each section. The pin can be turned off with
   Settings → Groups → "Pin top result" (global, on by default, key `matchingGroupsPinTopResult`); then every
   match stays in its section. For the query `pro` with the groups above:

   ```
   ▸ Project Beta — Terminal        ← best match, pinned, no header
    PROJECTS
     ▸ Project Alpha — Xcode
    OTHER
     ▸ Some Proxy Tool
   ```

7. **Per-shortcut switch.** AltTab supports several shortcuts, each with its own settings. Matching groups are
   turned on per shortcut, and only take effect when that shortcut's style is Titles. The list of groups is
   global and shared by every shortcut.
8. **Default selection still toggles.** Pressing ⌥⇥ once and releasing must still take you back to the window
   you were on before, even when grouping moves that window down the list.
9. **Groups never get lost.** Groups are saved immediately, survive relaunches, and a malformed stored entry
   drops only that entry.

## Non-goals

- Thumbnails and App Icons styles.
- A custom rule language or parser. Rules use Apple's `NSPredicate` and `NSPredicateEditor` (see Part 3).
- Localization of the new UI strings (English is fine).
- Collapsing sections, per-group colors or icons, renaming "Other".

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
- Low latency matters: no polling, no redundant work on the path that shows the switcher.
- To build, run `ai/build.sh`. To run the unit tests, run `ai/test.sh`. Don't use `scripts/run_tests.sh`.
- **The `unit-tests` target has its own source list** in `alt-tab-macos.xcodeproj`, and it does not build the
  app target. Every new kernel file, and every file a test references, must be added to **both** targets.

## How a switcher frame is built today

This is a simplified version of the pipeline. Each step names the code you'll change.

```
user presses shortcut / types in search
        │
        ▼
Windows (src/switcher/state/Windows.swift)
  • Windows.list: [Window], every tracked window.
  • window.shouldShowTheUser: set by the shortcut's filters (apps, Spaces, screens, …).
  • Windows.shouldDisplay(w) = shouldShowTheUser && Search.matches(w, query).
    Non-matching windows stay in the list but are not drawn.
  • Windows.sort(): sorts Windows.list in place with WindowOrderResolver.isOrderedBefore.
        │
        ▼
WindowOrderResolver (src/switcher/state/WindowOrderResolver.swift)   ← pure kernel
  • OrderWindow = WindowState + ApplicationState + search score; computed once per window per sort.
  • isOrderedBefore: when a search is active, sort by match, then relevance.
    Otherwise: the "at the end" buckets, then the shortcut's Window order.
        │
        ▼
TilesView (src/switcher/main-window/TilesView.swift)
  • recycledViews[i] is the TileView for Windows.list[i]. The index is the same in both arrays.
  • updateItemsAndLayout → layoutTileViews → fillTiles: fills tiles for windows where
    shouldDisplay is true, and gives the others frame = .zero.
  • Builds a TileGridLayout.Input from the tile widths and puts each tile at the computed origin.
  • rows: [[TileView]] drives ↑/↓ keyboard navigation (nextRow, navigateUpOrDown).
  • resolveAutoSize / dryRunLayoutTileViews run the same layout to pick a size.
        │
        ▼
TileGridLayout (src/switcher/main-window/TileGridLayout.swift)       ← pure kernel
  • Lays tiles out left to right and wraps rows. In Titles every tile is at least 60% of the panel
    width (Appearance.titlesSize: windowMinWidthInRow = 0.6), so each row holds exactly one tile.

Selection (src/switcher/state/SelectionResolver.swift)               ← pure kernel
  • Decides which index is highlighted. Inputs are built in Windows.swift (search "useLastFocusedRule").
  • Default: "the second visible tile", which assumes MRU order. When `useLastFocusedRule` is true,
    it picks the visible window with the lowest lastFocusOrder instead.
  • When a search query changes, it jumps to the first visible tile (the best match).
```

The facts you'll match against:

- `WindowState.title` (`src/switcher/state/WindowState.swift`)
- `ApplicationState.localizedName`, the app name (`src/switcher/state/ApplicationState.swift`)
- `ApplicationState.bundleIdentifier` (`src/switcher/state/ApplicationState.swift`)

`ExceptionMatcher.swift` is the closest existing example of matching user rules against these records.

## Preferences

These are in `src/preferences/Preferences.swift`.

- Everything is stored in `UserDefaults` **as strings**. `defaultValues` registers every key's default, and
  `ownedKeys` is derived from it.
- Reads go through `CachedUserDefaults` (`.bool`, `.macroPref`, `.json`, …). The cache exists because
  `UserDefaults` is IPC.
- Writes go through `Preferences.set(key, value)`. It invalidates the caches and then calls
  `PreferencesEvents.preferenceChanged(key)` (`src/events/PreferencesEvents.swift`), which is where code reacts
  to changes.
- **Per-shortcut** settings use one key per shortcut: `windowOrder`, `windowOrder2`, … `windowOrder10`
  (`Preferences.indexToName(base, index)`), each registered in the `(0...maxShortcutCount)` loop.
- Dropdown settings are `MacroPreference` enums, such as `WindowOrderPreference` in
  `src/preferences/MacroPreferences.swift`.
- The Exceptions list is the existing JSON-array preference to copy (`ExceptionEntry`, key `"exceptions"`).

**Naming collision to avoid:** "group" already means two unrelated per-shortcut settings here. One is
`showAppsOrWindows` (`GroupAppsPreference`, one window per app). The other is `showTabsAsWindows`
(`GroupTabsPreference`, `TabGroup`, native macOS tabs). `PreferencesEvents.isPerShortcutGroupingKey` refers
to those two settings. To keep the meanings apart, every identifier in this feature uses the `MatchingGroup`
prefix.

## Settings window

These are in `src/preferences/settings-window/`.

- Sidebar sections are declared in `SettingsWindow.swift` (search for
  `SettingsSectionDefinition(id: "exceptions"`), and each tab's `cleanup()` is called from the same file.
- `tabs/ExceptionsTab.swift` and `tabs/ExceptionEditorView.swift` show the layout to copy: a list on the left,
  an editor on the right, +/− buttons, and saving on every change.
- Per-shortcut dropdowns: `tabs/controls/ShortcutEditor.swift`, where `windowOrder` is a
  `ShortcutBoundDropdown` row. Add the on/off row next to it.

---

# Part 3: Design

## Terminology

| Term | Meaning |
| --- | --- |
| Matching group | A user-defined `{ name, rule, enabled }` entry. |
| Rank | A window's group index (0 = the first group). The rank for "Other" is the number of groups. |
| Section | A run of consecutive drawn tiles with the same rank. It gets a header. |
| Pinned best match | During search, the one top-scoring window, drawn first with no header. |

## Rules: `NSPredicate` + `NSPredicateEditor`

Using AppKit's own tools keeps this as simple as possible.

- `NSPredicateEditor` is AppKit's built-in rule builder (the UI in Finder's and Mail's smart-folder editors).
  It has dropdowns for field and operator, a text field for the value, and All / Any / None groups that can
  be nested (⌥-click +).
- `NSPredicate` evaluates the rule the editor builds.
- `predicate.predicateFormat` gives a string for saving, for example
  `title BEGINSWITH[c] "Inbox (" OR app ==[c] "Messages"`. `NSPredicate(format:)` turns that string back into a
  predicate.

We write no parser, no evaluator and no rule UI widgets.

### Editor configuration (in code)

```swift
let fields = ["title", "app", "bundleId"].map { NSExpression(forKeyPath: $0) }
let operators: [NSComparisonPredicate.Operator] = [.equalTo, .notEqualTo, .contains, .beginsWith, .endsWith, .matches]
let stringRow = NSPredicateEditorRowTemplate(leftExpressions: fields,
    rightExpressionAttributeType: .stringAttributeType, modifier: .direct,
    operators: operators.map { NSNumber(value: $0.rawValue) },
    options: Int(NSComparisonPredicate.Options.caseInsensitive.rawValue))
let compoundRow = NSPredicateEditorRowTemplate(compoundTypes: [.and, .or, .not].map { NSNumber(value: $0.rawValue) })
editor.rowTemplates = [compoundRow, stringRow]
```

- The field popup shows the key path by default ("title"). Give it readable labels ("Title", "App name",
  "Bundle ID"), either with `formattingDictionary` or by setting the titles of the menu items in the
  template's first popup once.
- `.caseInsensitive` makes every comparison ignore case.
- **`matches` is an ICU regex that must match the whole string.** `^Project.*` matches "Project Alpha", but
  `Project` alone doesn't. Say this in the value field's placeholder text, and pin it with a test.

### Evaluation

Each window is turned into a 3-key dictionary, once per sort. `NSPredicate` reads the key paths through KVC,
so we need no `@objc` model class.

```swift
enum MatchingGroupFacts {
    static func of(_ s: WindowState, _ app: ApplicationState) -> [String: String] {
        ["title": s.title, "app": app.localizedName ?? "", "bundleId": app.bundleIdentifier ?? ""]
    }
}
// predicate.evaluate(with: facts)
```

### Loading a stored rule safely

`NSPredicate(format:)` raises an Objective-C exception on a malformed string, and Swift can't catch that.
Wrap the call in the existing `ObjCExceptionCatcher.attempt { … }` (`src/vendors/ObjCExceptionCatcher.h`; it
returns `false` if the block threw). A rule that fails to load becomes `nil`: it never matches, Settings shows
a warning on it, and the other rules are unaffected.

## Data model

Create `src/switcher/matching-groups/MatchingGroupRule.swift`:

```swift
struct MatchingGroupRule: Codable, Equatable {
    var id: UUID              // stable identity across renames and reorders
    var name: String
    var predicateFormat: String
    var isEnabled: Bool
}
```

## Persistence: three fixes so groups are never lost

**1. `Preferences.set` must JSON-encode the new key.** Today it hard-codes one key:

```swift
write(key, notify) { UserDefaults.standard.set(key == "exceptions" ? jsonEncode(value) : value, forKey: key) }
```

`Preferences.set("matchingGroups", rules)` would therefore pass an array of Swift structs to `UserDefaults`.
That isn't a property-list type, so it crashes. Replace the check with a named set:

```swift
private static let jsonEncodedKeys: Set<String> = ["exceptions", "matchingGroups"]
…
write(key, notify) { UserDefaults.standard.set(jsonEncodedKeys.contains(key) ? jsonEncode(value) : value, forKey: key) }
```

**2. Decode one entry at a time.** When `CachedUserDefaults.getThenConvertOrReset` can't decode a stored value,
it **deletes the key** and falls back to the default (here, an empty list). One bad entry would wipe every
group. Decode into a wrapper that never fails, then drop the failures:

```swift
struct LenientDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
static var matchingGroups: [MatchingGroupRule] {
    CachedUserDefaults.json("matchingGroups", [LenientDecodable<MatchingGroupRule>].self).compactMap { $0.value }
}
```

**3. Make `MatchingGroupRule.init(from:)` permissive.** Use `decodeIfPresent` with defaults (`id = UUID()`,
`name = ""`, `isEnabled = true`), so future field additions decode old data. `predicateFormat` is the only
required field. `ExceptionEntry` at the bottom of `Preferences.swift` is the precedent.

Test all three: save then reload, an old shape with missing fields, and a list with one corrupt entry that
keeps the others.

### Preference keys

| Key | Type / default | Where |
| --- | --- | --- |
| `matchingGroups` | JSON `[MatchingGroupRule]`, default `"[]"` | `defaultValues` |
| `matchingGroupsEnabled`, `matchingGroupsEnabled2`, … | `MatchingGroupsPreference` (`off`, `byRules`), default `off` | the `(0...maxShortcutCount)` loop |

Add the accessors `Preferences.matchingGroups` and `Preferences.matchingGroupsEnabled(_ index: Int)`, and
add `MatchingGroupsPreference` to `MacroPreferences.swift`. Follow `WindowOrderPreference` as the model.

### Compiled cache

Create `src/switcher/matching-groups/MatchingGroups.swift`. It keeps `NSPredicate(format:)` off the show path:

```swift
enum MatchingGroups {
    /// Enabled rules in priority order. `predicate` is nil when the stored format failed to load.
    private(set) static var compiled: [(rule: MatchingGroupRule, predicate: NSPredicate?)] = []
    static func reload() { … }   // call at launch, and from PreferencesEvents.preferenceChanged on "matchingGroups"
}
```

## Assigning ranks (pure kernel)

Create `src/switcher/matching-groups/MatchingGroupResolver.swift`, plus its Specs and Tests:

```swift
enum MatchingGroupResolver {
    /// Index of the first predicate that matches, or `predicates.count` ("Other"). nil never matches.
    static func rank(_ facts: [String: String], predicates: [NSPredicate?]) -> Int
}
```

This is `n windows × r rules` evaluations once per sort, which is negligible. Don't add a cache unless
`MainThreadStall.step()` shows a cost.

## Ordering: changes to `WindowOrderResolver`

Add two fields to `OrderWindow`. Declare them as `var` with defaults, because the struct's memberwise init
can't default a `let`. This way existing tests and call sites still compile:

```swift
var matchingGroupRank = 0
var isPinnedBestMatch = false
```

When the feature is off, every window has rank 0 and nothing is pinned, so the comparator returns exactly
what it returns today.

**Without search**, add one line after the `if searchActive { … }` block, before the at-the-end buckets:

```swift
if a.matchingGroupRank != b.matchingGroupRank { return a.matchingGroupRank < b.matchingGroupRank }
```

**With search**, change the search block to:

```swift
if searchActive {
    if a.searchMatches != b.searchMatches { return a.searchMatches }
    if a.isPinnedBestMatch != b.isPinnedBestMatch { return a.isPinnedBestMatch }
    if a.matchingGroupRank != b.matchingGroupRank { return a.matchingGroupRank < b.matchingGroupRank }
    if a.searchRelevance != b.searchRelevance { return a.searchRelevance > b.searchRelevance }
    return a.state.lastFocusOrder < b.state.lastFocusOrder
}
```

### Wiring in `Windows.sort()`

1. Next to the other per-sort locals (`searchActive`, `windowlessAtEnd`, …), compute:

   ```swift
   let groupingActive = Preferences.matchingGroupsEnabled(shortcutIndex) == .byRules
       && Preferences.effectiveAppearanceStyle(shortcutIndex) == .titles
       && !MatchingGroups.compiled.isEmpty
   ```

   Expose it as `Windows.matchingGroupsActive(_ shortcutIndex:)`, because the selection change below needs the
   same answer.
2. In `orderWindow(_:_:_:)`, set `matchingGroupRank` when `groupingActive` is true.
3. If both `groupingActive` and `searchActive` are true, then before sorting, set `isPinnedBestMatch` on the
   single window that is matching and has `shouldShowTheUser`, with the highest `searchRelevance` (ties go to
   the lowest `lastFocusOrder`). Do this with one pass over the precomputed `facts`. Put the choice itself in a
   small pure function on the resolver, so it can be tested.
4. After sorting, copy both values onto each `Window` (`window.matchingGroupRank`,
   `window.isPinnedBestMatch`, next to the existing `rowIndex` property in `Window.swift`), so the layout can
   read them.

## Selection: judge the default pick in the ungrouped order

The original design reused `useLastFocusedRule` when grouping is on. That rule picks the visible window with
the lowest `lastFocusOrder`, which is the window the user is currently on, so a quick ⌥⇥ would do nothing
(rule 8). Instead:

- `Windows.sort()` also sorts the list with every rank at 0 and stores each window's position there in
  `Window.ungroupedPosition` (nil while grouping is off, or during search).
- `SelectionWindow.ungroupedPosition` carries it to the kernel. `SelectionResolver.initialPickIndex` runs the
  usual default pick (newcomers, filtered-out current window, both-top-minimized) over the list reordered by
  that position, then maps the answer back to a list index.
- `useLastFocusedRule` is unchanged, so non-MRU window orders keep picking the current window as before.

Search needs no change: when a query changes, the selection already jumps to the first visible tile, which is
the pinned best match. `SelectionResolverTests.testInitialPickInAGroupedListLandsOnThePreviousWindow` pins the
grouped case.

## Section headers

**Headers are separate views, not entries in `Windows.list`.** Selection, hover, `recycledViews`, cycling and
every window action index into that list, and a fake entry would break all of them.

### Where sections start (pure kernel)

Put this in `MatchingGroupResolver`, with tests:

```swift
/// Given the drawn tiles' ranks in display order, and whether tile 0 is the pinned best match,
/// returns the positions that open a section.
static func sectionStarts(ranks: [Int], firstIsPinned: Bool) -> [Int]
```

The rules:

- A section starts at the first unpinned tile, and at every position where the rank differs from the previous
  tile's rank.
- The pinned tile is never a section start, and it doesn't count as "the previous tile".
- If all the unpinned tiles share one rank, return `[]` (no headers, rule 4). The one exception is when there
  is a pinned tile *and* the unpinned tiles all share a rank: they still get their header, so the pinned tile
  is visibly separated from the rest.

### `TileGridLayout` changes

```swift
struct Input  { …; var sectionStarts: [Int] = []; var headerHeight: CGFloat = 0 }
struct Result { …; var headerOrigins: [CGPoint] }   // one per sectionStarts entry, same order
```

When `compute` reaches a tile whose position is in `sectionStarts`, it:

1. starts a new row (unless this is the first tile);
2. records a header origin at that row's leading edge (it respects `isLeftToRight`);
3. moves `currentY` down by `headerHeight` before placing the tile;
4. includes this in `maxY`.

`rows` still lists **only tiles**, so ↑/↓ navigation skips headers without any change. Add tests to
`TileGridLayoutTests` and its spec:

- a section at position 0 (header first, no blank row);
- two consecutive sections;
- RTL origins;
- `maxY` that includes headers.

### `TilesView` changes

- In `layoutTileViews`, take the drawn tiles' `window.matchingGroupRank` and the first tile's
  `isPinnedBestMatch`, call `sectionStarts`, and pass the result plus `headerHeight` through `gridInput(…)`.
  Cache `headerHeight` in `LayoutCache`, derived from the header font.
- Do the same in `dryRunLayoutTileViews`. Auto-size runs that dry-run layout to pick a size, so without headers
  it measures a shorter list and picks a size that overflows.
- Keep a reusable pool, `static var matchingGroupHeaderViews: [MatchingGroupHeaderView]`, that grows on demand
  and never shrinks (like `recycledViews`). `layoutTileViews` replaces `documentView.subviews` with the tile
  views. Append the headers in use to that array, and set their origins from `layout.headerOrigins`.
- Set header widths in `layoutParentViews`, once `thumbnailsWidth` is known (the width is
  `thumbnailsWidth - 2 × interCellPadding`). The right-to-left crop shift there must move headers too.
  `centerRows` moves tiles only.
- When the selected tile is the first in its section, include its header in the scroll-to-visible area, so
  that moving to the top of a group shows the group's name.

### `MatchingGroupHeaderView`

Create `src/switcher/main-window/MatchingGroupHeaderView.swift`:

- A `FlippedView` (defined in `TilesView.swift`) that draws the group name uppercased with
  `uppercased(with: .current)`, or "Other" for the last rank: semibold, 85% of `Appearance.fontHeight`, in
  `Appearance.fontColor` at 55% opacity.
- The name is a `CATextLayer`, not an `NSTextField`. A label added to the tiles' document view never drew:
  logged live, its layer never got contents while its space was laid out.
- `hitTest(_:)` returns `nil`, so hover, clicks and drag and drop pass through to the tiles underneath.

## Settings UI

### Per-shortcut switch

In `ShortcutEditor.swift`, add a `ShortcutBoundDropdown(baseName: "matchingGroupsEnabled", cases: MatchingGroupsPreference.allCases)`
row labelled "Matching groups", next to the Window order row. Bind it in `bind(toShortcut:)`.

### New "Groups" sidebar section

Add a `SettingsSectionDefinition` next to the Exceptions one in `SettingsWindow.swift`, and call `cleanup()` in
the same places Exceptions does. The section's layout copies `ExceptionsTab`:

- **Left: the list of groups.** It's an `NSTableView` with one column and the group name as each row's text,
  because reordering is the core interaction and the Exceptions sidebar (an `NSStackView`) has no drag support.
  - Drag to reorder:
    - `tableView(_:pasteboardWriterForRow:)` writes the rule `id` under a private pasteboard type.
    - `validateDrop` allows only `.above` drops.
    - Set `draggingDestinationFeedbackStyle = .gap`.
    - `acceptDrop` moves the rule, saves, and keeps it selected.
  - The table reports the destination index *before* removing the dragged row. Put the move in a pure, tested
    helper (`Array.moved(from:to:)`) to avoid the off-by-one.
  - Rows show a warning symbol when the rule's predicate failed to load, and dimmed text when the group is
    disabled.
  - The +/− buttons below add and remove groups. A new group is named "New group", with the rule
    `title CONTAINS[c] ""`. That rule matches every title, so it would capture all windows below it in
    priority. Either keep the new group **disabled** until the user edits the value, or treat an empty value
    as "matches nothing". Disabled is simpler.
- **Right: the editor for the selected group.**
  - a name `TextField`;
  - the `NSPredicateEditor`;
  - an enabled `Switch`;
  - a status line, "Matches N open windows", evaluated against the currently displayable `Windows.list`.
- **Saving:** every edit calls `Preferences.set("matchingGroups", items)`, as `ExceptionsTab.savePreferences`
  does. `NSPredicateEditor` sends its target-action when any row changes. `MatchingGroups.reload()` runs from
  `PreferencesEvents`.

---

# Part 4: Implementation plan

Do the steps in order. Each one ends with `ai/build.sh` and `ai/test.sh` passing.

| # | Step | Done when |
| --- | --- | --- |
| 1 | **Persistence.** `MatchingGroupRule` (permissive decoding), `LenientDecodable`, the `jsonEncodedKeys` fix, the two preference keys, `MatchingGroupsPreference`, and `MatchingGroups.reload()` wired to launch and `PreferencesEvents`. | Tests prove save→reload works, old shapes decode, and one corrupt entry leaves the others intact. |
| 2 | **Ranks and ordering.** `MatchingGroupFacts`, `MatchingGroupResolver.rank`, best-match pinning, the `OrderWindow` fields, the comparator lines, and `Windows.sort()` wiring. | Unit tests cover first-match-wins, disabled and nil rules, Other, and ordering with and without search. Manually, with `matchingGroups` written by `defaults write` and the shortcut set to Titles, the list comes out grouped (no headers yet). |
| 3 | **Selection.** Extend `useLastFocusedRule`. | A new `SelectionResolverTests` scenario passes. ⌥⇥ toggles between two windows in different sections. |
| 4 | **Headers.** `sectionStarts`, the `TileGridLayout` input and result fields, `MatchingGroupHeaderView`, and the `TilesView` wiring (layout, dry run, pool, widths, RTL, scroll). | Kernel tests pass, headers draw correctly, ↑/↓ skips them, and auto-size doesn't overflow. |
| 5 | **Settings.** The per-shortcut dropdown, the Groups section, the `NSPredicateEditor` setup, drag reorder, and the status line. | Groups can be created, edited, reordered, disabled and deleted, they survive a relaunch, and the switcher reflects every change on its next show. |

For a test value in step 2:

```
defaults write com.lwouis.alt-tab-macos matchingGroups '[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Comms","predicateFormat":"app ==[c] \"Messages\" OR title BEGINSWITH[c] \"Inbox (\"","isEnabled":true}]'
```

## Test scenarios to put in the Specs files

- **`MatchingGroupResolver`:**
  - first match wins when two rules match;
  - disabled rules are skipped;
  - a `nil` predicate never matches;
  - no match gives "Other";
  - an empty list gives rank 0 for everyone;
  - `matches` is a full-string match (`Project` doesn't match "Project Alpha", `^Project.*` does);
  - comparisons ignore case;
  - a nil app name is evaluated as "".
- **`sectionStarts`:**
  - all tiles in one rank gives no headers;
  - ranks `[0,0,1,2]` give `[0,2,3]`;
  - pinned and the rest in one rank gives a header after the pinned tile;
  - pinned and the pinned tile's own group continues gives a header after the pinned tile;
  - a single pinned tile gives `[]`.
- **`WindowOrderResolver`:**
  - rank is the primary key without search;
  - at-the-end buckets apply within a group;
  - rank 0 everywhere reproduces today's order;
  - with search: matches, then the pinned tile, then rank, then relevance.
- **`TileGridLayout`:** as listed in Part 3.
- **`SelectionResolver`:** grouped list, and the default selection lands on the most recently focused visible
  window.
- **Persistence:** save and reload, an old shape, and a corrupt entry among good ones.

## Edge cases to keep in mind

- **A title changes while the switcher is open** (for example `Inbox (3)` becomes `Inbox (4)`). The window may
  move to another section on the next sort. The selection follows the window by id, which `SelectionResolver`
  already does.
- **"Show one window per app" mode** (`showAppsOrWindows`). The representative window is chosen first, in
  `refreshWhichWindowsToShowTheUser`, and then grouped by its own title.
- **Windowless app placeholders** have an empty title. App-name and bundle-ID rules still match them.
- **When the list of groups is empty, or every group is disabled**, `groupingActive` is false, so the flat
  list is the same as today. When every enabled group failed to load, every window is ranked "Other". That
  is a single section, so there are no headers, and the order is the same as today.
- **Duplicate group names** are allowed. Identity is the `id`, and the position sets the priority.
