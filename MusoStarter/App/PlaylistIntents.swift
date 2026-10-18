import AppIntents
import Foundation

@available(iOS 16.0, *)
struct LibraryPlaylistEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Playlist")
    static var defaultQuery = LibraryPlaylistQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

@available(iOS 16.0, *)
struct LibraryPlaylistQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [LibraryPlaylistEntity] {
        let playlists = LibraryStore.playlistsForCurrentAccount()
        return playlists.filter { identifiers.contains($0.id.uuidString) }
            .map { LibraryPlaylistEntity(id: $0.id.uuidString, name: $0.name) }
    }
    func suggestedEntities() async throws -> [LibraryPlaylistEntity] {
        LibraryStore.playlistsForCurrentAccount().map { LibraryPlaylistEntity(id: $0.id.uuidString, name: $0.name) }
    }
    func entities(matching string: String) async throws -> [LibraryPlaylistEntity] {
        LibraryStore.playlistsForCurrentAccount()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map { LibraryPlaylistEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

@available(iOS 16.0, *)
struct PlayLibraryPlaylistIntent: AppIntent {
    static var title: LocalizedStringResource = "Play a Library Playlist"
    static var description = IntentDescription("Start playing a playlist saved in your Muso library.")
    static var openAppWhenRun = true
    @Parameter(title: "Playlist") var playlist: LibraryPlaylistEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        let url = URL(string: "muso://playlist/\(playlist.id)")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}

@available(iOS 16.0, *)
struct MusoAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayLibraryPlaylistIntent(),
            phrases: [
                "Play \(\.$playlist) on \(.applicationName)",
                "Play my \(\.$playlist) playlist in \(.applicationName)"
            ],
            shortTitle: "Play Playlist",
            systemImageName: "music.note.list"
        )
    }
}
