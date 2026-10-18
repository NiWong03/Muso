import Foundation

protocol PlayerService: AnyObject {
    var currentTrack: PlayableTrack? { get }
    var isPlaying: Bool { get }

    func setQueue(_ tracks: [PlayableTrack], startAt index: Int)
    func play()
    func pause()
    func next()
    func previous()
}
