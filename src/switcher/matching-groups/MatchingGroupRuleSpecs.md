# MatchingGroupRule — Specs

## Summary

`MatchingGroupRule` is one stored matching group (see `MatchingGroupResolverSpecs.md`). The list is saved as a
JSON string under `matchingGroups` (`Preferences.jsonEncodedKeys`), on every edit in Settings.

Groups must never get lost. `CachedUserDefaults.getThenConvertOrReset` deletes a key it can't decode, so:
- the list is decoded element by element through `LenientDecodable`, and a malformed element drops only itself;
- `init(from:)` defaults every field except `predicateFormat`, so data written before a field existed decodes.

`Array.moved(from:to:)` is the reorder behind drag and drop in Settings: `NSTableView` reports an `.above`
drop index counted before the dragged row is removed.

## Test scenarios

Mirrors `MatchingGroupRuleTests.swift` 1:1.

### A. Persistence
- **testSaveThenReloadKeepsEveryField** — encode then `decodeList` gives the same rules.
- **testOldShapeWithMissingFieldsGetsDefaults** — only `predicateFormat` present: empty name, enabled.
- **testCorruptEntryIsDroppedAndTheOthersKept** — an entry without `predicateFormat` and a non-object are
  dropped; the rest survive in order.

### B. Reordering
- **testMovingDownCountsTheDestinationBeforeTheRemoval** — dropping below lands before the row at `to`.
- **testMovingUp** — dropping above an earlier row.
- **testDroppingOntoItselfChangesNothing** — `to == from` and `to == from + 1` are no-ops.
