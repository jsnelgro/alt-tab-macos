# MatchingGroupResolver — Specs

## Summary

Matching groups split the Titles list into named sections. The user keeps an ordered list of
`MatchingGroupRule`s (`Preferences.matchingGroups`), each a name, an `NSPredicate` format over
`MatchingGroupFacts` (`title`, `app`, `bundleId`) and an enabled switch. The order is both the draw order of
the sections and the priority when a window matches several rules. Grouping is turned on per shortcut
(`matchingGroupsEnabled`), and only applies when that shortcut's style is Titles and at least one group is
enabled (`Windows.matchingGroupsActive`).

`MatchingGroupResolver` is the pure part:
- `compile` keeps the enabled rules in order, with their parsed predicate (nil when the format failed to
  load; the shell parses through `ObjCExceptionCatcher` in `MatchingGroups.parse`).
- `rank` is the index of the first predicate the window's facts match, or the number of predicates ("Other").
- `pinnedBestMatch` picks the one window drawn first, outside any section, during a search. The shell only
  pins while `matchingGroupsPinTopResult` (Settings → Groups → "Pin top result", global, on by default) is on;
  off, search results stay entirely in their sections.
- `sectionStarts` turns the drawn tiles' ranks into the positions that get a header.

## Behavior & edge cases

- First match wins; a window is never in two groups. A nil predicate never matches.
- No enabled group → `matchingGroupsActive` is false, every rank is 0, and the list is exactly the flat one.
- Every enabled group failed to load → every window is "Other": one section, so no headers.
- `MATCHES` is an ICU regex over the whole string: `Project` doesn't match "Project Alpha", `^Project.*` does.
- The editor builds case-insensitive comparisons (`[c]`).
- A windowless placeholder has an empty title; a nil app name is evaluated as "".
- Section starts: a section opens at the first unpinned tile and at every rank change after it. The pinned tile
  is never a start and isn't "the previous tile". One section draws no headers, except when a pinned tile sits
  above it: then the header separates the pin from the rest. A lone pinned tile draws none.
- Ordering inside a section, the show-at-the-end buckets, and search ordering are `WindowOrderResolver`'s.
- The default selection is judged in the ungrouped order (`SelectionWindow.ungroupedPosition`), so a quick
  press still returns to the previous window when grouping moved it down the list.

## Test scenarios

Mirrors `MatchingGroupResolverTests.swift` 1:1.

### A. Ranks
- **testFirstMatchWinsWhenTwoRulesMatch** — two matching rules; the first one wins.
- **testDisabledRulesAreSkipped** — `compile` drops disabled rules, so ranks count enabled ones only.
- **testNilPredicateNeverMatches** — a rule that failed to load keeps its slot and never matches.
- **testNoMatchIsOther** — no match ranks as `predicates.count`.
- **testEmptyListRanksEveryoneZero** — no rules, rank 0 for everyone.
- **testMatchesIsAFullStringMatch** — `MATCHES 'Project'` fails on "Project Alpha"; `'^Project.*'` matches.
- **testComparisonsIgnoreCase** — `[c]` comparisons ignore case.
- **testNilAppNameEvaluatesAsEmpty** — a nil app name is "", and bundle-ID rules still match.

### B. Best-match pinning
- **testPinnedBestMatchIsTheHighestRelevance** — highest search relevance is pinned.
- **testPinnedBestMatchTiesGoToTheMostRecentlyFocused** — equal relevance goes to the lowest `lastFocusOrder`.
- **testPinnedBestMatchIsNilWithoutCandidates** — nothing matches, nothing is pinned.

### C. Section starts
- **testAllTilesInOneRankDrawNoHeaders** — one section, no headers.
- **testEachRankChangeOpensASection** — `[0,0,1,2]` gives `[0,2,3]`.
- **testPinnedAndTheRestInOneRankHeadsTheRest** — pinned plus one section: a header after the pin.
- **testPinnedTilesOwnGroupContinuingGetsAHeaderAfterThePin** — the pin's own group continues below it and
  still gets its header.
- **testASinglePinnedTileDrawsNoHeaders** — a lone pinned tile, no headers.
