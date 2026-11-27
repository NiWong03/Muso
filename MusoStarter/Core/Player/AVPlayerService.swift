import Foundation
import AVFoundation
import Combine
import MediaPlayer
import UIKit

final class PlaybackTimeline: ObservableObject {
    @Published private(set) var elapsedTime: Double = 0
    @Published private(set) var duration: Double = 0

    func update(elapsedTime: Double, duration: Double) {
        if self.elapsedTime != elapsedTime { self.elapsedTime = elapsedTime }
        if self.duration != duration { self.duration = duration }
    }
}

final class AVPlayerService: PlayerService, ObservableObject {
    @Published private(set) var currentTrack: PlayableTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?

    let timeline = PlaybackTimeline()
    var elapsedTime: Double { timeline.elapsedTime }
    var duration: Double { timeline.duration }
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var sessionObservers: [NSObjectProtocol] = []
    private var artworkTask: Task<Void, Never>?
    private var artwork: MPMediaItemArtwork?
    private var loadID = UUID()
    private var resumeAfterInterruption = false
    let queueStore: PlaybackQueueStore
    private let resolver: YouTubeServing
    var autoplaySource: ((MusicVideo, Set<String>) async throws -> [MusicVideo])?
    var onPlayed: ((MusicVideo) -> Void)?
    @Published private(set) var isPreparing = false
    private var preparation: Task<Void, Never>?
    private var preparationID = UUID()
    private var radioTask: Task<Void, Never>?
    private var radioRequestID = UUID()
    private var radioSeedID: UUID?
    private var recordedEntryID: UUID?
    private var queueSubscription: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var itemObservation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?

    init(queueStore: PlaybackQueueStore? = nil, resolver: YouTubeServing? = nil) {
        self.queueStore = queueStore ?? PlaybackQueueStore()
        self.resolver = resolver ?? YouTubeService()
        queueSubscription = self.queueStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            Task { @MainActor [weak self] in
                self?.updateNowPlaying()
                self?.fillRadioQueue()
            }
        }
        configureRemoteCommands()
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateNowPlaying() }
        }
        sessionObservers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self.resumeAfterInterruption = self.player.rate > 0 || self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.pause()
            } else {
                let options = AVAudioSession.InterruptionOptions(rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                if self.resumeAfterInterruption && options.contains(.shouldResume) { self.play() }
                self.resumeAfterInterruption = false
            }
        })
        sessionObservers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                self?.pause()
            }
        })
        playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.updateNowPlaying()
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let item = notification.object as? AVPlayerItem,
                  self.player.currentItem === item else { return }
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self.errorMessage = PlaybackFailure.message(for: error ?? item.error)
            self.pause()
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let currentItem = self.player.currentItem,
                  let endedItem = notification.object as? AVPlayerItem,
                  currentItem === endedItem else { return }
            self.next()
        }
    }

    deinit {
        preparation?.cancel()
        radioTask?.cancel()
        artworkTask?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        for (command, target) in commandTargets { command.removeTarget(target) }
        for observer in sessionObservers { NotificationCenter.default.removeObserver(observer) }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func setQueue(_ tracks: [PlayableTrack], startAt index: Int) {
        guard !tracks.isEmpty else { return }
        queueStore.replace(tracks.map { QueueEntry(video: MusicVideo(id: $0.id, title: $0.title, channelTitle: $0.artist, thumbnailURL: $0.artworkURL), localURL: $0.streamURL) }, startAt: index)
        loadCurrentAndPlay()
    }

    func playVideos(_ videos: [MusicVideo], startAt index: Int = 0) {
        guard !videos.isEmpty else { return }
        queueStore.replace(videos.map { QueueEntry(video: $0) }, startAt: index)
        loadCurrentAndPlay()
    }

    func playStation(seed: MusicVideo) {
        queueStore.autoplay = true
        playVideos([seed])
    }

    func playCollection(_ videos: [MusicVideo], startingAt index: Int) {
        guard videos.indices.contains(index) else { return }
        queueStore.replaceCollection(videos, startingAt: index)
        loadCurrentAndPlay()
    }

    func enqueueCollection(_ videos: [MusicVideo], next: Bool = false) {
        queueStore.enqueueCollection(videos, next: next)
    }

    @discardableResult func enqueue(_ video: MusicVideo, next: Bool = false) -> Bool {
        queueStore.enqueue(video, next: next)
    }
    func playEntry(_ id: UUID) { queueStore.select(id); loadCurrentAndPlay() }

    func switchAccount(_ userID: String?) {
        radioTask?.cancel(); radioTask = nil; radioRequestID = UUID(); radioSeedID = nil
        preparation?.cancel(); preparationID = UUID(); isPreparing = false
        pause(); player.replaceCurrentItem(with: nil); currentTrack = nil
        artworkTask?.cancel(); artwork = nil; loadID = UUID()
        timeline.update(elapsedTime: 0, duration: 0); errorMessage = nil
        queueStore.switchAccount(userID)
        updateNowPlaying()
    }

    func play() {
        guard queueStore.current != nil else { return }
        isPlaying = true
        if isPreparing { updateNowPlaying(); return }
        if player.currentItem == nil { if queueStore.current != nil { loadCurrentAndPlay() }; return }
        if duration > 0 && elapsedTime >= duration - 0.5 { seek(to: 0) }
        AudioSessionManager.configureForPlayback()
        player.play()
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func next() {
        if queueStore.advance() { loadCurrentAndPlay(); return }
        guard !isPreparing else { return }
        guard queueStore.autoplay, autoplaySource != nil else { pause(); return }
        fillRadioQueue()
        pause()
        isPreparing = true
        isPlaying = true
        let request = UUID(); preparationID = request
        preparation?.cancel()
        preparation = Task { [weak self] in
            guard let self else { return }
            await self.radioTask?.value
            guard !Task.isCancelled, self.preparationID == request else { return }
            self.isPreparing = false
            let shouldPlay = self.isPlaying
            if self.queueStore.advance() {
                self.loadCurrentAndPlay()
                if !shouldPlay { self.pause() }
            } else {
                self.pause()
                self.errorMessage = "No more music is available right now. Search for a song to keep listening."
            }
        }
    }

    /// Start radio alongside stream resolution so the initial track already has Up Next items.
    private func fillRadioQueue() {
        guard queueStore.autoplay, !queueStore.hasNext,
              let entry = queueStore.current, entry.localURL == nil,
              let source = autoplaySource else { return }
        if radioSeedID == entry.id, radioTask != nil { return }
        radioTask?.cancel()
        let request = UUID()
        radioRequestID = request
        radioSeedID = entry.id
        radioTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.radioRequestID == request { self.radioTask = nil }
            }
            do {
                let videos = try await source(entry.video, Set(self.queueStore.radioExclusions.map(\.id)))
                guard !Task.isCancelled, self.radioRequestID == request,
                      self.queueStore.current?.id == entry.id, self.queueStore.autoplay else { return }
                self.queueStore.append(videos)
            } catch {
                // Discovery failure must not interrupt the track already playing.
            }
        }
    }

    func previous() {
        if elapsedTime > 3 { seek(to: 0); return }
        if queueStore.previous() { loadCurrentAndPlay() } else { seek(to: 0) }
    }

    private func loadCurrentAndPlay() {
        guard let entry = queueStore.current else { return }
        preparation?.cancel()
        let request = UUID(); preparationID = request
        pause(); player.replaceCurrentItem(with: nil); currentTrack = nil
        errorMessage = nil; isPreparing = true; isPlaying = true
        fillRadioQueue()
        timeline.update(elapsedTime: 0, duration: 0)
        updateNowPlaying()
        preparation = Task { [weak self] in
            guard let self else { return }
            defer { if self.preparationID == request { self.isPreparing = false } }
            do {
                let track: PlayableTrack
                if let url = entry.localURL {
                    track = PlayableTrack(id: entry.video.id, title: entry.video.title, artist: entry.video.channelTitle, artworkURL: entry.video.thumbnailURL, streamURL: url)
                } else { track = try await self.resolver.playableTrack(for: entry.video) }
                guard !Task.isCancelled, self.preparationID == request, self.queueStore.current?.id == entry.id else { return }
                self.install(track)
            } catch {
                if !Task.isCancelled && self.preparationID == request { self.errorMessage = error.localizedDescription; self.pause() }
            }
        }
    }

    private func install(_ track: PlayableTrack) {
        errorMessage = nil
        player.pause()
        timeline.update(elapsedTime: 0, duration: 0)
        artwork = nil
        loadID = UUID()
        artworkTask?.cancel()
        currentTrack = track
        let item = AVPlayerItem(url: track.streamURL)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let error = item.error
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item else { return }
                self.errorMessage = PlaybackFailure.message(for: error)
                self.pause()
            }
        }
        player.replaceCurrentItem(with: item)
        loadArtwork(for: track, generation: loadID)
        if isPlaying {
            AudioSessionManager.configureForPlayback()
            player.play()
        }
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, duration > 0 else { return }
        player.seek(to: CMTime(seconds: min(max(0, seconds), duration), preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateNowPlaying() }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        func register(_ command: MPRemoteCommand, action: @escaping @MainActor (AVPlayerService) -> Void) {
            let token = command.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    action(self)
                }
                return .success
            }
            commandTargets.append((command, token))
        }
        register(center.playCommand) { $0.play() }
        register(center.pauseCommand) { $0.pause() }
        register(center.togglePlayPauseCommand) { player in
            if player.isPlaying { player.pause() } else { player.play() }
        }
        register(center.nextTrackCommand) { $0.next() }
        register(center.previousTrackCommand) { $0.previous() }
        let token = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = event.positionTime
            Task { @MainActor [weak self] in self?.seek(to: seconds) }
            return .success
        }
        commandTargets.append((center.changePlaybackPositionCommand, token))
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        let center = MPRemoteCommandCenter.shared()
        let available = queueStore.current != nil && player.currentItem?.status != .failed
        center.playCommand.isEnabled = available
        center.pauseCommand.isEnabled = available
        center.togglePlayPauseCommand.isEnabled = available
        center.nextTrackCommand.isEnabled = available && (queueStore.hasNext || (!isPreparing && queueStore.autoplay))
        center.previousTrackCommand.isEnabled = available
        guard let track = currentTrack else {
            center.changePlaybackPositionCommand.isEnabled = false
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let time = player.currentTime().seconds
        let length = player.currentItem?.duration.seconds ?? 0
        timeline.update(elapsedTime: time.isFinite ? max(0, time) : 0,
                        duration: length.isFinite && length > 0 ? length : 0)
        if isPlaying, elapsedTime > 1, let entry = queueStore.current, entry.localURL == nil, recordedEntryID != entry.id {
            recordedEntryID = entry.id
            onPlayed?(entry.video)
        }
        center.changePlaybackPositionCommand.isEnabled = available && duration > 0
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: VideoArtistResolver.shared.artist(for: MusicVideo(id: track.id, title: track.title, channelTitle: track.artist, thumbnailURL: track.artworkURL)),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? player.rate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for track: PlayableTrack, generation: UUID) {
        guard let url = track.artworkURL else { return }
        artworkTask = Task { [weak self] in
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled, let self, self.loadID == generation,
                      let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let image = UIImage(data: data) else { return }
                self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.updateNowPlaying()
            } catch { /* Artwork is optional; audio continues. */ }
        }
    }

}
