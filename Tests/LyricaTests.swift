import Foundation

final class LyricsURLProtocol: URLProtocol, @unchecked Sendable {
    static var requests = 0
    static var status = 200
    static var payload = #"{"status":"success","data":{"source":"genius","artist":"Zach Bryan","title":"Heading South","lyrics":"[Verse 1]\nTest line","hasTimestamps":false}}"#
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct LyricaTests {
    @MainActor static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        let service = LyricaService(session: URLSession(configuration: configuration))
        let query = LyricsQuery(video: MusicVideo(id: "test", title: "Zach Bryan - Heading South (Official Video)", channelTitle: "Uploader", thumbnailURL: nil))
        precondition(query.artist == "Zach Bryan" && query.song == "Heading South")
        let special = LyricsQuery(video: MusicVideo(id: "test", title: "Home & Away + You?", channelTitle: "Beyoncé - Topic", thumbnailURL: nil))
        let request = try service.request(query: special, server: "http://localhost:9999")
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        precondition(components.path == "/lyrics/")
        precondition(components.queryItems?.first?.value == "Beyoncé")
        precondition(components.queryItems?.last?.value == "Home & Away + You?")
        let result = try await service.lyrics(query: query, server: "http://localhost:9999")
        precondition(result.source == "genius" && !result.hasTimestamps && result.lyrics.contains("\n"))
        _ = try await service.lyrics(query: query, server: "http://localhost:9999")
        precondition(LyricsURLProtocol.requests == 1)
        LyricsURLProtocol.status = 404
        do {
            _ = try await service.lyrics(query: special, server: "http://localhost:9999")
            preconditionFailure("Expected missing lyrics")
        } catch LyricaError.unavailable {}
        LyricsURLProtocol.status = 200
        LyricsURLProtocol.payload = #"{"status":"success","data":null}"#
        do {
            _ = try await service.lyrics(query: special, server: "http://localhost:9999")
            preconditionFailure("Expected missing data")
        } catch LyricaError.unavailable {}
        let unknown = MusicVideo(id: "aaaaaaaaaaa", title: "Heading South", channelTitle: "YouTube Music", thumbnailURL: nil)
        precondition(LyricsQuery(video: unknown).artist.isEmpty)
        LyricsURLProtocol.payload = #"{"author_name":"Zach Bryan"}"#
        let suite = "muso.artist-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let resolver = VideoArtistResolver(session: URLSession(configuration: configuration), defaults: defaults)
        let before = LyricsURLProtocol.requests
        let recovered = try await resolver.resolve(unknown)
        precondition(recovered.channelTitle == "Zach Bryan")
        precondition(resolver.artist(for: unknown) == "Zach Bryan")
        let restored = VideoArtistResolver(session: URLSession(configuration: configuration), defaults: defaults)
        precondition(restored.artist(for: unknown) == "Zach Bryan")
        _ = try await restored.resolve(unknown)
        precondition(LyricsURLProtocol.requests == before + 1)
        precondition(LyricsQuery(video: recovered).artist == "Zach Bryan")
        _ = try await resolver.resolve(unknown)
        precondition(LyricsURLProtocol.requests == before + 1)
        let known = MusicVideo(id: "bbbbbbbbbbb", title: "Song", channelTitle: "Actual Artist", thumbnailURL: nil)
        let preserved = try await resolver.resolve(known)
        precondition(preserved == known && LyricsURLProtocol.requests == before + 1)
        let embedded = MusicVideo(id: "ccccccccccc", title: "Actual Artist - Song", channelTitle: "YouTube", thumbnailURL: nil)
        precondition(LyricsQuery(video: embedded).artist == "Actual Artist")
        print("Artist recovery, cached recovery, known-artist preservation and placeholder rejection passed")
        print("Lyrica request, metadata, decoding, caching and missing-lyrics checks passed")
    }
}
