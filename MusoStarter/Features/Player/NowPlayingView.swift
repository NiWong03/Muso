import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var queueEditMode: EditMode = .inactive
    @ObservedObject var library: LibraryStore
    @ObservedObject var player: AVPlayerService
    @ObservedObject private var timeline: PlaybackTimeline

    init(player: AVPlayerService, library: LibraryStore) {
        self.library = library
        self.player = player
        self.timeline = player.timeline
    }

    var body: some View {
        NavigationStack {
            List {
                if let entry = player.queueStore.current {
                    VStack(spacing: 22) {
                        MusicArtwork(url: entry.video.thumbnailURL)
                            .frame(maxWidth: 360)
                            .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.video.title).font(.title2.bold()).lineLimit(3)
                            Text(entry.video.channelTitle).lineLimit(2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if player.isPreparing { ProgressView("Preparing audio…") }
                        if let error = player.errorMessage {
                            Text(error).font(.footnote).foregroundStyle(.red)
                            Button("Retry playback") { player.playEntry(entry.id) }
                        }
                        VStack {
                            Slider(value: Binding(get: { min(timeline.elapsedTime, max(1, timeline.duration)) }, set: { player.seek(to: $0) }), in: 0...max(1, timeline.duration))
                                .disabled(timeline.duration <= 0 || player.isPreparing).accessibilityLabel("Playback position")
                            HStack { Text(timeLabel(timeline.elapsedTime)); Spacer(); Text(timeline.duration > 0 ? timeLabel(timeline.duration) : "--:--") }
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 40) {
                            Button { player.previous() } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel("Previous track")
                            Button { if player.isPlaying { player.pause() } else { player.play() } } label: {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .frame(width: 68, height: 68).foregroundStyle(.white).background(HomePalette.coral, in: Circle())
                            }.accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                            Button { player.next() } label: { Image(systemName: "forward.end.fill") }
                                .disabled(!player.queueStore.hasNext && (!player.queueStore.autoplay || player.isPreparing)).accessibilityLabel("Next track")
                        }.font(.title2).buttonStyle(.plain)
                        AddToPlaylistMenu(library: library, track: entry.video, showsTitle: true)
                    }.frame(maxWidth: 560).frame(maxWidth: .infinity).padding(20)
                        .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
                    queue
                } else {
                    ContentUnavailableView("Nothing queued", systemImage: "music.note.list", description: Text("Play a mix from Home or choose a song in Search."))
                }
            }.environment(\.editMode, $queueEditMode).listStyle(.plain).scrollContentBackground(.hidden).background(HomePalette.paper).navigationTitle("Now Playing").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "chevron.down") }
                            .accessibilityLabel("Minimize player")
                    }
                }
        }
    }
    private var queue: some View {
        Section {
            Toggle("Autoplay", isOn: Binding(get: { player.queueStore.autoplay }, set: { player.queueStore.autoplay = $0 }))
            ForEach(Array(player.queueStore.entries.dropFirst(player.queueStore.index + 1))) { entry in
                HStack(spacing: 8) {
                    Button { player.playEntry(entry.id) } label: { MusicVideoRow(video: entry.video) }
                        .buttonStyle(.plain)
                        .disabled(queueEditMode.isEditing)
                    Spacer(minLength: 0)
                    if !queueEditMode.isEditing {
                        QueueOptionsButton(entry: entry, queue: player.queueStore, library: library)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Remove", role: .destructive) { player.queueStore.remove(entry.id) }
                }
            }
            .onMove { offsets, destination in
                player.queueStore.moveUpcoming(from: offsets, to: destination)
            }
            if !player.queueStore.hasNext {
                Text(player.queueStore.autoplay ? "More songs will be added after this track." : "This is the last track.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Up next").font(.title2.bold())
                Spacer()
                Button(queueEditMode.isEditing ? "Done" : "Reorder") {
                    withAnimation { queueEditMode = queueEditMode.isEditing ? .inactive : .active }
                }
                .font(.subheadline.weight(.semibold))
                .disabled(!queueEditMode.isEditing && player.queueStore.entries.count - player.queueStore.index < 3)
                .accessibilityLabel(queueEditMode.isEditing ? "Finish reordering queue" : "Reorder queue")
            }.textCase(nil)
        } footer: {
            Text("Tap Reorder, then drag the handles to move songs. Tap Done to return to swipe-to-remove.")
        }
    }
    private func timeLabel(_ seconds: Double) -> String {
        let value = Int(max(0, seconds)); return String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// Attach presentation to the tapped row, so iPhone keeps a compact, anchored menu.
private struct QueueOptionsButton: View {
    let entry: QueueEntry
    @ObservedObject var queue: PlaybackQueueStore
    @ObservedObject var library: LibraryStore
    @State private var isPresented = false
    @State private var choosingPlaylist = false
    @State private var showsCreatePlaylist = false

    var body: some View {
        Button {
            choosingPlaylist = false
            isPresented = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.08), in: Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Queue actions for \(entry.video.title)")
        .accessibilityHint("Tap for playlist and queue options.")
        .accessibilityAction(named: "Move up") { queue.moveUp(entry.id) }
        .accessibilityAction(named: "Move to end") { queue.moveToEnd(entry.id) }
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(spacing: 0) {
                if choosingPlaylist {
                    option("Back", symbol: "chevron.left") { choosingPlaylist = false }
                    Divider()
                    if !library.playlists.isEmpty {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(library.playlists) { playlist in
                                    option(playlist.name, symbol: "music.note.list") {
                                        library.add(entry.video, to: playlist.id)
                                        isPresented = false
                                    }
                                }
                            }
                        }.frame(height: min(CGFloat(library.playlists.count) * 44, 220))
                    }
                    option("New playlist…", symbol: "plus") {
                        isPresented = false
                        showsCreatePlaylist = true
                    }
                } else {
                    option("Add to playlist", symbol: "text.badge.plus") { choosingPlaylist = true }
                    Divider()
                    option("Play next", symbol: "text.line.first.and.arrowtriangle.forward") {
                        isPresented = false
                        if let first = queue.entries.dropFirst(queue.index + 1).first {
                            queue.move(entry.id, to: first.id)
                        }
                    }
                    option("Move to end", symbol: "text.append") {
                        isPresented = false
                        queue.moveToEnd(entry.id)
                    }
                    Divider()
                    option("Remove from queue", symbol: "trash", destructive: true) {
                        isPresented = false
                        queue.remove(entry.id)
                    }
                }
            }
            .padding(6)
            .frame(width: 224)
            .presentationCompactAdaptation(.popover)
        }
        .sheet(isPresented: $showsCreatePlaylist) {
            CreatePlaylistView(library: library) { playlist in
                library.add(entry.video, to: playlist.id)
            }.presentationDetents([.medium])
        }
    }

    private func option(_ title: String, symbol: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18)
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
