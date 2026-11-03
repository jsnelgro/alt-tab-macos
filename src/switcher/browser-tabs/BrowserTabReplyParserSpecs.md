# BrowserTabReplyParser — Specs

## Summary

`BrowserTabsReader` runs a dialect's `readTabs` handler and hands the reply here.
`BrowserTabReplyParser.parse(_:dialect:)` turns it into `[BrowserScriptWindow]`. It is pure Foundation, so
tests build replies with `NSAppleEventDescriptor.list()`.

- **Chromium** (Helium, Brave): seven parallel lists, `{ids, modes, bounds, active tab indexes, tab ids of
  each window, tab titles of each window, tab URLs of each window}`. Ids are text in these dictionaries.
- **Safari**: one entry per window, `{id, bounds, index of current tab, tab names, tab URLs}`. Windows without
  a current tab (Settings, Downloads) are skipped by the script's `try`. Safari has no tab id, so a tab's key is
  `"index|URL"`.

## Behavior & edge cases

- Only Chromium windows whose `mode` is exactly `"normal"` are kept. Incognito, and any mode a future version
  adds, never leave the parser.
- `bounds` `{left, top, right, bottom}` become a top-left `CGRect`.
- `missing value` (a tab still loading has no URL) reads as "".
- A malformed window (wrong bounds, mismatched tab lists, empty id or tab key) drops only that window.
- An empty reply (`{}`, what the script returns with no windows) gives no windows.

## Test scenarios

- `testChromiumReplyWithTwoWindowsZipsIntoTabs` — two windows zip into the right tabs and active tab.
- `testEmptyReplyGivesNoWindows` — `{}` gives no windows, in both dialects.
- `testIncognitoOrUnknownModeWindowIsDropped` — an incognito or unknown-mode window is dropped with its tabs.
- `testMissingValueUrlBecomesEmpty` — `missing value` for a URL becomes "".
- `testMalformedWindowIsDroppedAndOthersKept` — one malformed window is dropped, the rest kept.
- `testBoundsBecomeTopLeftRects` — bounds become top-left rects.
- `testSafariReplyMissingOneWindowParsesTheRest` — a Safari reply with one broken entry parses the rest.
