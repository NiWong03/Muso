import SwiftUI

struct LyricsView: View {
    @Environment(\.dismiss) private var dismiss
    let video: MusicVideo
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(video.title).font(.title3.bold())
                    ArtistName(video: video).font(.subheadline).foregroundStyle(.secondary)
                    if loading {
                        ProgressView("Finding lyrics…")
                    } else if let result {
                        Text(result.lyrics)
                            .font(.body).lineSpacing(6)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
