import SwiftUI

/// The card determines layout; downloaded images only draw inside its bounds.
/// This keeps wide YouTube thumbnails from supplying an oversized ideal width.
struct MusicArtwork: View {
    let url: URL?
    var symbol = "music.note"

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { bounds in
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            LinearGradient(colors: [HomePalette.coral, HomePalette.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
                                .overlay {
                                    Image(systemName: symbol)
                                        .font(.system(size: min(bounds.size.width * 0.35, 54)))
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                        }
                    }
                    .frame(width: bounds.size.width, height: bounds.size.height)
                    .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}
