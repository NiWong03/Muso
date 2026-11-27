import Foundation

struct LyricsQuery: Hashable {
    let artist: String
    let song: String

    init(video: MusicVideo) {
        var title = video.title.replacingOccurrences(
            of: #"(?i)[\(\[]\s*(?:official\s*(?:music\s*)?(?:video|audio)?|lyrics?(?:\s+video)?|visualizer|hd|4k)\s*[\)\]]"#,
            with: "", options: .regularExpression)
        var credit = video.channelTitle.replacingOccurrences(of: #"(?i)(\s*-\s*topic|vevo|\s+official)$"#, with: "", options: .regularExpression)
        if let separator = title.range(of: " - ") ?? title.range(of: " – ") {
            credit = String(title[..<separator.lowerBound])
            title = String(title[separator.upperBound...])
        }
        title = title.replacingOccurrences(of: #"(?i)\s*[-–]\s*(?:official\s+)?(?:music\s+video|video|audio|lyrics?)$"#, with: "", options: .regularExpression)
        let cleanedArtist = credit.trimmingCharacters(in: .whitespacesAndNewlines)
        artist = ["youtube", "youtube music", "unknown", "unknown artist"].contains(cleanedArtist.lowercased()) ? "" : cleanedArtist
        song = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TimedLyricWord: Decodable {
    let word: String
    let start: Double
    let end: Double
}

struct TimedLyricLine: Decodable {
    let text: String
    let startTime: Double
    let endTime: Double?
    let words: [TimedLyricWord]?
    enum CodingKeys: String, CodingKey {
        case text, words
        case startTime = "start_time", endTime = "end_time"
    }
}

struct LyricaLyrics: Decodable {
    let source: String
    let artist: String
    let title: String
    let lyrics: String
    let hasTimestamps: Bool
    let timedLines: [TimedLyricLine]
    enum CodingKeys: String, CodingKey {
        case source, artist, title, lyrics, hasTimestamps
        case timedLines = "timed_lyrics"
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decode(String.self, forKey: .source)
        artist = try values.decode(String.self, forKey: .artist)
        title = try values.decode(String.self, forKey: .title)
        lyrics = try values.decodeIfPresent(String.self, forKey: .lyrics) ?? ""
        hasTimestamps = try values.decodeIfPresent(Bool.self, forKey: .hasTimestamps) ?? false
        let lines = (try? values.decode([TimedLyricLine].self, forKey: .timedLines)) ?? []
        timedLines = hasTimestamps ? lines.filter { $0.startTime.isFinite && $0.startTime >= 0 }
            .sorted { $0.startTime < $1.startTime } : []
    }
    var staticText: String { lyrics.isEmpty ? timedLines.map(\.text).joined(separator: "\n") : lyrics }

    func activeLine(at seconds: Double) -> Int? {
        guard seconds.isFinite else { return nil }
        let milliseconds = seconds * 1000
        guard let index = timedLines.lastIndex(where: { $0.startTime <= milliseconds }) else { return nil }
        if let end = timedLines[index].endTime, end > timedLines[index].startTime, milliseconds >= end { return nil }
        return index
    }
}

enum LyricaError: LocalizedError {
    case invalidServer, missingTrack, unavailable, server(Int)
    var errorDescription: String? {
        switch self {
        case .invalidServer: return "Enter a valid Lyrica server URL in Settings."
        case .missingTrack: return "This track is missing its artist or title."
        case .unavailable: return "No lyrics found for this track."
        case .server(let code): return "The lyrics server returned an error (\(code))."
        }
    }
}

@MainActor
final class LyricaService {
    static let shared = LyricaService()
    static let serverKey = "lyricaServerURL"
    static var defaultServer: String {
        #if targetEnvironment(simulator)
        "http://127.0.0.1:9999"
        #else
        "http://192.168.7.99:9999"
        #endif
    }
    private struct Envelope: Decodable {
        let status: String
        let data: LyricaLyrics?
    }
    private let session: URLSession
    private var cache: [URL: LyricaLyrics] = [:]

    init(session: URLSession = .shared) { self.session = session }

    func request(query: LyricsQuery, server: String, timestamps: Bool = true) throws -> URLRequest {
        guard !query.artist.isEmpty, !query.song.isEmpty else { throw LyricaError.missingTrack }
        guard var components = URLComponents(string: server.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { throw LyricaError.invalidServer }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + (components.path.isEmpty ? "" : components.path + "/") + "lyrics/"
        components.queryItems = [URLQueryItem(name: "artist", value: query.artist), URLQueryItem(name: "song", value: query.song),
                                 URLQueryItem(name: "timestamps", value: timestamps ? "true" : "false"),
                                 URLQueryItem(name: "word", value: timestamps ? "true" : "false")]
        components.fragment = nil
        guard let url = components.url else { throw LyricaError.invalidServer }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func lyrics(query: LyricsQuery, server: String) async throws -> LyricaLyrics {
        let request = try request(query: query, server: server)
        let key = request.url!
        if let cached = cache[key] { return cached }
        let result: LyricaLyrics
        do {
            result = try await fetch(request)
        } catch {
            try Task.checkCancellation()
            // Timed-only searches can miss a track that has plain lyrics.
            result = try await fetch(self.request(query: query, server: server, timestamps: false))
        }
        if cache.count >= 100 { cache.removeAll() }
        cache[key] = result
        return result
    }

    private func fetch(_ request: URLRequest) async throws -> LyricaLyrics {
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw LyricaError.unavailable }
        if response.statusCode == 404 { throw LyricaError.unavailable }
        guard (200..<300).contains(response.statusCode) else { throw LyricaError.server(response.statusCode) }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.status == "success", let result = envelope.data,
              !result.staticText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LyricaError.unavailable }
        return result
    }
}
