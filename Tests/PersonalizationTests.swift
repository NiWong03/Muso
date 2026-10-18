import Foundation

final class StubDiscovery: YouTubeDiscovering {
    var likedCalls = 0
    var recommendationCalls = 0
    var failLikes = false
    let video = MusicVideo(id: "9bZkp7q19f0", title: "Song", channelTitle: "Artist", thumbnailURL: nil)
    func trending() async throws -> [MusicVideo] { [video] }
    func likedMusic() async throws -> [MusicVideo] {
        likedCalls += 1
        if failLikes { throw MusicDiscoveryError.signInRequired }
        return [video]
    }
    func recommendations(seeds: [MusicVideo], excluding: Set<String>) async throws -> [MusicVideo] {
        recommendationCalls += 1
        precondition(Set(seeds.map(\.id)) == excluding)
        return [MusicVideo(id: "sF80I-TQiW0", title: "Next", channelTitle: "Artist", thumbnailURL: nil)]
    }
}

@MainActor func testPersonalization() async {
    let suite = "MusoTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let discovery = StubDiscovery()
    let video = discovery.video
    let other = MusicVideo(id: "sF80I-TQiW0", title: "Next", channelTitle: "Artist", thumbnailURL: nil)
    let history = ListeningHistoryStore(defaults: defaults)
    history.record(video)
    precondition(history.recent.isEmpty)
    history.switchAccount("A"); history.record(video); history.record(other); history.record(video)
    precondition(history.recent == [video, other])
    history.switchAccount("B"); precondition(history.recent.isEmpty)
    history.switchAccount("A"); precondition(history.recent == [video, other])
    history.switchAccount(nil); precondition(history.recent.isEmpty)
    history.switchAccount("A"); history.clear(); history.switchAccount("A"); precondition(history.recent.isEmpty)
    let queue = PlaybackQueueStore(defaults: defaults)
    queue.replace([QueueEntry(video: video), QueueEntry(video: other)], startAt: 0)
    queue.append([video, other]); precondition(queue.entries.count == 2)
    precondition(queue.advance() && queue.current?.video == other && !queue.advance())
    queue.autoplay = false
    let restored = PlaybackQueueStore(defaults: defaults)
    precondition(restored.index == 1 && restored.entries.count == 2 && !restored.autoplay)
    precondition(restored.entries.allSatisfy { $0.localURL == nil })
    restored.switchAccount("A"); precondition(restored.entries.isEmpty)
    restored.switchAccount(nil); precondition(restored.entries.count == 2)
    restored.remove(restored.current!.id); precondition(restored.entries.count == 2)
    restored.remove(restored.entries[0].id); precondition(restored.index == 0 && restored.current?.video == other)
    restored.replace([QueueEntry(video: video), QueueEntry(video: other), QueueEntry(video: MusicVideo(id: "abcdefghijk", title: "Third", channelTitle: "Artist", thumbnailURL: nil))], startAt: 0)
    let third = restored.entries[2].id
    restored.moveUp(third); precondition(restored.entries[1].id == third)
    restored.select(third); precondition(restored.index == 1 && restored.previous())
    let original = MusicVideo(id: "aaaaaaaaaaa", title: "Wonderwall", channelTitle: "Oasis", thumbnailURL: nil)
    let repost = MusicVideo(id: "bbbbbbbbbbb", title: "Oasis - Wonderwall (Official Music Video)", channelTitle: "Uploader", thumbnailURL: nil)
    let lyrics = MusicVideo(id: "ccccccccccc", title: "Wonderwall [Lyrics]", channelTitle: "Oasis - Topic", thumbnailURL: nil)
    let live = MusicVideo(id: "ddddddddddd", title: "Wonderwall (Live)", channelTitle: "Oasis", thumbnailURL: nil)
    let remix = MusicVideo(id: "eeeeeeeeeee", title: "Wonderwall (Remix)", channelTitle: "Oasis", thumbnailURL: nil)
    precondition(original.songIdentity == repost.songIdentity && original.songIdentity == lyrics.songIdentity)
    precondition(original.songIdentity != live.songIdentity && original.songIdentity != remix.songIdentity)
    let loop = MusicVideo(id: "loop", title: "Oasis - Wonderwall (10 hours loop)", channelTitle: "Fan Uploads", thumbnailURL: nil)
    precondition(QueueDeduplicator.isDuplicate(original, loop))
    precondition(!QueueDeduplicator.isDuplicate(original, remix))
    func candidate(_ title: String, artist: String = "Artist") -> MusicVideo {
        MusicVideo(id: title + artist, title: title, channelTitle: artist, thumbnailURL: nil)
    }
    precondition(QueueDeduplicator.isDuplicate(candidate("Never Gonna Give You Up"), candidate("Never Gonna Give You Up HQ")))
    precondition(!QueueDeduplicator.isDuplicate(candidate("Love"), candidate("Love Story")))
    precondition(!QueueDeduplicator.isDuplicate(candidate("Never Gonna Give You Up"), candidate("Never Gonna Give You Up", artist: "Someone Else")))
    precondition(!QueueDeduplicator.isDuplicate(candidate("Go"), candidate("No")))
    for title in ["Artist interview", "Song reaction", "Guitar tutorial", "Gaming walkthrough", "My daily vlog"] {
        precondition(!QueueDeduplicator.isLikelyMusic(candidate(title)))
    }
    for title in ["Song (Fan Remix)", "Song (Live)", "Artist - Song [Unofficial Upload]"] {
        precondition(QueueDeduplicator.isLikelyMusic(candidate(title)))
    }
    precondition(QueueDeduplicator.filter([loop, candidate("Artist interview"), remix], excluding: [original]) == [remix])
    print("Passed: fuzzy title matching, loop removal, short-title and artist protection, non-music exclusions, remix preservation.")
    queue.replace([QueueEntry(video: original), QueueEntry(video: repost), QueueEntry(video: live)], startAt: 1)
    precondition(queue.entries.map(\.video.id) == [repost.id, live.id] && queue.current?.video.id == repost.id)
    queue.append([original, lyrics, remix, remix])
    precondition(queue.entries.map(\.video.id) == [repost.id, live.id, remix.id])
    precondition(!queue.enqueue(original))
    queue.enqueue(remix, next: true)
    precondition(queue.entries.map(\.video.id) == [repost.id, remix.id, live.id])
    let currentID = queue.current!.id
    queue.move(queue.entries[1].id, to: queue.entries[2].id)
    precondition(queue.entries.map(\.video.id) == [repost.id, live.id, remix.id] && queue.current?.id == currentID)
    queue.move(queue.entries[2].id, to: queue.entries[1].id)
    precondition(queue.entries[1].video.id == remix.id)
    queue.move(currentID, to: queue.entries[1].id)
    precondition(queue.current?.id == currentID)
    queue.remove(queue.entries[1].id)
    queue.enqueue(remix)
    let beforeMove = queue.entries.map(\.id)
    queue.moveUpcoming(from: IndexSet(integer: 0), to: 2)
    precondition(queue.entries.map(\.id) == [beforeMove[0], beforeMove[2], beforeMove[1]])
    queue.moveUpcoming(from: IndexSet(integer: 1), to: 0)
    precondition(queue.entries.map(\.id) == beforeMove && queue.current?.id == currentID)
    queue.moveUpcoming(from: IndexSet(integer: 20), to: 0)
    precondition(queue.entries.map(\.id) == beforeMove)
    let persisted = PlaybackQueueStore(defaults: defaults)
    precondition(persisted.entries.map(\.video.id) == queue.entries.map(\.video.id))
    precondition(persisted.current?.id == currentID)
    // Reordering is relative to upcoming rows, even after several tracks have played.
    let tracks = (0..<205).map { MusicVideo(id: "track-\($0)", title: "Track \($0)", channelTitle: "Artist", thumbnailURL: nil) }
    queue.replace(tracks.map { QueueEntry(video: $0) }, startAt: 2)
    let playedPrefix = Array(queue.entries.prefix(3))
    let upcoming = Array(queue.entries.dropFirst(3))
    queue.moveUpcoming(from: IndexSet(integer: 0), to: upcoming.count)
    precondition(Array(queue.entries.prefix(3)) == playedPrefix)
    precondition(queue.entries.last == upcoming.first && queue.index == 2)
    queue.moveUpcoming(from: IndexSet(integer: upcoming.count - 1), to: 0)
    precondition(Array(queue.entries.dropFirst(3)) == upcoming)
    queue.moveUpcoming(from: IndexSet([0, 2]), to: 4)
    precondition(Array(queue.entries.dropFirst(3).prefix(4)) == [upcoming[1], upcoming[3], upcoming[0], upcoming[2]])
    let reordered = PlaybackQueueStore(defaults: defaults)
    precondition(reordered.entries == queue.entries && reordered.current == queue.current)
    // Trimming old queue rows must not make their songs eligible for radio again.
    queue.select(queue.entries[10].id)
    let trimmedSong = queue.entries[0].video
    queue.append([])
    precondition(queue.entries.count == 200 && !queue.entries.contains { $0.video.id == trimmedSong.id })
    let radioRestored = PlaybackQueueStore(defaults: defaults)
    precondition(radioRestored.radioExclusions.contains(trimmedSong))
    radioRestored.append([trimmedSong])
    precondition(radioRestored.entries.count == 200)
    print("Passed: alternate-posting deduplication, version preservation, play-next, drag reorder, removal and persistence.")
    queue.replaceCollection([original, live, remix, live], startingAt: 1)
    precondition(queue.entries.map(\.video) == [live, remix, live] && queue.index == 0)
    let collectionRestored = PlaybackQueueStore(defaults: defaults)
    precondition(collectionRestored.entries.map(\.video) == [live, remix, live])
    precondition(collectionRestored.advance() && collectionRestored.current?.video == remix)
    queue.replaceCollection([original, live], startingAt: 1)
    precondition(queue.entries.map(\.video) == [live])
    queue.replaceCollection([original], startingAt: 9)
    precondition(queue.entries.map(\.video) == [live])
    print("Passed: collection selection queues only the selected and subsequent tracks, preserves repeats/order and restores them.")
    queue.replace([QueueEntry(video: original), QueueEntry(video: live)], startAt: 0)
    let playingBeforePlaylist = queue.current!.id
    queue.enqueueCollection([remix, original, remix], next: true)
    precondition(queue.entries.map(\.video) == [original, remix, original, remix, live])
    precondition(queue.current?.id == playingBeforePlaylist)
    queue.enqueueCollection([live, original])
    precondition(queue.entries.map(\.video) == [original, remix, original, remix, live, live, original])
    let restoredPlaylistQueue = PlaybackQueueStore(defaults: defaults)
    precondition(restoredPlaylistQueue.entries == queue.entries && restoredPlaylistQueue.current?.id == playingBeforePlaylist)
    let beforeEmptyPlaylist = queue.entries
    queue.enqueueCollection([], next: true)
    precondition(queue.entries == beforeEmptyPlaylist)
    queue.clear()
    queue.enqueueCollection([original, remix], next: true)
    precondition(queue.entries.map(\.video) == [original, remix] && queue.index == 0)
    print("Passed: whole-playlist next/end insertion, repeated tracks, current-track preservation, restore and empty queues.")
    let home = HomeViewModel(discovery: discovery)
    await home.load(signedIn: false, recent: [])
    precondition(home.trending == [video] && home.recommendations.isEmpty && discovery.likedCalls == 0)
    await home.load(signedIn: true, recent: [video])
    precondition(home.recommendations == [other] && discovery.likedCalls == 1)
    home.resetPersonalization()
    precondition(home.liked.isEmpty && home.recommendations.isEmpty)
    discovery.failLikes = true
    await home.load(signedIn: true, recent: [])
    precondition(home.personalError != nil && home.trending == [video] && !home.isLoading)
    await home.load(signedIn: false, recent: [])
    precondition(home.personalError == nil && home.recommendations.isEmpty)
    print("Passed: account-isolated history, queue persistence/order/advance/remove, guest Home, personalization, partial failure.")
}
