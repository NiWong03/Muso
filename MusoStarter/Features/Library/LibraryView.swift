import SwiftUI

struct LibraryView: View {
    let tracks: [MusicTrack]
    @ObservedObject var library: LibraryStore
    @ObservedObject var player: AVPlayerService
    @State private var showsCreatePlaylist = false

    private var savedTracks: [MusicTrack] { tracks.filter { library.savedTrackIDs.contains($0.id) } }

    var body: some View {
        NavigationStack {
            List {
                Section("Playlists") {
                    if library.playlists.isEmpty {
                        ContentUnavailableView("No Playlists Yet", systemImage: "music.note.list",
                                               description: Text("Create a playlist, then add songs from Search."))
                            .listRowBackground(Color.clear)
                    }
                    ForEach(library.playlists) { playlist in
                        NavigationLink {
                            UserPlaylistView(playlistID: playlist.id, library: library, player: player)
                        } label: {
                            HStack(spacing: 12) {
                                MusicArtwork(url: playlist.tracks.first?.thumbnailURL)
                                    .frame(width: 58, height: 58)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name).font(.headline)
                                    Text("\(playlist.tracks.count) songs").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !playlist.tracks.isEmpty {
                                    Button { player.playVideos(playlist.tracks) } label: {
                                        Image(systemName: "play.fill").frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Play \(playlist.name)")
                                }
                            }
                        }
                        .contextMenu { PlaylistQueueActions(player: player, tracks: playlist.tracks) }
                        .swipeActions {
                            Button("Delete", role: .destructive) { library.deletePlaylist(playlist.id) }
                        }
                    }
                    Button { showsCreatePlaylist = true } label: {
                        Label("Create Playlist", systemImage: "plus")
                    }
                }
                Section("Saved Songs") {
                    if savedTracks.isEmpty {
                        Text("Save a track from Home to see it here.").foregroundStyle(.secondary)
                    } else {
                        ForEach(savedTracks) { track in
                            MusicTrackRow(track: track, isSaved: true,
                                          onSave: { library.toggleSaved(track) }, onPlay: { play(track) })
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsCreatePlaylist = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Create playlist")
                }
            }
            .sheet(isPresented: $showsCreatePlaylist) {
                CreatePlaylistView(library: library)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func play(_ track: MusicTrack) {
        player.setQueue(savedTracks.map(\.playableTrack), startAt: savedTracks.firstIndex(of: track) ?? 0)
    }
}

struct CreatePlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    var onCreated: (UserPlaylist) -> Void = { _ in }
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist name") {
                    TextField("My playlist", text: $name).textInputAutocapitalization(.words)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if let playlist = library.createPlaylist(name) { onCreated(playlist); dismiss() }
                        else { error = "Enter a name that is not already in your library." }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct AddToPlaylistMenu: View {
    @ObservedObject var library: LibraryStore
    let track: MusicVideo
    var minimal = false
    var showsTitle = false
    @State private var showsCreate = false

    var body: some View {
        Menu {
            if library.playlists.isEmpty {
                Button("Create Playlist…", systemImage: "plus") { showsCreate = true }
            } else {
                ForEach(library.playlists) { playlist in
                    Button(playlist.name, systemImage: "text.badge.plus") {
                        library.add(track, to: playlist.id)
                    }
                }
                Divider()
                Button("New Playlist…", systemImage: "plus") { showsCreate = true }
            }
        } label: {
            if showsTitle {
                Label("Add to playlist", systemImage: "text.badge.plus")
                    .font(.subheadline).padding(.horizontal, 12).frame(minHeight: 44)
            } else {
            Image(systemName: minimal ? "plus" : "text.badge.plus")
                .font(.system(size: minimal ? 14 : 17, weight: .regular))
                .foregroundStyle(minimal ? Color.secondary : Color.accentColor)
                .frame(width: minimal ? 28 : 36, height: minimal ? 28 : 36)
                .background(minimal ? Color.secondary.opacity(0.08) : .clear, in: Circle())
                .frame(width: minimal ? 44 : 36, height: minimal ? 44 : 36).contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(track.title) to a playlist")
        .sheet(isPresented: $showsCreate) { CreatePlaylistView(library: library) { playlist in library.add(track, to: playlist.id) }.presentationDetents([.medium]) }
    }
}

struct UserPlaylistView: View {
    let playlistID: UUID
    @ObservedObject var library: LibraryStore
    @ObservedObject var player: AVPlayerService
    private var playlist: UserPlaylist? { library.playlists.first { $0.id == playlistID } }

    var body: some View {
        Group {
            if let playlist {
                List {
                    if playlist.tracks.isEmpty {
                        ContentUnavailableView("Playlist Is Empty", systemImage: "music.note.list",
                                               description: Text("Use Search to add songs to this playlist."))
                    } else {
                        Section {
                            ForEach(Array(playlist.tracks.enumerated()), id: \.offset) { index, video in
                                HStack {
                                    Button { player.playVideos(playlist.tracks, startAt: index) } label: { MusicVideoRow(video: video) }
                                        .buttonStyle(.plain)
                                    TrackDetailsMenu(video: video, player: player, library: library) {
                                        library.removeTrack(video.id, from: playlistID)
                                    }
                                }
                            }
                            .onMove { offsets, destination in
                                var reordered = playlist.tracks
                                reordered.move(fromOffsets: offsets, toOffset: destination)
                                library.setTracks(reordered, for: playlistID)
                            }
                        } header: {
                            HStack {
                                Text("\(playlist.tracks.count) songs")
                                Spacer()
                                Button("Play") { player.playVideos(playlist.tracks) }.disabled(playlist.tracks.isEmpty)
                                Menu { PlaylistQueueActions(player: player, tracks: playlist.tracks) } label: {
                                    Image(systemName: "text.append")
                                }.accessibilityLabel("Queue playlist")
                            }
                        }
                    }
                }
                .toolbar { EditButton() }
            } else {
                ContentUnavailableView("Playlist Removed", systemImage: "music.note.list")
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PlaylistQueueActions: View {
    @ObservedObject var player: AVPlayerService
    let tracks: [MusicVideo]

    var body: some View {
        Button("Play playlist next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            player.enqueueCollection(tracks, next: true)
        }.disabled(tracks.isEmpty)
        Button("Add playlist to end", systemImage: "text.append") {
            player.enqueueCollection(tracks)
        }.disabled(tracks.isEmpty)
    }
}

struct TrackPlaylistPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryStore
    let tracks: [MusicVideo]

    init(library: LibraryStore, track: MusicVideo) {
        self.library = library
        self.tracks = [track]
    }

    init(library: LibraryStore, tracks: [MusicVideo]) {
        self.library = library
        self.tracks = tracks
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(library.playlists) { playlist in
                    Button(playlist.name, systemImage: "music.note.list") {
                        tracks.forEach { library.add($0, to: playlist.id) }
                        dismiss()
                    }
                }
                NavigationLink("New playlist…") {
                    CreatePlaylistView(library: library) { playlist in
                        tracks.forEach { library.add($0, to: playlist.id) }
                        dismiss()
                    }
                }
            }
            .navigationTitle("Add to playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
