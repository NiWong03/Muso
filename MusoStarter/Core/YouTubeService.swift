import Foundation
import YouTubeKit

final class YouTubeService: YouTubeServing {
    func video(for input: String) async throws -> MusicVideo {
        guard let id = YouTubeVideoInput.videoID(from: input) else {
            throw YouTubeServiceError.invalidVideoLink
        }
        let youtube = YouTube(videoID: id, methods: [.local])
        guard let metadata = try await youtube.metadata else {
            throw YouTubeServiceError.metadataUnavailable
        }
        try Task.checkCancellation()
        let video = MusicVideo(id: id, title: metadata.title, channelTitle: "YouTube",
                               thumbnailURL: metadata.thumbnail?.url)
        do { return try await VideoArtistResolver.shared.resolve(video) }
        catch {
            try Task.checkCancellation()
            return video
        }
    }

    func playableTrack(for video: MusicVideo) async throws -> PlayableTrack {
        let youtube = YouTube(videoID: video.id, methods: [.local])
        // YouTubeKit exposes HLS manifests here for some on-demand videos too.
        // A codec-compatible M4A URL can download successfully yet never become
        // playable in AVPlayer. Prefer the native segmented streaming manifest.
        do {
            if let hls = try await youtube.livestreams.first(where: { $0.streamType == .hls }) {
                try Task.checkCancellation()
                return playableTrack(video: video, url: hls.url)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Not every video/client offers HLS; retain direct-stream support.
            try Task.checkCancellation()
        }
        let streams = try await youtube.streams.filter { $0.isNativelyPlayable }
        try Task.checkCancellation()
        // Resolve on each play; extracted stream URLs expire.
        guard let stream = streams.filterAudioOnly().highestAudioBitrateStream()
                ?? streams.filterVideoAndAudio().lowestResolutionStream() else {
            throw YouTubeServiceError.noPlayableAudio
        }
        return playableTrack(video: video, url: stream.url)
    }

    private func playableTrack(video: MusicVideo, url: URL) -> PlayableTrack {
        PlayableTrack(id: video.id, title: video.title, artist: video.channelTitle,
                      artworkURL: video.thumbnailURL, streamURL: url)
    }
}
