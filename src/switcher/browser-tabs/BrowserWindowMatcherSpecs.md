# BrowserWindowMatcher — Specs

## Summary

A Chromium script window's `id` is the browser's internal number, not a `CGWindowID`, so its tabs can only be
attached to an AltTab window by pairing frames and titles. `BrowserWindowMatcher.match(_:_:)` gets the script
windows of one browser and the tracked windows of the **same pid** (Chromium PWA windows run in another pid and
are never passed in), and returns `scriptId → wid`.

Rules, each a pass over the script windows still unmatched:

1. Frame equal (each edge within 2 pt) **and** the active tab's title equals the tracked title, or the tracked
   title begins with it (Chromium can append a profile name such as " - Work").
2. Frame equal.
3. Title equal (same prefix rule).

A pair is taken only when it is unique both ways: exactly one free tracked window fits the script window, and
no other unmatched script window fits that tracked window. Otherwise the script window stays unmatched: a wrong
pair would focus the wrong window. An unmatched window's tabs are still listed (see `BrowserTabRowsDiffSpecs.md`);
the match only decides where they sit and which window AltTab focuses.

## Behavior & edge cases

- Two windows with one frame (stacked, or both fullscreen on one screen) are told apart by title.
- A minimized window keeps its last frame in both sources, so it still matches.
- A script window that isn't tracked yet stays unmatched until the next read.
- An empty active-tab title never matches by title.

## Test scenarios

- `testFrameAndTitleMatch` — frame + title match.
- `testTitleWithProfileSuffixMatches` — a tracked title with a profile suffix matches.
- `testTwoWindowsWithOneFrameToldApartByTitle` — two windows with one frame are told apart by title.
- `testFrameOnlyMatchWhenUnique` — a frame-only match when it is unique.
- `testTitleOnlyMatchWhenUnique` — a title-only match when it is unique.
- `testAmbiguousStaysUnmatched` — ambiguous → unmatched.
- `testEachTrackedWindowMatchedAtMostOnce` — each tracked window is matched at most once.
- `testNoCandidatesNoMatches` — no candidates → no matches.
