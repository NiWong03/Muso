import SwiftUI

struct LyricsView: View {
    @Environment(\.dismiss) private var dismiss
    let video: MusicVideo
    let timeline: PlaybackTimeline
    @AppStorage(LyricaService.serverKey) private var server = LyricaService.defaultServer
    @State private var result: LyricaLyrics?
    @State private var message: String?
    @State private var loading = true
    @State private var retry = 0

    private struct RequestID: Equatable {
        let query: LyricsQuery
        let server: String
        let retry: Int
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result, !loading, !result.timedLines.isEmpty {
                    SyncedLyricsView(video: video, lyrics: result, timeline: timeline)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(video.title).font(.title3.bold())
                            ArtistName(video: video).font(.subheadline).foregroundStyle(.secondary)
                            if loading {
                                ProgressView("Finding lyrics…")
                            } else if let result {
                                if result.timedLines.isEmpty {
                                    Text(result.staticText)
                                        .font(.body).lineSpacing(6)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Text("\(result.artist) · \(result.title)\nSource: \(result.source)")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(message ?? "No lyrics found for this track.")
                                    .foregroundStyle(.secondary)
                                Button("Retry lyrics") { retry += 1 }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                    }
                }
            }
            .background(HomePalette.paper)
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: RequestID(query: LyricsQuery(video: video), server: server, retry: retry)) {
            loading = true
            result = nil
            message = nil
            do {
                let resolved: MusicVideo
                if VideoArtistResolver.needsArtist(video) {
                    do { resolved = try await VideoArtistResolver.shared.resolve(video) }
                    catch {
                        try Task.checkCancellation()
                        // An artist embedded in the title can still support a lookup.
                        guard !LyricsQuery(video: video).artist.isEmpty else { throw LyricaError.missingTrack }
                        resolved = video
                    }
                } else {
                    resolved = video
                }
                let lyrics = try await LyricaService.shared.lyrics(query: LyricsQuery(video: resolved), server: server)
                try Task.checkCancellation()
                result = lyrics
                loading = false
            } catch {
                guard !Task.isCancelled else { return }
                if let error = error as? LyricaError {
                    message = error.localizedDescription
                } else {
                    message = "Couldn’t load lyrics. Check that your Lyrica server is running and its address in Settings is reachable."
                }
                loading = false
            }
        }
    }
}

private struct SyncedLyricsView: View {
    let video: MusicVideo
    let lyrics: LyricaLyrics
    @ObservedObject var timeline: PlaybackTimeline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeLine: Int? { lyrics.activeLine(at: timeline.elapsedTime) }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(video.title).font(.title3.bold())
                            ArtistName(video: video).font(.subheadline).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(lyrics.timedLines.indices, id: \.self) { index in
                                let line = lyrics.timedLines[index]
                                let active = activeLine == index
                                Text(styled(line, active: active))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(active ? HomePalette.coral : Color.secondary)
                                    .opacity(active ? 1 : 0.65)
                                    .scaleEffect(active && !reduceMotion ? 1.025 : 1, anchor: .leading)
                                    .contentTransition(.opacity)
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: active)
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: activeWord(in: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .id(index)
                                    .accessibilityAddTraits(active ? .isSelected : [])
                            }
                        }
                        // Room at both ends allows even the first/last line to reach center.
                        .padding(.vertical, geometry.size.height / 2)
                        Text("\(lyrics.artist) · \(lyrics.title)\nSource: \(lyrics.source)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
                .onChange(of: activeLine, initial: true) { _, _ in
                    centerActiveLine(proxy)
                }
                .onChange(of: geometry.size) { _, _ in
                    centerActiveLine(proxy)
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    // Resume following after a manual scroll ends; ignore our own animation.
                    if newPhase == .idle && (oldPhase == .interacting || oldPhase == .decelerating) {
                        centerActiveLine(proxy)
                    }
                }
                .task {
                    // Center after the initial layout when opening mid-song.
                    await Task.yield()
                    centerActiveLine(proxy, animated: false)
                }
            }
        }
    }

    private func centerActiveLine(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let activeLine else { return }
        withAnimation(animated && !reduceMotion ? .easeInOut(duration: 0.45) : nil) {
            proxy.scrollTo(activeLine, anchor: .center)
        }
    }

    private func activeWord(in line: TimedLyricLine) -> Int? {
        guard let words = line.words else { return nil }
        let milliseconds = timeline.elapsedTime * 1000
        return words.firstIndex { $0.start <= milliseconds && milliseconds < $0.end }
    }

    private func styled(_ line: TimedLyricLine, active: Bool) -> AttributedString {
        var text = AttributedString(line.text)
        guard active, let words = line.words else { return text }
        // Match in order so repeated words highlight their own occurrence.
        var cursor = text.startIndex
        let milliseconds = timeline.elapsedTime * 1000
        for word in words {
            guard !word.word.isEmpty,
                  let range = text[cursor...].range(of: word.word) else { continue }
            if word.start <= milliseconds && milliseconds < word.end {
                text[range].foregroundColor = Color.primary
                text[range].backgroundColor = HomePalette.coral.opacity(0.2)
            }
            cursor = range.upperBound
        }
        return text
    }
}
