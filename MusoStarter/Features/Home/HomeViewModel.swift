import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var trending: [MusicVideo] = []
    @Published private(set) var recommendations: [MusicVideo] = []
    @Published private(set) var liked: [MusicVideo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var personalError: String?
    private let discovery: YouTubeDiscovering
    private var generation = UUID()
    init(discovery: YouTubeDiscovering) { self.discovery = discovery }
    func resetPersonalization() {
        generation = UUID(); liked = []; recommendations = []; personalError = nil
    }
    func load(signedIn: Bool, recent: [MusicVideo]) async {
        let request = UUID(); generation = request
        isLoading = true; errorMessage = nil; personalError = nil
        if !signedIn { liked = []; recommendations = [] }
        defer { if generation == request { isLoading = false } }
        do {
            let results = try await discovery.trending()
            guard generation == request, !Task.isCancelled else { return }
            trending = results
        } catch { if generation == request && !Task.isCancelled { errorMessage = error.localizedDescription } }
        guard signedIn, generation == request, !Task.isCancelled else { return }
        var seeds = recent
        do {
            let likes = try await discovery.likedMusic()
            guard generation == request, !Task.isCancelled else { return }
            liked = likes
            seeds += likes
        } catch { if generation == request && !Task.isCancelled { personalError = error.localizedDescription } }
        guard generation == request, !Task.isCancelled else { return }
        do {
            let results = try await discovery.homeRecommendations(seeds: seeds, excluding: Set(seeds.map(\.id)))
            guard generation == request, !Task.isCancelled else { return }
            recommendations = results
        } catch { if generation == request && !Task.isCancelled { personalError = error.localizedDescription } }
    }
}
