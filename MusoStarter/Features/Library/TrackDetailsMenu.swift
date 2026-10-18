import SwiftUI

struct DetailsMenuLabel: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Color.secondary.opacity(0.08), in: Circle())
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }
}

struct TrackDetailsMenu: View {
    let video: MusicVideo
    @ObservedObject var player: AVPlayerService
    @ObservedObject var library: LibraryStore
    var onDelete: (() -> Void)? = nil
    @State private var showsPlaylists = false

    var body: some View {
        Menu {
            Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") { player.enqueue(video, next: true) }
            Button("Play last", systemImage: "text.append") { player.enqueue(video) }
            Button("Add to playlist", systemImage: "text.badge.plus") { showsPlaylists = true }
            if let onDelete {
                Divider()
                Button("Delete from playlist", systemImage: "trash", role: .destructive, action: onDelete)
            }
        } label: { DetailsMenuLabel() }
        .buttonStyle(.plain)
        .accessibilityLabel("Details for \(video.title)")
        .sheet(isPresented: $showsPlaylists) { TrackPlaylistPicker(library: library, track: video) }
    }
}

struct CollectionDetailsMenu: View {
    let collection: MusicCollection
    @ObservedObject var player: AVPlayerService
    @ObservedObject var library: LibraryStore
    let loadTracks: (MusicCollection) async throws -> [MusicVideo]
    @State private var operation: Task<Void, Never>?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedTracks: [MusicVideo] = []
    @State private var showsPlaylists = false

    private enum Action { case next, last, save }

    var body: some View {
        Menu {
            Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") { perform(.next) }
            Button("Play last", systemImage: "text.append") { perform(.last) }
            Button("Add to playlist", systemImage: "text.badge.plus") { perform(.save) }
        } label: {
            if isLoading { ProgressView().frame(width: 44, height: 44) }
            else { DetailsMenuLabel() }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "Loading \(collection.title)" : "Details for \(collection.title)")
        .sheet(isPresented: $showsPlaylists) { TrackPlaylistPicker(library: library, tracks: selectedTracks) }
        .alert("Couldn’t load playlist", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onDisappear { operation?.cancel(); isLoading = false }
    }

    private func perform(_ action: Action) {
        guard !isLoading else { return }
        isLoading = true
        operation = Task { @MainActor in
            defer { isLoading = false }
            do {
                let tracks = try await loadTracks(collection)
                try Task.checkCancellation()
                guard !tracks.isEmpty else {
                    errorMessage = "This playlist has no playable tracks."
                    return
                }
                switch action {
                case .next: player.enqueueCollection(tracks, next: true)
                case .last: player.enqueueCollection(tracks)
                case .save: selectedTracks = tracks; showsPlaylists = true
                }
            } catch is CancellationError {
            } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
        }
    }
}
