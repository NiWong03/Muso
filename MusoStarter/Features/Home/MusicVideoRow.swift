import SwiftUI

struct MusicVideoRow: View {
    let video: MusicVideo
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            MusicArtwork(url: video.thumbnailURL)
                .frame(width: compact ? 48 : 60, height: compact ? 48 : 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(compact ? .subheadline.weight(.medium) : .headline)
                    .lineLimit(compact ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                ArtistName(video: video)
                    .font(compact ? .caption : .subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

/// Shared artist presentation keeps saved copies and active screens in sync.
struct ArtistName: View {
    let video: MusicVideo
    @ObservedObject private var metadata = VideoArtistResolver.shared

    var body: some View {
        Text(metadata.artist(for: video))
            .task(id: video.id) { await metadata.resolveForDisplay(video) }
    }
}
