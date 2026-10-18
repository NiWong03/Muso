import Foundation

struct PlayableTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let streamURL: URL
}
