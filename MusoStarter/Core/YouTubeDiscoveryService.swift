import Foundation

protocol YouTubeDiscovering {
    func trending() async throws -> [MusicVideo]
    func likedMusic() async throws -> [MusicVideo]
    func recommendations(seeds: [MusicVideo], excluding: Set<String>) async throws -> [MusicVideo]
    func homeRecommendations(seeds: [MusicVideo], excluding: Set<String>) async throws -> [MusicVideo]
}

extension YouTubeDiscovering {
    func homeRecommendations(seeds: [MusicVideo], excluding: Set<String>) async throws -> [MusicVideo] {
        try await recommendations(seeds: seeds, excluding: excluding)
    }
}

final class YouTubeDiscoveryService: YouTubeDiscovering {
    private let provider: YouTubeMusicProviding
    init(provider: YouTubeMusicProviding) { self.provider = provider }

    func trending() async throws -> [MusicVideo] { try await provider.trending() }
    func likedMusic() async throws -> [MusicVideo] { try await provider.likedMusic() }

    func recommendations(seeds: [MusicVideo], excluding: Set<String>) async throws -> [MusicVideo] {
        guard let seed = seeds.first else {
            return QueueDeduplicator.filter(try await trending(), excluding: [], ids: excluding)
        }
        let radio = try await provider.radio(videoID: seed.id)
        return QueueDeduplicator.filter(radio, excluding: seeds, ids: excluding)
    }

    func homeRecommendations(seeds: [MusicVideo], excluding: Set<String>) async throws -> [MusicVideo] {
        let home = QueueDeduplicator.filter(try await provider.home(), excluding: seeds, ids: excluding)
        if !home.isEmpty { return home }
        return try await recommendations(seeds: seeds, excluding: excluding)
    }
}
