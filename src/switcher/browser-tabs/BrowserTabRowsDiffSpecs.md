# BrowserTabRowsDiff — Specs

## Summary

Turns a fresh `BrowserSnapshot` plus the matcher's `scriptId → wid` pairs into the tab rows that should exist
(`wantedRefs`), names each row (`rowId`), and reconciles those names with the rows already in `Windows.list`
(`diff`). `BrowserTabs.apply` is the shell that acts on the result.

- Every tab gets a row, **the active tab included**, so each tab shows its own title and site icon. The window
  keeps its own row, titled by the browser (which may be a custom window name).
- The matcher only decides placement, never whether a tab is listed. An unmatched window's rows have no
  `parentWid`: they are shown and sorted with the browser's least recently used shown window
  (`BrowserTabs.anchor`), and switching to one has the script raise its window.
- `slot` is the 1-based strip position; tab rows sort after their window by it. Unmatched rows count on from
  `unmatchedSlotBase` across all unmatched windows, so they follow any matched rows of their anchor and each
  window's tabs stay together. `stripIndex` is the position in the strip, which Safari switches tabs by.
- Row id: `btab-<pid>-<scriptWindowId>-<tab key>`. The prefix keeps it apart from `wid-N` and `pid-N`, and
  selection follows rows by id, so a row keeps its selection across reads while its key is stable.

## Behavior & edge cases

- Switching tabs within a window changes no rows: the active tab isn't special.
- A tab dragged to another window changes `scriptWindowId`, so it is a remove plus an insert.
- Safari keys are `"index|URL"`, so a moved Safari tab is a remove plus an insert too.

## Test scenarios

- `testUnchangedKeepsAll` — unchanged → keep all.
- `testNewTabIsInserted` — a new tab → insert.
- `testClosedTabIsRemoved` — a closed tab → remove.
- `testActiveTabChangeKeepsEveryRow` — the active tab changed → every row is kept.
- `testSafariTabMovedIsRemoveAndInsert` — Safari tabs moved (index keys changed) → remove and insert.
- `testEveryTabGetsARowInStripOrder` — every tab, the active one included, gets a row; slots follow strip order.
- `testSingleTabWindowGetsARow` — a window with one tab still gets a row for it.
- `testUnmatchedWindowsAreListedWithoutParentAfterMatchedRows` — unmatched windows' tabs are listed with no
  parent and slots from `unmatchedSlotBase`, continuing across unmatched windows.
