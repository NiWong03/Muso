import Foundation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var video: MusicVideo?
    @Published private(set) var isLoading = false
    @Published private(set) var isResolvingPlayback = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var collections: [MusicCollection] = []
    @Published private(set) var results: [MusicVideo] = []
    @Published private(set) var nextPageToken: String?
    @Published private(set) var hasSearched = false
    private var searchedQuery = ""
    private var accountSignals: [MusicVideo] = []
    private let searchService: YouTubeSearching?
    private let service: YouTubeServing

    init(service: YouTubeServing, searchService: YouTubeSearching? = nil) {
        self.service = service
        self.searchService = searchService
    }

    func setPersonalization(_ signals: [MusicVideo]) {
        accountSignals = signals
    }

    enum Result: Identifiable {
        case track(MusicVideo)
        case collection(MusicCollection)

        var id: String {
            switch self {
            case .track(let video): return "track:" + video.id
            case .collection(let collection): return "collection:" + collection.id
            }
        }
    }

    var rankedResults: [Result] {
        let signals = accountSignals.filter { !artistKey($0).isEmpty }
        let artists = signals.map { artistKey($0) }
        let titles = signals.map { titleWords($0.title) }
        let items = results.map(Result.track) + collections.map(Result.collection)
        let scored = items.enumerated().map { index, item -> (item: Result, score: Double, index: Int) in
            let score: Double
            switch item {
            case .track(let video):
                score = relevance(title: video.title, subtitle: video.channelTitle)
                    + min(3, affinity(video, artists: artists, titles: titles))
            case .collection(let collection):
                score = relevance(title: collection.title, subtitle: collection.subtitle)
            }
            return (item, score, index)
        }
        return scored.sorted {
            $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score
        }.map(\.item)
    }

    private func relevance(title: String, subtitle: String) -> Double {
        func words(_ text: String) -> [String] {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        }
        let queryWords = words(searchedQuery)
        guard !queryWords.isEmpty else { return 0 }
        let queryTokens = Set(queryWords)
        let titleWords = words(title)
        let titleTokens = Set(titleWords)
        let combined = titleTokens.union(words(subtitle))
        let titleMatches = Double(queryTokens.intersection(titleTokens).count)
        let coverage = Double(queryTokens.intersection(combined).count) / Double(queryTokens.count)
        let phrase = queryWords.joined(separator: " ")
        let normalizedTitle = titleWords.joined(separator: " ")
        let exact = normalizedTitle == phrase
        let containsPhrase = (" " + normalizedTitle + " ").contains(" " + phrase + " ")
        // Query coverage dominates; concise title matches beat broad playlist titles.
        return 60 * coverage + 25 * titleMatches / Double(queryTokens.count)
            + 10 * titleMatches / Double(max(titleTokens.count, 1))
            + (exact ? 30 : containsPhrase ? 12 : 0)
    }

    private func affinity(_ video: MusicVideo, artists: [String], titles: [Set<String>]) -> Double {
        let artist = artistKey(video)
        let artistTokens = Set(artist.split(separator: " ").map(String.init))
        let title = titleWords(video.title)
        var score = 0.0
        for (index, listenedArtist) in artists.enumerated() {
            let recency = 1.0 / Double(index + 1).squareRoot()
            if artist == listenedArtist { score += 8 * recency }
            else {
                let tokens = Set(listenedArtist.split(separator: " ").map(String.init))
                if tokens.count > 1 { score += 2 * recency * Double(artistTokens.intersection(tokens).count) / Double(tokens.count) }
            }
            let overlap = title.intersection(titles[index]).count
            if overlap > 1 { score += recency * Double(overlap) / Double(max(title.count, titles[index].count)) }
        }
        return score
    }

    private func artistKey(_ video: MusicVideo) -> String {
        let identity = video.songIdentity
        return String(identity.split(separator: "|", maxSplits: 1).first ?? "")
    }

    private func titleWords(_ title: String) -> Set<String> {
        let normalized = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"(?i)[\(\[]\s*(?:official|music video|audio|lyrics?|visualizer|hd|4k)[^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        return Set(normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
    }

    private var generation = UUID()
    func reset() {
        generation = UUID(); collections = []; results = []; accountSignals = []; video = nil; nextPageToken = nil; errorMessage = nil; hasSearched = false
    }

    func search(loadMore: Bool = false) async {
        guard !isLoading, !isResolvingPlayback else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let request = generation
        if !loadMore, YouTubeVideoInput.videoID(from: text) != nil {
            collections = []
            results = []
            nextPageToken = nil
            await openVideo()
            guard !Task.isCancelled, request == generation else { return }
            if let video { results = [video] }
            hasSearched = true
            return
        }
        guard let searchService else { return }
        if loadMore && nextPageToken == nil { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        if !loadMore {
            collections = []
            results = []
            video = nil
            nextPageToken = nil
            searchedQuery = text
        }
        do {
            let page = try await searchService.search(query: searchedQuery, pageToken: loadMore ? nextPageToken : nil)
            try Task.checkCancellation()
            guard request == generation else { return }
            var ids = Set(results.map(\.id))
            let merged = results + page.videos.filter { ids.insert($0.id).inserted }
            results = merged
            collections += page.collections.filter { item in !collections.contains { $0.id == item.id } }
            nextPageToken = page.nextPageToken
            hasSearched = true
        } catch is CancellationError {
        } catch { if request == generation { errorMessage = error.localizedDescription } }
    }

    func tracks(in collection: MusicCollection) async throws -> [MusicVideo] {
        guard let searchService else { throw MusicDiscoveryError.invalidResponse }
        return try await searchService.tracks(in: collection)
    }

    func suggestions(for query: String) async throws -> [String] {
        guard let searchService else { return [] }
        let suggestions = try await searchService.suggestions(query: query)
        try Task.checkCancellation()
        return suggestions
    }

    func preparePlayback(for selected: MusicVideo) async -> PlayableTrack? {
        guard !isLoading, !isResolvingPlayback else { return nil }
        video = selected
        return await preparePlayback()
    }

    func openVideo() async {
        guard !isLoading, !isResolvingPlayback else { return }
        let request = generation
        isLoading = true
        errorMessage = nil
        video = nil
        defer { isLoading = false }
        do {
            let result = try await service.video(for: query)
            try Task.checkCancellation()
            guard request == generation else { return }
            video = result
        } catch is CancellationError {
        } catch { if request == generation { errorMessage = error.localizedDescription } }
    }

    func preparePlayback() async -> PlayableTrack? {
        guard let video, !isLoading, !isResolvingPlayback else { return nil }
        isResolvingPlayback = true
        errorMessage = nil
        defer { isResolvingPlayback = false }
        do {
            let track = try await service.playableTrack(for: video)
            try Task.checkCancellation()
            return track
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
