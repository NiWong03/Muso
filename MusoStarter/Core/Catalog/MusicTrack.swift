import Foundation

struct MusicTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let artworkSymbol: String
    let streamURL: URL

    var playableTrack: PlayableTrack {
        PlayableTrack(id: id, title: title, artist: artist, artworkURL: nil, streamURL: streamURL)
    }
}
