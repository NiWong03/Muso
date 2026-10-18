import Foundation

final class StubMusicProvider: YouTubeMusicProviding {
    var catalogCollections: [MusicCollection] = []
    var collectionTracks: [MusicVideo] = []
    var searchCalls = 0
    var radioCalls = 0
    var suggestionCalls = 0
    var radioOverride: [MusicVideo]?
    var error: Error?
    let song = MusicVideo(id: "9bZkp7q19f0", title: "Song", channelTitle: "Artist", thumbnailURL: URL(string: "https://example.com/art.jpg"))
    let next = MusicVideo(id: "sF80I-TQiW0", title: "Next", channelTitle: "Artist", thumbnailURL: nil)
    func search(_ query: String) async throws -> [MusicVideo] {
        searchCalls += 1
        if let error { throw error }
        return [song]
    }
    func searchCatalog(_ query: String) async throws -> YouTubeSearchPage {
        YouTubeSearchPage(videos: try await search(query), nextPageToken: nil, collections: catalogCollections)
    }
    func tracks(in collection: MusicCollection) async throws -> [MusicVideo] { collectionTracks }
    func suggestions(_ query: String) async throws -> [String] {
        suggestionCalls += 1
        return ["jazz piano", "jazz music"]
    }
    func trending() async throws -> [MusicVideo] { [song] }
    func likedMusic() async throws -> [MusicVideo] { [song] }
    func home() async throws -> [MusicVideo] { [next] }
    func radio(videoID: String) async throws -> [MusicVideo] {
        precondition(videoID == song.id)
        radioCalls += 1
        return radioOverride ?? [song, next, next]
    }
}

final class RankedSearchStub: YouTubeSearching {
    var pages: [YouTubeSearchPage] = []
    func search(query: String, pageToken: String?) async throws -> YouTubeSearchPage {
        pages[pageToken == nil ? 0 : 1]
    }
    func suggestions(query: String) async throws -> [String] { [] }
}

@MainActor
func testYouTubeSearch() async throws {
    let rankedService = RankedSearchStub()
    let exact = MusicVideo(id: "exact", title: "Déjà Vu", channelTitle: "Olivia Rodrigo", thumbnailURL: nil)
    let unrelated = MusicVideo(id: "unrelated", title: "Favorite Song", channelTitle: "Favorite Artist", thumbnailURL: nil)
    let broad = MusicCollection(id: "broad", title: "Déjà Vu and other pop hits", subtitle: "Pop playlists", thumbnailURL: nil, kind: .playlist)
    let weak = MusicCollection(id: "weak", title: "Weekend hits", subtitle: "Various artists", thumbnailURL: nil, kind: .playlist)
    let exactPlaylist = MusicCollection(id: "exact-playlist", title: "Déjà Vu", subtitle: "Various artists", thumbnailURL: nil, kind: .playlist)
    rankedService.pages = [
        YouTubeSearchPage(videos: [unrelated, exact], nextPageToken: "next", collections: [weak, broad]),
        YouTubeSearchPage(videos: [exact], nextPageToken: nil, collections: [broad, exactPlaylist])
    ]
    let rankedModel = SearchViewModel(service: StubYouTubeService(), searchService: rankedService)
    rankedModel.setPersonalization(Array(repeating: unrelated, count: 100))
    rankedModel.query = "deja vu"
    await rankedModel.search()
    precondition(rankedModel.rankedResults.map(\.id) == ["track:exact", "collection:broad", "track:unrelated", "collection:weak"])
    await rankedModel.search(loadMore: true)
    precondition(rankedModel.rankedResults.map(\.id) == ["track:exact", "collection:exact-playlist", "collection:broad", "track:unrelated", "collection:weak"])
    precondition(rankedModel.results.count == 2 && rankedModel.collections.count == 3)
    rankedModel.query = "weekend hits"
    await rankedModel.search()
    precondition(rankedModel.rankedResults.first?.id == "collection:weak")
    rankedModel.query = "Olivia Rodrigo deja vu"
    await rankedModel.search()
    precondition(rankedModel.rankedResults.first?.id == "track:exact")
    rankedModel.reset()
    precondition(rankedModel.rankedResults.isEmpty)
    print("Passed: mixed relevance ranking, exact tracks and playlists, artist/title queries, bounded personalization, pagination deduplication, reset.")
    let collectionFixture = Data(#"""
    {"contents":[
      {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Album &amp; More"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"MPRE-album"}},"subtitle":{"runs":[{"text":"Artist"}]}}},
      {"musicResponsiveListItemRenderer":{"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"My playlist","navigationEndpoint":{"browseEndpoint":{"browseId":"VLplaylist"}}}]}}}]}},
      {"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"9bZkp7q19f0"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Song"}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Album","navigationEndpoint":{"browseEndpoint":{"browseId":"MPRE-wrong"}}}]}}}]}},
      {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Artist"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"UCartist"}}}}
    ]}
    """#.utf8)
    let collections = try MusicCollectionParser.collections(from: collectionFixture)
    precondition(collections.map(\.id) == ["MPRE-album", "VLplaylist"])
    precondition(collections[0].title == "Album & More" && collections[1].kind == .playlist)
    let tracksFixture = Data(#"""
    {"contents":{"musicPlaylistShelfRenderer":{"contents":[
      {"playlistPanelVideoRenderer":{"videoId":"9bZkp7q19f0","title":{"simpleText":"First"}}},
      {"playlistPanelVideoRenderer":{"videoId":"sF80I-TQiW0","title":{"simpleText":"Second"}}}],
      "continuations":[{"nextContinuationData":{"continuation":"page-two"}}]}},
      "suggestions":{"playlistPanelVideoRenderer":{"videoId":"abcdefghijk","title":{"simpleText":"Not an album track"}}}}
    """#.utf8)
    let trackPage = try MusicCollectionParser.tracks(from: tracksFixture)
    precondition(trackPage.videos.map(\.title) == ["First", "Second"] && trackPage.continuation == "page-two")
    let continuationFixture = Data(#"""
    {"onResponseReceivedActions":[{"appendContinuationItemsAction":{"continuationItems":[
      {"playlistPanelVideoRenderer":{"videoId":"abcdefghijk","title":{"simpleText":"Third"}}},
      {"continuationItemRenderer":{"continuationEndpoint":{"continuationCommand":{"token":"page-three"}}}}
    ]}}]}
    """#.utf8)
    let continuationPage = try MusicCollectionParser.tracks(from: continuationFixture)
    precondition(continuationPage.videos.map(\.title) == ["Third"] && continuationPage.continuation == "page-three")
    print("Passed: album/playlist search destinations, entity decoding, ordered track shelves, continuation pages, recommendation exclusion.")
    let catalogProvider = StubMusicProvider()
    catalogProvider.catalogCollections = collections
    catalogProvider.collectionTracks = trackPage.videos + continuationPage.videos
    let catalogService = YouTubeSearchService(provider: catalogProvider)
    let catalogPage = try await catalogService.search(query: "album")
    precondition(catalogPage.collections == collections && catalogPage.videos == [catalogProvider.song])
    let collectionTracks = try await catalogService.tracks(in: collections[0])
    precondition(collectionTracks.map(\.title) == ["First", "Second", "Third"])
    let encodedTitle = "Don&#39;t &quot;Stop&quot; &amp; Go &#x1F3B5;"
    let decodedTitle = "Don't \"Stop\" & Go 🎵"
    let entityVideo = MusicVideo(id: "entities", title: encodedTitle, channelTitle: "Artist&#x27;s", thumbnailURL: nil)
    precondition(entityVideo.title == decodedTitle && entityVideo.channelTitle == "Artist's")
    let saved = Data(#"{"id":"cached","title":"Don&#39;t","channelTitle":"A &amp; B"}"#.utf8)
    let restored = try JSONDecoder().decode(MusicVideo.self, from: saved)
    precondition(restored.title == "Don't" && restored.channelTitle == "A & B")
    precondition("<live> &unknown; &#xD800;".decodingHTMLEntities == "<live> &unknown; &#xD800;")
    precondition("&amp;#39;".decodingHTMLEntities == "&#39;")
    let roundTrip = try JSONDecoder().decode(MusicVideo.self, from: JSONEncoder().encode(entityVideo))
    precondition(roundTrip == entityVideo)
    print("Passed: HTML entities, Unicode, cached metadata, and plain-text preservation.")

    var tokenRequests = 0
    let publicHeaders = try await MusicRequestAuthorization.headers(requiresSignIn: false) {
        tokenRequests += 1
        throw MusicDiscoveryError.signInRequired
    }
    precondition(publicHeaders.isEmpty && tokenRequests == 0)
    let privateHeaders = try await MusicRequestAuthorization.headers(requiresSignIn: true) {
        tokenRequests += 1
        return "test-token"
    }
    precondition(privateHeaders["Authorization"] == "Bearer test-token" && tokenRequests == 1)
    do {
        _ = try await MusicRequestAuthorization.headers(requiresSignIn: true) { nil }
        preconditionFailure("Private requests require authentication")
    } catch MusicDiscoveryError.signInRequired { }
    print("Passed: public music requests neither refresh nor attach OAuth; private requests require a token.")

    let provider = StubMusicProvider()
    let service = YouTubeSearchService(provider: provider)
    let playback = StubYouTubeService()
    let model = SearchViewModel(service: playback, searchService: service)
    model.query = "piano & rain"
    await model.search()
    precondition(model.results == [provider.song] && model.nextPageToken == nil)
    let track = await model.preparePlayback(for: model.results[0])
    precondition(track?.artist == "Artist" && playback.resolutionCount == 1)
    let suggestions = try await model.suggestions(for: "jazz")
    precondition(suggestions == ["jazz piano", "jazz music"] && provider.suggestionCalls == 1)
    precondition(provider.searchCalls == 1 && model.query == "piano & rain" && model.results == [provider.song])
    model.query = "https://youtu.be/9bZkp7q19f0"
    await model.search()
    precondition(provider.searchCalls == 1 && model.results.count == 1)
    provider.error = MusicDiscoveryError.invalidResponse
    model.query = "new search"
    await model.search()
    precondition(model.errorMessage != nil && !model.isLoading)
    provider.error = CancellationError()
    await model.search()
    precondition(model.errorMessage == nil && !model.isLoading)

    let discovery = YouTubeDiscoveryService(provider: provider)
    let queue = try await discovery.recommendations(seeds: [provider.song], excluding: [provider.song.id])
    precondition(queue == [provider.next] && provider.radioCalls == 1)
    let exhausted = try await discovery.recommendations(seeds: [provider.song], excluding: [provider.song.id, provider.next.id])
    precondition(exhausted.isEmpty)
    let repost = MusicVideo(id: "zzzzzzzzzzz", title: "Artist - Song (Official Video)", channelTitle: "Fan upload", thumbnailURL: nil)
    let nextRepost = MusicVideo(id: "yyyyyyyyyyy", title: "Next [Lyrics]", channelTitle: "Artist - Topic", thumbnailURL: nil)
    let remix = MusicVideo(id: "xxxxxxxxxxx", title: "Song (Fan Remix)", channelTitle: "Artist", thumbnailURL: nil)
    provider.radioOverride = [repost, provider.next, nextRepost, remix]
    let broadRadio = try await discovery.recommendations(seeds: [provider.song], excluding: [])
    precondition(broadRadio == [provider.next, remix])
    let afterPlayingNext = try await discovery.recommendations(seeds: [provider.song, provider.next], excluding: [])
    precondition(afterPlayingNext == [remix])
    print("Passed: broad radio retains unofficial remixes while excluding alternate postings of played/queued songs.")
    let home = try await discovery.homeRecommendations(seeds: [], excluding: [])
    precondition(home == [provider.next])

    let fixture = Data(#"{"contents":[{"playlistPanelVideoRenderer":{"videoId":"9bZkp7q19f0","title":{"runs":[{"text":"Don&#39;t"}]},"longBylineText":{"runs":[{"text":"Artist","navigationEndpoint":{"browseEndpoint":{"browseId":"UC123"}}}]},"thumbnail":{"thumbnails":[{"url":"https://example.com/art.jpg"}]}}},{"playlistPanelVideoRenderer":{"videoId":"sF80I-TQiW0","title":{"simpleText":"Next"}}},{"playlistPanelVideoRenderer":{"videoId":"9bZkp7q19f0","title":{"simpleText":"Duplicate"}}},{"playlistPanelVideoRenderer":{"videoId":"abcdefghijk","title":{"simpleText":"Unavailable"},"isPlayable":false}}]}"#.utf8)
    let parsed = try MusicResponseParser.videos(from: fixture)
    precondition(parsed.map(\.id) == [provider.song.id, provider.next.id])
    precondition(parsed[0].title == "Don't" && parsed[0].channelTitle == "Artist" && parsed[0].thumbnailURL != nil)
    let responsive = Data(#"{"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"9bZkp7q19f0"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Music title"}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Singer"}]}}}]}}"#.utf8)
    let songs = try MusicResponseParser.videos(from: responsive)
    precondition(songs.first?.title == "Music title" && songs.first?.channelTitle == "Singer")
    do {
        _ = try MusicResponseParser.videos(from: Data(#"{"error":{"code":403}}"#.utf8))
        preconditionFailure("Upstream errors must not look like an empty library")
    } catch MusicDiscoveryError.invalidResponse { }
    func musicRow(_ id: String, type: String?) -> [String: Any] {
        var endpoint: [String: Any] = ["videoId": id]
        if let type { endpoint["watchEndpointMusicSupportedConfigs"] = ["watchEndpointMusicConfig": ["musicVideoType": type]] }
        return ["playlistPanelVideoRenderer": ["videoId": id, "title": ["simpleText": "Track"], "navigationEndpoint": ["watchEndpoint": endpoint]]]
    }
    let mixed = try JSONSerialization.data(withJSONObject: ["contents": [
        musicRow("aaaaaaaaaaa", type: "MUSIC_VIDEO_TYPE_ATV"),
        musicRow("bbbbbbbbbbb", type: "MUSIC_VIDEO_TYPE_OMV"),
        musicRow("ccccccccccc", type: "MUSIC_VIDEO_TYPE_UGC"),
        musicRow("ddddddddddd", type: "MUSIC_VIDEO_TYPE_PODCAST_EPISODE"),
        musicRow("eeeeeeeeeee", type: nil)]])
    let unrestricted = try MusicResponseParser.videos(from: mixed)
    precondition(unrestricted.count == 5, "Unfiltered radio must retain unofficial uploads and videos")
    let audioOnly = try MusicResponseParser.videos(from: mixed, songsOnly: true)
    precondition(audioOnly.map(\.id) == ["aaaaaaaaaaa"])
    print("Passed: strict audio-track filtering excludes music videos, uploads, podcasts and unclassified videos.")
    print("Passed: music search, native suggestions, direct links, cancellation, radio order/exclusions, Home and response parsing.")
}
