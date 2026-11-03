# BrowserTabRowsDiff — Specs

## Summary

Turns a fresh `BrowserSnapshot` plus the matcher's `scriptId → wid` pairs into the tab rows that should exist
(`wantedRefs`), names each row (`rowId`), and reconciles those names with the rows already in `Windows.list`
(`diff`). `BrowserTabs.apply` is the shell that acts on the result.

- A matched window gets one row per tab **except its active tab**: the window's own row already is that tab.
  A window with one tab, or an unmatched window, adds nothing.
- `slot` is the 1-based strip position among the non-active tabs; tab rows sort after their window by it.
  `stripIndex` is the position in the whole strip, which Safari switches tabs by.
- Row id: `btab-<pid>-<scriptWindowId>-<tab key>`. The prefix keeps it apart from `wid-N` and `pid-N`, and
  selection follows rows by id, so a row keeps its selection across reads while its key is stable.

## Behavior & edge cases

- A tab dragged to another window changes `scriptWindowId`, so it is a remove plus an insert.
- Safari keys are `"index|URL"`, so a moved Safari tab is a remove plus an insert too.

## Test scenarios

- `testUnchangedKeepsAll` — unchanged → keep all.
- `testNewTabIsInserted` — a new tab → insert.
- `testClosedTabIsRemoved` — a closed tab → remove.
- `testActiveTabChangeSwapsWhichTabHasARow` — the active tab changed → the old active tab gets a row and the
  new one loses its row.
- `testSafariTabMovedIsRemoveAndInsert` — a Safari tab moved (index key changed) → remove and insert.
- `testSlotsFollowStripOrderSkippingTheActiveTab` — slots follow strip order, skipping the active tab.
- `testUnmatchedOrSingleTabWindowWantsNoRows` — unmatched or single-tab windows want no rows.
