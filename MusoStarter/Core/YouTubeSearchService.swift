import Foundation

struct YouTubeSearchPage {
    let videos: [MusicVideo]
    let nextPageToken: String?
    var collections: [MusicCollection] = []
}

protocol YouTubeSearching {
    func tracks(in collection: MusicCollection) async throws -> [MusicVideo]
    func search(query: String, pageToken: String?) async throws -> YouTubeSearchPage
    func suggestions(query: String) async throws -> [String]
}

extension YouTubeSearching {
    func tracks(in collection: MusicCollection) async throws -> [MusicVideo] { throw MusicDiscoveryError.invalidResponse }
}

final class YouTubeSearchService: YouTubeSearching {
    private let provider: YouTubeMusicProviding
    init(provider: YouTubeMusicProviding) { self.provider = provider }

    func search(query: String, pageToken: String? = nil) async throws -> YouTubeSearchPage {
        // The SDK's music search returns a complete batch without a continuation token.
        guard pageToken == nil else { return YouTubeSearchPage(videos: [], nextPageToken: nil) }
        let page = try await provider.searchCatalog(query)
        try Task.checkCancellation()
        return page
    }

    func tracks(in collection: MusicCollection) async throws -> [MusicVideo] {
        try await provider.tracks(in: collection)
    }

    func suggestions(query: String) async throws -> [String] {
        try await provider.suggestions(query)
    }
}
