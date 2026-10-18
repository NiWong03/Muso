import SwiftUI

struct SearchView: View {
    @StateObject var viewModel: SearchViewModel
    @ObservedObject var player: AVPlayerService
    @ObservedObject var auth: GoogleAuthStore
    @ObservedObject var history: ListeningHistoryStore
    @ObservedObject var library: LibraryStore
    @State private var operation: Task<Void, Never>?
    @State private var showsSettings = false
    @State private var queueNotice: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                SearchInputView(initialQuery: viewModel.query, accountID: auth.userID, busy: busy, hasSearched: viewModel.hasSearched || viewModel.isLoading, suggestions: viewModel.suggestions, onClear: clearSearch, onSearch: search)
                    .id(auth.userID ?? "guest")
                if busy { ProgressView(viewModel.isLoading ? "Searching…" : "Preparing audio…") }
                if let error = viewModel.errorMessage ?? player.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                if let queueNotice { Text(queueNotice).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if auth.isSignedIn && (!history.recent.isEmpty || !library.playlists.isEmpty) {
                    Label("Ranked using your listening and playlists", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
                List {
                    ForEach(viewModel.rankedResults) { result in
                        switch result {
                        case .collection(let collection):
                            HStack(spacing: 0) {
                                NavigationLink {
                                    MusicCollectionView(collection: collection, player: player, library: library, loadTracks: viewModel.tracks)
                                } label: {
                                    HStack(spacing: 12) {
                                        MusicArtwork(url: collection.thumbnailURL).frame(width: 48, height: 48)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(collection.title).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                                            Text(collection.kind.rawValue + (collection.subtitle.isEmpty ? "" : " · " + collection.subtitle))
                                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                    }
                                }
                                CollectionDetailsMenu(collection: collection, player: player, library: library, loadTracks: viewModel.tracks)
                            }
                            .disabled(busy)
                        case .track(let video):
                            HStack(spacing: 0) {
                                MusicVideoRow(video: video, compact: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .gesture(LongPressGesture(minimumDuration: 0.45).exclusively(before: TapGesture()).onEnded { action in
                                        guard !busy else { return }
                                        switch action {
                                        case .first: enqueue(video)
                                        case .second: player.playVideos([video])
                                        }
                                    })
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { player.playVideos([video]) }
                                    .accessibilityAction(named: "Add to end") { enqueue(video) }
                                    .accessibilityAction(named: "Play next") { enqueue(video, next: true) }
                                    .accessibilityHint("Tap to play. Hold to add to the end of the queue.")
                                AddToPlaylistMenu(library: library, track: video, minimal: true)
                                TrackDetailsMenu(video: video, player: player, library: library)
                            }
                            .disabled(busy)
                        }
                    }
                    if viewModel.nextPageToken != nil {
                        Button("Load More") { operation = Task { await viewModel.search(loadMore: true) } }
                            .disabled(busy)
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if viewModel.results.isEmpty && viewModel.collections.isEmpty && !busy && viewModel.errorMessage == nil {
                        ContentUnavailableView(viewModel.hasSearched ? "No Results" : "Find Your Music",
                                               systemImage: "magnifyingglass",
                                               description: Text("Search YouTube for music or paste a video link. Tap a result to play."))
                    }
                }
            }
            .padding()
            .sensoryFeedback(.success, trigger: queueNotice)
            .navigationTitle("Search Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { showsSettings = true } label: { Label("Account", systemImage: "gearshape") } }
            .sheet(isPresented: $showsSettings) { SettingsView(auth: auth, history: history) }
            .onDisappear { operation?.cancel() }
        }
    }
    private var busy: Bool { viewModel.isLoading || viewModel.isResolvingPlayback }
    private func enqueue(_ video: MusicVideo, next: Bool = false) {
        let added = player.enqueue(video, next: next)
        queueNotice = added ? "\(next ? "Playing next" : "Added to end"): \(video.title)" : "This song is already playing."
    }

    private func clearSearch() {
        operation?.cancel()
        viewModel.query = ""
        viewModel.reset()
    }

    private func search(_ query: String) {
        guard !busy else { return }
        viewModel.query = query
        viewModel.setPersonalization(auth.isSignedIn ? history.recent + library.playlists.flatMap(\.tracks) : [])
        operation = Task { await viewModel.search() }
    }
}

private struct SearchInputView: View {
    @State private var query: String
    @State private var showsRecentSearches = false
    @State private var suggestedTerms: [String] = []
    @State private var suggestionCache: [String: [String]] = [:]
    @State private var isSuggesting = false
    @AppStorage private var storedSearches: String
    @FocusState private var isFocused: Bool
    let busy: Bool
    let hasSearched: Bool
    private var compact: Bool { hasSearched && !isFocused }
    let suggestions: (String) async throws -> [String]
    let onClear: () -> Void
    let onSearch: (String) -> Void

    init(initialQuery: String, accountID: String?, busy: Bool, hasSearched: Bool, suggestions: @escaping (String) async throws -> [String], onClear: @escaping () -> Void, onSearch: @escaping (String) -> Void) {
        _query = State(initialValue: initialQuery)
        _storedSearches = AppStorage(wrappedValue: "[]", "muso.recentSearches.\(accountID ?? "guest")")
        self.busy = busy
        self.hasSearched = hasSearched
        self.suggestions = suggestions
        self.onClear = onClear
        self.onSearch = onSearch
    }

    private var recentSearches: [String] {
        guard let data = storedSearches.data(using: .utf8),
              let searches = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        var seen = Set<String>()
        return Array(searches.map(\.decodingHTMLEntities)
            .filter { seen.insert($0.lowercased()).inserted }.prefix(10))
    }

    private var suggestionQuery: String {
        isFocused ? query.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    private var displayedSuggestions: [String] {
        let local = recentSearches.filter { $0.localizedCaseInsensitiveContains(suggestionQuery) }
        var seen = Set<String>()
        return Array((local + suggestedTerms).filter { seen.insert($0.lowercased()).inserted }.prefix(6))
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Songs, albums, playlists, or video link", text: $query)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .focused($isFocused)
                        .onSubmit { submit(query) }
                        .font(.subheadline)
                        .frame(minHeight: compact ? 44 : 56)
                        .accessibilityLabel("Search music")
                    Button {
                        query = ""
                        suggestedTerms = []
                        isSuggesting = false
                        Task { @MainActor in
                            await Task.yield()
                            onClear()
                        }
                    } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                        .opacity(query.isEmpty ? 0 : 1)
                        .disabled(query.isEmpty)
                        .accessibilityHidden(query.isEmpty)
                }
                .padding(.horizontal, 16)
                .background {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(.secondarySystemBackground))
                        .onTapGesture { isFocused = true }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(isFocused ? HomePalette.coral : Color.primary.opacity(0.08), lineWidth: isFocused ? 2 : 1)
                        .allowsHitTesting(false)
                }
                .contentShape(RoundedRectangle(cornerRadius: 22))

                Button { submit(query) } label: {
                    Image(systemName: "arrow.up")
                        .font(.title3.weight(.semibold))
                        .frame(width: compact ? 44 : 56, height: compact ? 44 : 56)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(HomePalette.coral, in: RoundedRectangle(cornerRadius: 22))
                .opacity(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Search")
            }

            if isFocused && !suggestionQuery.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Suggestions").font(.subheadline.weight(.medium))
                        Spacer()
                        if isSuggesting { ProgressView().controlSize(.small) }
                    }.padding(.horizontal, 16).frame(minHeight: 40)
                    if displayedSuggestions.isEmpty {
                        Text(isSuggesting ? "Finding music…" : (suggestionQuery.count < 3 ? "Type at least 3 characters, or tap Search." : "Tap Search to see all results."))
                            .font(.footnote).foregroundStyle(.secondary).padding(16)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(displayedSuggestions, id: \.self) { term in
                                    Button { submit(term) } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                            Text(term).lineLimit(2).multilineTextAlignment(.leading)
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }.buttonStyle(.plain).disabled(busy)
                                }
                            }
                        }.frame(height: CGFloat(min(displayedSuggestions.count, 3)) * 56)
                    }
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            } else if !compact {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                    Button {
                        showsRecentSearches.toggle()
                    } label: {
                        HStack {
                            Label("Recent searches", systemImage: "clock")
                            Spacer()
                            Text("\(recentSearches.count)").foregroundStyle(.secondary)
                            Image(systemName: showsRecentSearches ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(showsRecentSearches ? "Expanded" : "Collapsed")
                    Button("Clear", role: .destructive) { storedSearches = "[]" }
                        .font(.subheadline)
                        .frame(minWidth: 44, minHeight: 48)
                        .padding(.trailing, 12)
                        .disabled(recentSearches.isEmpty)
                        .accessibilityLabel("Clear recent searches")
                    }

                    if showsRecentSearches {
                        Divider().padding(.horizontal, 16)
                        if recentSearches.isEmpty {
                            Text("Your last 10 searches will appear here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(recentSearches, id: \.self) { term in
                                        Button { submit(term) } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                                                Text(term).lineLimit(2).multilineTextAlignment(.leading)
                                                Spacer(minLength: 0)
                                                Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.secondary)
                                            }
                                            .padding(.horizontal, 16)
                                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(busy)
                                        .accessibilityHint("Search again")
                                    }
                                }
                            }
                            .frame(height: CGFloat(min(recentSearches.count, 4)) * 48)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .task(id: suggestionQuery) { await loadSuggestions() }
        .onChange(of: isFocused) { _, focused in
            if focused && !recentSearches.isEmpty { showsRecentSearches = true }
        }
        .onDisappear { isFocused = false }
    }

    private func loadSuggestions() async {
        let term = suggestionQuery
        suggestedTerms = []
        isSuggesting = false
        guard term.count >= 3, YouTubeVideoInput.videoID(from: term) == nil else { return }
        let key = term.lowercased()
        if let cached = suggestionCache[key] { suggestedTerms = cached; return }
        do {
            try await Task.sleep(for: .milliseconds(600))
            try Task.checkCancellation()
            isSuggesting = true
            let results = try await suggestions(term)
            try Task.checkCancellation()
            guard suggestionQuery == term else { return }
            if suggestionCache.count >= 30 { suggestionCache.removeAll() }
            suggestionCache[key] = results
            suggestedTerms = results
            isSuggesting = false
        } catch {
            if !Task.isCancelled && suggestionQuery == term { isSuggesting = false }
        }
    }

    private func submit(_ text: String) {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !term.isEmpty else { return }
        query = term
        let searches = [term] + recentSearches.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        if let data = try? JSONEncoder().encode(Array(searches.prefix(10))),
           let value = String(data: data, encoding: .utf8) {
            storedSearches = value
        }
        showsRecentSearches = false
        isFocused = false
        onSearch(term)
    }
}
