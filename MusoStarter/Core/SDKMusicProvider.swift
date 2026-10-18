import Foundation
import YouTubeSDK

@MainActor
final class SDKMusicProvider: YouTubeMusicProviding {
    private let music = YouTubeMusicClient()
    private let charts = YouTubeChartsClient()
    private let accessToken: () async throws -> String?

    init(accessToken: @escaping () async throws -> String? = { nil }) {
        self.accessToken = accessToken
    }

    func search(_ query: String) async throws -> [MusicVideo] {
        let songs = try await music.search(query)
        try Task.checkCancellation()
        return unique(songs.map {
            MusicVideo(id: $0.videoId, title: $0.title,
                       channelTitle: $0.artistsDisplay.isEmpty ? "YouTube Music" : $0.artistsDisplay,
                       thumbnailURL: $0.thumbnailURL)
        })
    }

    func searchCatalog(_ query: String) async throws -> YouTubeSearchPage {
        let data = try await request("search", body: ["query": query])
        return YouTubeSearchPage(videos: try MusicResponseParser.videos(from: data), nextPageToken: nil,
                                 collections: try MusicCollectionParser.collections(from: data))
    }

    func tracks(in collection: MusicCollection) async throws -> [MusicVideo] {
        var body: [String: Any] = ["browseId": collection.id]
        var tracks: [MusicVideo] = []
        var tokens = Set<String>()
        repeat {
            let page = try MusicCollectionParser.tracks(from: await request("browse", body: body))
            tracks += page.videos
            guard let token = page.continuation else { return tracks }
            guard tokens.insert(token).inserted else { throw MusicDiscoveryError.invalidResponse }
            body = ["continuation": token]
            try Task.checkCancellation()
        } while true
    }

    func suggestions(_ query: String) async throws -> [String] {
        let values = try await music.getSearchSuggestions(query: query)
        try Task.checkCancellation()
        var seen = Set<String>()
        return Array(values.map(\.decodingHTMLEntities).filter { seen.insert($0.lowercased()).inserted }.prefix(8))
    }

    func trending() async throws -> [MusicVideo] {
        let items = try await charts.getTopSongs(country: Locale.current.region?.identifier ?? "US")
        try Task.checkCancellation()
        return Array(unique(items.map {
            MusicVideo(id: $0.id, title: $0.title, channelTitle: $0.subtitle, thumbnailURL: $0.thumbnailURL)
        }).prefix(30))
    }

    func likedMusic() async throws -> [MusicVideo] {
        try await browse("FEmusic_liked_videos")
    }

    func home() async throws -> [MusicVideo] {
        try await browse("FEmusic_home")
    }

    func radio(videoID: String) async throws -> [MusicVideo] {
        let data = try await request("next", body: ["videoId": videoID, "playlistId": "RDAMVM" + videoID,
                                                    "isAudioOnly": true, "enablePersistentPlaylistPanel": true])
        return try MusicResponseParser.videos(from: data)
    }

    private func browse(_ id: String) async throws -> [MusicVideo] {
        let data = try await request("browse", body: ["browseId": id], requiresSignIn: true)
        return try MusicResponseParser.videos(from: data)
    }

    private func request(_ endpoint: String, body: [String: Any], requiresSignIn: Bool = false) async throws -> Data {
        let headers = try await MusicRequestAuthorization.headers(requiresSignIn: requiresSignIn, accessToken: accessToken)
        let context = InnerTubeContext(client: .webRemix, gl: Locale.current.region?.identifier ?? "US")
        let client = NetworkClient(context: context, baseURL: YouTubeSDKConstants.URLS.API.youtubeMusicInnerTubeURL)
        let data = try await client.sendComplexRequest(endpoint, body: body, additionalHeaders: headers)
        try Task.checkCancellation()
        return data
    }

    private func unique(_ videos: [MusicVideo]) -> [MusicVideo] {
        var seen = Set<String>()
        return videos.filter { YouTubeVideoInput.videoID(from: $0.id) == $0.id && seen.insert($0.id).inserted }
    }
}
