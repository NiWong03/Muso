import SwiftUI

struct MusicTrackRow: View {
    let track: MusicTrack
    let isSaved: Bool
    let onSave: () -> Void
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                MusicArtwork(url: nil, symbol: track.artworkSymbol)
                    .frame(width: 60, height: 60)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).font(.headline).lineLimit(1)
                Text(track.artist).lineLimit(1).font(.subheadline).foregroundStyle(.secondary)
                Text(track.album).lineLimit(1).font(.caption).foregroundStyle(.tertiary)
            }

            Spacer()

            Button(action: onSave) {
                Image(systemName: isSaved ? "heart.fill" : "heart")
                    .foregroundStyle(isSaved ? .red : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 5)
    }
}
