import SwiftUI

struct HomeView: View {
    @ObservedObject var auth: GoogleAuthStore
    @ObservedObject var history: ListeningHistoryStore
    @ObservedObject var player: AVPlayerService
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var library: LibraryStore
    @State private var playlistTrack: MusicVideo?
    @State private var showsAccount = false
    @State private var showsCreatePlaylist = false

    private var topPicks: [MusicVideo] {
        viewModel.recommendations.isEmpty ? viewModel.trending : viewModel.recommendations
    }

    private var stationSeeds: [MusicVideo] {
        var artists = Set<String>()
        return Array((history.recent + viewModel.liked + topPicks).filter {
            artists.insert($0.channelTitle.lowercased()).inserted
        }.prefix(12))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 32) {
                    topPicksShelf
                    recentShelf
                    playlistShelf
                    stationShelf
                    if let error = viewModel.errorMessage ?? viewModel.personalError {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(error).font(.footnote).foregroundStyle(.secondary)
                            Button("Try again") { Task { await refresh() } }
                        }.padding(.horizontal, 20)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsAccount = true } label: {
                        Image(systemName: "person.crop.circle").font(.title2)
                    }.accessibilityLabel("Account and settings")
                }
            }
            .refreshable { await refresh() }
            .sheet(item: $playlistTrack) { track in
                TrackPlaylistPicker(library: library, track: track)
            }
            .sheet(isPresented: $showsAccount) { SettingsView(auth: auth, history: history) }
            .sheet(isPresented: $showsCreatePlaylist) {
                CreatePlaylistView(library: library) { _ in }
                    .presentationDetents([.medium])
            }
        }
    }

    private var topPicksShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Top picks", subtitle: viewModel.recommendations.isEmpty ? "Discover your next favorite" : "Chosen for your listening")
            if topPicks.isEmpty {
                if viewModel.isLoading {
                    ProgressView("Finding your music…").padding(.horizontal, 20)
                } else {
                    emptyShelf("New music will appear here when it’s available.")
                }
            } else {
                carousel {
                    ForEach(Array(topPicks.prefix(12).enumerated()), id: \.element.id) { index, video in
                        Button { player.playVideos(topPicks, startAt: index) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                MusicArtwork(url: video.thumbnailURL)
                                    .frame(width: 264, height: 264)
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "play.fill")
                                            .font(.body).foregroundStyle(.white)
                                            .frame(width: 40, height: 40)
                                            .background(.ultraThinMaterial, in: Circle())
                                            .padding(12)
                                    }
                                Text(video.title).font(.headline).lineLimit(2)
                                ArtistName(video: video).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(width: 264, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { queueActions(video) }
                    }
                }
            }
        }
    }

    private var recentShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Recently played", subtitle: "Pick up where you left off")
            if history.recent.isEmpty {
                emptyShelf(auth.isSignedIn ? "Play a song to start your listening history." : "Sign in to keep your recently played music here.")
            } else {
                carousel {
                    ForEach(Array(history.recent.prefix(20).enumerated()), id: \.element.id) { index, video in
                        Button { player.playVideos(history.recent, startAt: index) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                MusicArtwork(url: video.thumbnailURL).frame(width: 158, height: 158)
                                Text(video.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                ArtistName(video: video).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(width: 158, alignment: .leading)
                        }.buttonStyle(.plain).contextMenu { queueActions(video) }
                    }
                }
            }
        }
    }

    private var playlistShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Playlists", subtitle: "Your music, your way")
            carousel {
                ForEach(library.playlists) { playlist in
                    NavigationLink {
                        UserPlaylistView(playlistID: playlist.id, library: library, player: player)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            MusicArtwork(url: playlist.tracks.first?.thumbnailURL, symbol: "music.note.list")
                                .frame(width: 158, height: 158)
                            Text(playlist.name).font(.subheadline.weight(.medium)).lineLimit(2)
                            Text("\(playlist.tracks.count) songs").font(.caption).foregroundStyle(.secondary)
                        }.frame(width: 158, alignment: .leading)
                    }.buttonStyle(.plain)
                        .contextMenu { PlaylistQueueActions(player: player, tracks: playlist.tracks) }
                }
                Button { showsCreatePlaylist = true } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 158, height: 158)
                            .overlay { Image(systemName: "plus").font(.largeTitle.weight(.light)).foregroundStyle(HomePalette.coral) }
                        Text("New playlist").font(.subheadline.weight(.medium))
                        Text("Make it yours").font(.caption).foregroundStyle(.secondary)
                    }.frame(width: 158, alignment: .leading)
                }.buttonStyle(.plain)
            }
        }
    }

    private var stationShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Stations", subtitle: "Start with a favorite. Keep discovering.")
            if stationSeeds.isEmpty {
                emptyShelf("Stations will appear as music becomes available.")
            } else {
                carousel {
                    ForEach(stationSeeds) { seed in
                        Button { player.playStation(seed: seed) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                MusicArtwork(url: seed.thumbnailURL, symbol: "dot.radiowaves.left.and.right")
                                    .frame(width: 190, height: 190)
                                    .overlay(alignment: .bottomLeading) {
                                        Label("STATION", systemImage: "dot.radiowaves.left.and.right")
                                            .font(.caption2.weight(.bold)).tracking(1)
                                            .foregroundStyle(.white).padding(10)
                                            .background(.black.opacity(0.65), in: Capsule())
                                            .padding(10)
                                    }
                                ArtistName(video: seed)
                                    .font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text("Inspired by \(seed.title)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.frame(width: 190, alignment: .leading)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Play station inspired by \(seed.title)")
                    }
                }
            }
        }
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.horizontal, 20)
    }

    private func carousel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14, content: content)
                .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
    }

    private func emptyShelf(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
    }

    @ViewBuilder private func queueActions(_ video: MusicVideo) -> some View {
        Button("Add to playlist", systemImage: "text.badge.plus") { playlistTrack = video }
        Divider()
        Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") { player.enqueue(video, next: true) }
        Button("Add to end", systemImage: "text.append") { player.enqueue(video) }
    }

    private func refresh() async { await viewModel.load(signedIn: auth.isSignedIn, recent: history.recent) }
}
