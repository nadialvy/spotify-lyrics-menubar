import Foundation

struct LyricLine {
    let time: Double
    let text: String
}

private struct LyricsResponse: Decodable {
    let syncedLyrics: String?
    let plainLyrics: String?

    var hasLyrics: Bool {
        !(syncedLyrics?.isEmpty ?? true) || !(plainLyrics?.isEmpty ?? true)
    }
}

enum LyricsFetcher {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 6
        return URLSession(configuration: config)
    }()

    private static let lrcRegex = try! NSRegularExpression(pattern: #"\[(\d+):(\d+\.?\d*)\](.*)"#)

    static func fetch(track: String, artist: String, duration: Double) -> ([LyricLine], Bool) {
        let cleanTrack = track
            .replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let cleanArtist = (artist.components(separatedBy: ",").first ?? artist)
            .trimmingCharacters(in: .whitespaces)

        let trackEnc = cleanTrack.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanTrack
        let artistEnc = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanArtist

        let directURL = URL(string: "https://lrclib.net/api/get?track_name=\(trackEnc)&artist_name=\(artistEnc)&duration=\(Int(duration))")!
        var payload = fetchSync(url: directURL)

        if payload == nil {
            let searchURL = URL(string: "https://lrclib.net/api/search?track_name=\(trackEnc)&artist_name=\(artistEnc)")!
            if let searchData = fetchSync(url: searchURL),
               let arr = try? JSONSerialization.jsonObject(with: searchData) as? [[String: Any]],
               let entry = selectEntryWithLyrics(from: arr),
               let entryData = try? JSONSerialization.data(withJSONObject: entry) {
                payload = entryData
            }
        }

        guard let data = payload,
              let response = try? JSONDecoder().decode(LyricsResponse.self, from: data),
              response.hasLyrics else {
            return ([], false)
        }

        if let synced = response.syncedLyrics, !synced.isEmpty {
            return (parseLRC(synced), true)
        } else if let plain = response.plainLyrics, !plain.isEmpty, duration > 0 {
            let lines = plain
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { return ([], false) }
            let step = duration / Double(lines.count)
            let result = lines.enumerated().map { LyricLine(time: Double($0.offset) * step, text: $0.element) }
            return (result, false)
        }
        return ([], false)
    }

    static func selectEntryWithLyrics(from arr: [[String: Any]]) -> [String: Any]? {
        func nonEmptyString(_ value: Any?) -> Bool {
            if let s = value as? String { return !s.isEmpty }
            return false
        }
        return arr.first { nonEmptyString($0["syncedLyrics"]) || nonEmptyString($0["plainLyrics"]) }
    }

    private static func fetchSync(url: URL) -> Data? {
        var request = URLRequest(url: url)
        request.setValue("LyricsMenuBar v2.0 (personal use)", forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        let task = session.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                result = data
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 6)
        return result
    }

    private static func parseLRC(_ text: String) -> [LyricLine] {
        var result: [LyricLine] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            let range = NSRange(s.startIndex..., in: s)
            guard let match = lrcRegex.firstMatch(in: s, range: range) else { continue }
            let ns = s as NSString
            let minutes = ns.substring(with: match.range(at: 1))
            let seconds = ns.substring(with: match.range(at: 2))
            let body = ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty,
                  let m = Double(minutes),
                  let sec = Double(seconds) else { continue }
            result.append(LyricLine(time: m * 60 + sec, text: body))
        }
        return result.sorted { $0.time < $1.time }
    }
}
