import Foundation

final class StubYouTubeService: YouTubeServing {
    var fail = false
    var cancel = false
    var resolutionCount = 0
    func video(for input: String) async throws -> MusicVideo {
        if cancel { throw CancellationError() }
        if fail { throw YouTubeServiceError.metadataUnavailable }
        return MusicVideo(id: "9bZkp7q19f0", title: "Test", channelTitle: "YouTube", thumbnailURL: nil)
    }
    func playableTrack(for video: MusicVideo) async throws -> PlayableTrack {
        resolutionCount += 1
        if fail { throw YouTubeServiceError.noPlayableAudio }
        return PlayableTrack(id: video.id, title: video.title, artist: video.channelTitle,
                             artworkURL: nil, streamURL: URL(string: "https://example.com/audio.m4a")!)
    }
}

@main
struct YouTubeLinkTests {
    @MainActor static func main() async {
        let id = "9bZkp7q19f0"
        let valid = [id, "  \(id)\n", "https://youtube.com/watch?v=\(id)&list=PLtest",
                     "https://youtu.be/\(id)?t=42", "www.youtube.com/shorts/\(id)",
                     "https://m.youtube.com/live/\(id)", "https://music.youtube.com/watch?v=\(id)",
                     "https://www.youtube-nocookie.com/embed/\(id)"]
        for input in valid { precondition(YouTubeVideoInput.videoID(from: input) == id, input) }
        for input in ["", "lofi hip hop", "https://youtube.com/playlist?list=PLtest",
                      "https://youtube.com.evil.com/watch?v=\(id)", "https://evil.com/\(id)",
                      "https://youtube.com@evil.com/watch?v=\(id)", "file://youtube.com/watch?v=\(id)",
                      "https://youtube.com/watch?v=short", "https://youtube.com/watch?v=\(id)%0A", "https://youtu.be/\(id)/extra"] {
            precondition(YouTubeVideoInput.videoID(from: input) == nil, input)
        }
        let service = StubYouTubeService()
        let model = SearchViewModel(service: service)
        model.query = id
        await model.openVideo()
        precondition(model.video?.id == id && !model.isLoading && model.errorMessage == nil)
        let first = await model.preparePlayback()
        let second = await model.preparePlayback()
        precondition(first?.id == id && second?.id == id && service.resolutionCount == 2)
        service.fail = true
        let failed = await model.preparePlayback()
        precondition(failed == nil && model.errorMessage != nil && !model.isResolvingPlayback)
        await model.openVideo()
        precondition(model.video == nil && model.errorMessage != nil && !model.isLoading)
        service.fail = false
        service.cancel = true
        await model.openVideo()
        precondition(model.video == nil && model.errorMessage == nil && !model.isLoading)
        do { try await testYouTubeSearch(); await testPersonalization() } catch { fatalError("Search checks failed: \(error)") }
        print("Passed: 18 link cases, metadata, fresh playback resolution, failures, cancellation.")
    }
}
