import SwiftUI

struct MusicCollectionView: View {
    let collection: MusicCollection
    @ObservedObject var player: AVPlayerService
    @ObservedObject var library: LibraryStore
    let loadTracks: (MusicCollection) async throws -> [MusicVideo]
    @State private var tracks: [MusicVideo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var attempt = 0

    var body: some View {
        List {
            HStack(spacing: 16) {
                MusicArtwork(url: collection.thumbnailURL).frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text(collection.title).font(.title2.bold())
                    Text(collection.kind.rawValue).font(.subheadline).foregroundStyle(.secondary)
                    Text(collection.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }.listRowSeparator(.hidden)
            if isLoading {
                ProgressView("Loading tracks…")
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
                Button("Try again") { attempt += 1 }
            } else if tracks.isEmpty {
                ContentUnavailableView("No playable tracks", systemImage: "music.note.list",
                                       description: Text("This collection may be private or unavailable."))
            } else {
                Menu { PlaylistQueueActions(player: player, tracks: tracks) } label: {
                    Label("Queue playlist", systemImage: "text.append")
                }
                Section {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { index, video in
                        HStack(spacing: 4) {
                            Button { player.playCollection(tracks, startingAt: index) } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28)
                                    MusicVideoRow(video: video)
                                }.contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Plays this track, followed by the remaining tracks in order.")
                            TrackDetailsMenu(video: video, player: player, library: library)
                        }
                    }
                } header: { Text("\(tracks.count) tracks") }
            }
        }
        .listStyle(.plain)
        .navigationTitle(collection.kind.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: attempt) {
            isLoading = true
            errorMessage = nil
            do {
                let loaded = try await loadTracks(collection)
                try Task.checkCancellation()
                tracks = loaded
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
