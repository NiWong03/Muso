import Foundation

struct SampleMusicCatalog {
    static let tracks: [MusicTrack] = [
        MusicTrack(id: "sample-1", title: "Sample Track One", artist: "Muso Demo", album: "Starter Catalog", artworkSymbol: "waveform", streamURL: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3")!),
        MusicTrack(id: "sample-2", title: "Sample Track Two", artist: "Muso Demo", album: "Starter Catalog", artworkSymbol: "music.note.list", streamURL: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3")!),
        MusicTrack(id: "sample-3", title: "Sample Track Three", artist: "Muso Demo", album: "Starter Catalog", artworkSymbol: "headphones", streamURL: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3")!)
    ]
}
