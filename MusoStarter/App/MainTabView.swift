import SwiftUI
import UIKit

struct MainTabView: View {
    enum Tab: Int, Hashable { case home, search, library }
    @State private var selection: Tab = .home
    @State private var showsPlayer = false
    @StateObject private var library = LibraryStore()
    @StateObject private var auth: GoogleAuthStore
    @StateObject private var history: ListeningHistoryStore
    @StateObject private var player: AVPlayerService
    @StateObject private var home: HomeViewModel
    @StateObject private var search: SearchViewModel

    init() {
        let auth = GoogleAuthStore()
        let history = ListeningHistoryStore()
        let provider = SDKMusicProvider(accessToken: { try await auth.accessToken() })
        let discovery = YouTubeDiscoveryService(provider: provider)
        let player = AVPlayerService()
        player.onPlayed = { history.record($0) }
        player.autoplaySource = { [weak player] seed, excluded in
            let prior = player?.queueStore.radioExclusions ?? []
            return try await discovery.recommendations(seeds: [seed] + prior, excluding: excluded)
        }
        _auth = StateObject(wrappedValue: auth)
        _history = StateObject(wrappedValue: history)
        _player = StateObject(wrappedValue: player)
        _home = StateObject(wrappedValue: HomeViewModel(discovery: discovery))
        _search = StateObject(wrappedValue: SearchViewModel(service: YouTubeService(), searchService: YouTubeSearchService(provider: provider)))
    }

    private func playPlaylistURL(_ url: URL) {
        guard url.scheme == "muso", url.host == "playlist",
              let idString = url.pathComponents.dropFirst().first,
              let id = UUID(uuidString: idString),
              let playlist = library.playlists.first(where: { $0.id == id }),
              !playlist.tracks.isEmpty else { return }
        selection = .library
        player.playVideos(playlist.tracks)
    }

    private func switchTab(_ offset: Int) {
        guard !showsPlayer, let next = Tab(rawValue: selection.rawValue + offset) else { return }
        withAnimation(.snappy(duration: 0.25)) { selection = next }
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView(auth: auth, history: history, player: player, viewModel: home, library: library)
                .modifier(TabSwipeModifier(onSwipe: switchTab))
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(Tab.home)
            SearchView(viewModel: search, player: player, auth: auth, history: history, library: library)
                .modifier(TabSwipeModifier(onSwipe: switchTab))
                .tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(Tab.search)
            LibraryView(tracks: SampleMusicCatalog.tracks, library: library, player: player)
                .modifier(TabSwipeModifier(onSwipe: switchTab))
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }.tag(Tab.library)
        }
        .tabViewBottomAccessory(isEnabled: player.queueStore.current != nil) {
            MiniPlayerView(player: player) { showsPlayer = true }
        }
        .sheet(isPresented: $showsPlayer) {
            NowPlayingView(player: player, library: library)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .tint(HomePalette.coral)
        .onOpenURL(perform: playPlaylistURL)
        .task { await auth.restore() }
        .task(id: auth.userID) {
            let userID = auth.userID
            history.switchAccount(userID)
            library.switchAccount(userID)
            player.switchAccount(userID)
            home.resetPersonalization()
            search.reset()
            await home.load(signedIn: userID != nil, recent: history.recent)
        }
    }
}

private struct TabSwipeModifier: ViewModifier {
    let onSwipe: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .gesture(TabSwipeGesture(direction: .left) { onSwipe(1) })
            .gesture(TabSwipeGesture(direction: .right) { onSwipe(-1) })
    }
}

private struct TabSwipeGesture: UIGestureRecognizerRepresentable {
    let direction: UISwipeGestureRecognizer.Direction
    let action: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UISwipeGestureRecognizer {
        let recognizer = UISwipeGestureRecognizer()
        recognizer.direction = direction
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UISwipeGestureRecognizer, context: Context) {
        if recognizer.state == .ended { action() }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView || current is UISlider { return false }
                if let scroll = current as? UIScrollView,
                   scroll.alwaysBounceHorizontal || scroll.contentSize.width > scroll.bounds.width + 1 {
                    return false
                }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
