import Foundation
import Combine
import AppIntents

struct UserPlaylist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var tracks: [MusicVideo]
    var createdAt: Date
    init(id: UUID = UUID(), name: String, tracks: [MusicVideo] = [], createdAt: Date = Date()) {
        self.id = id; self.name = name; self.tracks = tracks; self.createdAt = createdAt
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var savedTrackIDs: Set<String> = []
    @Published private(set) var playlists: [UserPlaylist] = []
    private let defaults: UserDefaults
    private var accountID: String?
    private var savedKey: String { "muso.savedTrackIDs.\(accountID ?? "guest")" }
    private var playlistsKey: String { "muso.playlists.\(accountID ?? "guest")" }
    nonisolated private static let activeAccountKey = "muso.library.activeAccount"

    init(defaults: UserDefaults = .standard, userID: String? = nil) {
        self.defaults = defaults
        accountID = userID
        restore()
    }

    func switchAccount(_ userID: String?) {
        accountID = userID
        defaults.set(userID, forKey: Self.activeAccountKey)
        restore()
    }

    func toggleSaved(_ track: MusicTrack) {
        if savedTrackIDs.contains(track.id) { savedTrackIDs.remove(track.id) }
        else { savedTrackIDs.insert(track.id) }
        defaults.set(Array(savedTrackIDs), forKey: savedKey)
    }

    func isSaved(_ track: MusicTrack) -> Bool { savedTrackIDs.contains(track.id) }
    func createPlaylist(_ name: String) -> UserPlaylist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !playlists.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else { return nil }
        let playlist = UserPlaylist(name: trimmed)
        playlists.insert(playlist, at: 0)
        savePlaylists()
        return playlist
    }
    func add(_ track: MusicVideo, to playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              !playlists[index].tracks.contains(where: { QueueDeduplicator.isDuplicate($0, track) }) else { return }
        playlists[index].tracks.append(track)
        savePlaylists()
    }
    func setTracks(_ tracks: [MusicVideo], for playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].tracks = tracks
        savePlaylists()
    }
    func removeTrack(_ trackID: String, from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].tracks.removeAll { $0.id == trackID }
        savePlaylists()
    }
    func deletePlaylist(_ playlistID: UUID) {
        playlists.removeAll { $0.id == playlistID }
        savePlaylists()
    }

    nonisolated static func playlistsForCurrentAccount(defaults: UserDefaults = .standard) -> [UserPlaylist] {
        let userID = defaults.string(forKey: activeAccountKey)
        let key = "muso.playlists.\(userID ?? "guest")"
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([UserPlaylist].self, from: data)) ?? []
    }

    private func restore() {
        savedTrackIDs = Set(defaults.stringArray(forKey: savedKey) ?? [])
        if let data = defaults.data(forKey: playlistsKey), let stored = try? JSONDecoder().decode([UserPlaylist].self, from: data) {
            playlists = stored
        } else { playlists = [] }
    }
    private func savePlaylists() {
        if let data = try? JSONEncoder().encode(playlists) {
            defaults.set(data, forKey: playlistsKey)
            MusoAppShortcuts.updateAppShortcutParameters()
        }
    }
}
