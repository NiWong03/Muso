import Foundation
import Combine

/// Recover the credited upload channel when catalog metadata has no artist.
@MainActor
final class VideoArtistResolver: ObservableObject {
    static let shared = VideoArtistResolver()
    private let session: URLSession
    @Published private var cache: [String: String]
    private let defaults: UserDefaults
    private static let cacheKey = "muso.artistMetadata.v1"
    private var pending: [String: Task<MusicVideo, Error>] = [:]

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        cache = defaults.dictionary(forKey: Self.cacheKey) as? [String: String] ?? [:]
    }

    func artist(for video: MusicVideo) -> String {
        Self.needsArtist(video) ? (cache[video.id] ?? video.channelTitle) : video.channelTitle
    }

    func resolveForDisplay(_ video: MusicVideo) async {
        guard Self.needsArtist(video) else { return }
        if let task = pending[video.id] { _ = try? await task.value; return }
        let task = Task { try await self.resolve(video) }
        pending[video.id] = task
        _ = try? await task.value
        pending[video.id] = nil
    }

    static func needsArtist(_ video: MusicVideo) -> Bool {
        let artist = video.channelTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return artist.isEmpty || ["youtube", "youtube music", "unknown", "unknown artist"].contains(artist)
    }

    func resolve(_ video: MusicVideo) async throws -> MusicVideo {
        guard Self.needsArtist(video) else { return video }
        let artist: String
        if let cached = cache[video.id] {
            artist = cached
        } else {
            var url = URLComponents(string: "https://www.youtube.com/oembed")!
            url.queryItems = [URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(video.id)"),
                              URLQueryItem(name: "format", value: "json")]
            var request = URLRequest(url: url.url!)
            request.timeoutInterval = 15
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw YouTubeServiceError.metadataUnavailable
            }
            struct Metadata: Decodable { let author_name: String }
            artist = try JSONDecoder().decode(Metadata.self, from: data).author_name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !artist.isEmpty else { throw YouTubeServiceError.metadataUnavailable }
            cache[video.id] = artist
            defaults.set(cache, forKey: Self.cacheKey)
        }
        return MusicVideo(id: video.id, title: video.title, channelTitle: artist, thumbnailURL: video.thumbnailURL)
    }

    func resolveMissing(_ videos: [MusicVideo]) async throws -> [MusicVideo] {
        var result: [MusicVideo] = []
        for video in videos {
            do { result.append(try await resolve(video)) }
            catch {
                try Task.checkCancellation()
                result.append(video)
            }
        }
        return result
    }
}
