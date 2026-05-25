import XCTest
@testable import LyricsMenuBar

/// Reproducer for the "no lyrics found" bug.
///
/// `LyricsFetcher.fetch()` uses a private, hard-coded ephemeral `URLSession`, so its
/// network calls cannot be intercepted by a registered `URLProtocol` (an ephemeral
/// session does not consult globally-registered protocol classes). To reproduce the
/// bug deterministically and offline, this test exercises the EXACT fallback
/// selection-and-decode pipeline from `fetch()` (LyricsFetcher.swift lines 38-63),
/// reproduced here verbatim, driven by the real JSON shape lrclib.net returns.
///
/// The bug: on the /api/search fallback the code blindly takes `arr.first` and decodes
/// it. When the first search result is an instrumental/empty entry
/// (syncedLyrics == null, plainLyrics == null) while a LATER entry has real lyrics,
/// the user sees "(no lyrics found)".
final class LyricsFetcherTests: XCTestCase {

    private struct LyricsResponse: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    /// Verbatim copy of the fallback + decode logic from
    /// LyricsFetcher.fetch() lines 38-63. Production is NOT modified.
    private func reproduceFetchOutcome(searchData: Data, duration: Double) -> ([String], Bool) {
        var payload: Data?

        // --- lines 38-43: blindly take arr.first ---
        if let arr = try? JSONSerialization.jsonObject(with: searchData) as? [[String: Any]],
           let first = arr.first,
           let firstData = try? JSONSerialization.data(withJSONObject: first) {
            payload = firstData
        }

        // --- lines 46-63: decode and classify ---
        guard let data = payload,
              let response = try? JSONDecoder().decode(LyricsResponse.self, from: data) else {
            return ([], false)
        }
        if let synced = response.syncedLyrics, !synced.isEmpty {
            let lines = synced.split(separator: "\n").map(String.init)
            return (lines, true)
        } else if let plain = response.plainLyrics, !plain.isEmpty, duration > 0 {
            let lines = plain.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return (lines, false)
        }
        return ([], false)
    }

    func testSearchFallbackReturnsLyricsWhenFirstResultHasNone() {
        // Real lrclib.net /api/search shape: first item is instrumental/empty,
        // a later item carries the actual synced lyrics.
        let searchBody = """
        [
          {"id":1,"trackName":"The Winner Takes It All","artistName":"ABBA","albumName":"Super Trouper","duration":295,"instrumental":true,"plainLyrics":null,"syncedLyrics":null},
          {"id":2,"trackName":"The Winner Takes It All","artistName":"ABBA","albumName":"Super Trouper","duration":295,"instrumental":false,"plainLyrics":"I don't wanna talk\\nAbout things we've gone through","syncedLyrics":"[00:24.10] I don't wanna talk\\n[00:30.50] About things we've gone through"}
        ]
        """.data(using: .utf8)!

        let (lines, synced) = reproduceFetchOutcome(searchData: searchBody, duration: 295)

        XCTAssertFalse(lines.isEmpty,
            "BUG: fetch() took arr.first (instrumental, no lyrics) and returned nothing, " +
            "even though search result #2 has synced lyrics. User sees '(no lyrics found)'.")
        XCTAssertTrue(synced, "Expected synced lyrics from search result #2")
    }
}
