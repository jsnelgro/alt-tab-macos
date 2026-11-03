# BrowserFaviconPicker — Specs

## Summary

Tab rows show the site's icon instead of the browser's, read from the browser's own `Favicons` cache (Chromium's
SQLite file in each profile folder) by `BrowserFavicons`. No network is used. `BrowserFaviconPicker` is the pure
part of that lookup:

- `bestBitmap` picks which stored size to draw: the smallest at least `preferredWidth` (64 px, a ~32 pt tile
  icon on a 2x screen), else the largest. Chromium usually keeps 16 and 32 px, so in practice the 32 px one.
- `siteRanges` gives the `page_url` key ranges for a tab's site, used when the tab's exact URL isn't cached
  (a page opened but not yet visited long enough, a URL with a fresh query string). Both schemes, with and
  without `www.`. Ranges rather than `LIKE`, so the lookup uses the `page_url` index.

## Behavior & edge cases

- The exact URL wins over the site; among the site's pages, the shortest URL (closest to the root) wins. That
  choice is made in SQL by `BrowserFavicons`.
- Only http(s) URLs with a host have a site: `chrome://`, `about:blank` and `file:` tabs keep the browser icon.
- A range is `[prefix, prefix with its last character incremented)`, so `https://github.com/` covers
  `https://github.com/apple/swift` but not `https://github.community/` or `https://gist.github.com/`.

## Shell behavior (`BrowserFavicons`)

- Off by default. Settings → Browser tabs → "Show site icons" turns it on, and that click is the first time
  each installed browser's cache is touched, so any macOS prompt ("access data from other apps") follows it.
  Reads then only go to browsers checked that way, so the switcher never causes a prompt.
- The cache is copied before it is opened: the browser keeps the live file open.
- A URL that wasn't in the cache isn't asked for again until the cache file changes.
- macOS refusing the folder marks the browser "Icons blocked" in Settings, with a button to System Settings.

## Test scenarios

- `testSmallestBitmapAtLeastThePreferredWidthWins` — the smallest size at least the preferred width wins.
- `testLargestBitmapWinsWhenAllAreSmaller` — all smaller → the largest.
- `testNoBitmapsNoPick` — no bitmaps → nil.
- `testSiteRangesCoverBothSchemesWithAndWithoutWww` — four ranges, host lowercased, `www.` folded.
- `testSiteRangesContainTheSitesPagesOnly` — the range holds the site's pages and no look-alike host.
- `testNonWebUrlsHaveNoSite` — non-web URLs have no site.
