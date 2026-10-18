import Foundation

// Provider-specific experiments belong behind this boundary.
// YouTube link playback resolves through YouTubeService.
protocol AudioSourceResolving {
    func resolve(track: MusicTrack) async throws -> PlayableTrack
}

struct LocalAudioSourceResolver: AudioSourceResolving {
    func resolve(track: MusicTrack) async throws -> PlayableTrack { track.playableTrack }
}
