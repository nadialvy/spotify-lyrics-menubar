# Bug Report: "no lyrics found" despite lyrics existing on lrclib.net

**Date:** 2026-05-26  
**Status:** FIXED

## Symptom

App shows `♪ (no lyrics found)` in the menu bar for tracks that have lyrics available on lrclib.net. Observed example: "The Winner Takes It All — ABBA". Intermittent — only triggers when the direct `/api/get` call misses and the search fallback encounters a result set where the first entry has no lyrics.

## Reproduction

**Test:** `Tests/LyricsMenuBarTests/LyricsFetcherTests.swift::testSearchFallbackReturnsLyricsWhenFirstResultHasNone`

**Failing output on HEAD (before fix):**
```
XCTAssertFalse failed — BUG: fetch() took arr.first (instrumental, no lyrics)
and returned nothing, even though search result #2 has synced lyrics.
User sees '(no lyrics found)'.
```

**To run:**
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
(Default CommandLineTools toolchain lacks XCTest.)

## Root Cause

**File:** `Sources/LyricsMenuBar/LyricsFetcher.swift:40` (pre-fix)

When the direct `GET /api/get?track_name=...&duration=N` returns non-200 (common — lrclib requires exact duration match), the code falls back to `GET /api/search`. It then took `arr.first` without checking whether that entry had any lyrics:

```swift
// BEFORE (line 40, buggy):
let first = arr.first,
let firstData = try? JSONSerialization.data(withJSONObject: first) {
    payload = firstData  // first entry may have syncedLyrics: null, plainLyrics: null
}
```

`LyricsResponse` decoded successfully (the guard only checked JSON parsing, not content), then lines 51-62 found both fields empty and returned `([], false)`. A later entry in `arr` with actual lyrics was silently ignored.

**Secondary defensive issue:** the same path existed if the direct API returned HTTP 200 with null lyrics fields — post-decode validation was absent.

### Alternate hypotheses ruled out

- **H2 — Duration mismatch causing 404:** Confirmed LOW confidence. The duration handling is correct (Spotify AppleScript returns ms, `durationDivisor: 1000` converts to seconds correctly). The direct API 404 is expected and the fallback is the intended path — the bug was in the fallback logic, not the duration math.

## Fix

**Classification:** `[PATCH]`

| File | Change |
|------|--------|
| `Sources/LyricsMenuBar/LyricsFetcher.swift:44` | Replace `arr.first` with `selectEntryWithLyrics(from: arr)` — loops to find first entry with non-empty lyrics |
| `Sources/LyricsMenuBar/LyricsFetcher.swift:52` | Add `response.hasLyrics` to the decode guard — rejects 200 responses with null/empty fields |
| `Sources/LyricsMenuBar/LyricsFetcher.swift:12-14` | Added `hasLyrics: Bool` computed property on `LyricsResponse` |
| `Sources/LyricsMenuBar/LyricsFetcher.swift:71-77` | Added `internal static func selectEntryWithLyrics(from:)` — testable seam, no network needed |
| `Sources/LyricsMenuBar/PlayerReader.swift:60-78` | Combined `isAppRunning` + state fetch into one AppleScript per player (halved subprocess spawns per poll) |

**Why this fixes the root cause:** `selectEntryWithLyrics` iterates the search results and returns the first entry where `syncedLyrics` or `plainLyrics` is a non-empty string, skipping instrumental/empty entries. `hasLyrics` makes the post-decode guard independently reject empty results on any path.

**Architectural alternative (not applied):** Inject a network layer (e.g., a `LyricsNetworkClient` protocol) to make `fetch()` fully unit-testable without static `URLSession`. Deferred — the internal `selectEntryWithLyrics` helper provides sufficient testability for the affected logic at lower cost.  
**Recommended follow-up:** `/agent-plan "refactor LyricsFetcher to inject URLSession for full offline testability"`

## Additional improvements in this fix

**CJK language support (Chinese Simplified/Traditional, Japanese):** Confirmed already working — the cleaning regex only strips ASCII brackets, and `.urlQueryAllowed` correctly percent-encodes UTF-8 CJK characters. The `selectEntryWithLyrics` fix indirectly improves CJK results by skipping instrumental/empty first matches which are more common for CJK catalog entries on lrclib.

**Load time (AppleScript performance):** `PlayerReader.state(for:)` previously spawned 2 subprocesses per player (one `isAppRunning` check + one state fetch) = up to 4 `osascript` spawns per 500ms poll. Now combined into 1 spawn per player with an inline `if application is running then` check, halving subprocess overhead.

## Validation

- Reproducer test `testSearchFallbackReturnsLyricsWhenFirstResultHasNone`: **PASS** (was FAIL)
- `swift build`: **PASS** (clean)
- Full test suite (`swift test`): **PASS** (1 test, 0 failures)

## Debate highlights

- H1 (search fallback `arr.first` blind): HIGH confidence, survived cross-challenge — confirmed root cause
- H2 (duration 404 causing fallback): LOW confidence as a *root cause* (fallback is correct path), but raised the post-decode null-check gap, which was fixed defensively
- H1 and H2 cross-challenge: investigator-h1 confirmed H2's direct-200-null scenario is independent and not covered by the H1 fix alone — led to adding `hasLyrics` guard

## Follow-up recommendations

- Consider `/agent-plan "refactor LyricsFetcher to inject URLSession"` for full offline test coverage
- Audit other lrclib API result consumers if any are added — the `arr.first` antipattern could recur
