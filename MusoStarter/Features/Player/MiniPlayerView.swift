import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var player: AVPlayerService
    let openPlayer: () -> Void
    var body: some View {
        if let video = player.queueStore.current?.video {
            HStack(spacing: 12) {
                Button(action: openPlayer) {
                    HStack(spacing: 12) {
                        MusicArtwork(url: video.thumbnailURL).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(video.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(player.isPreparing ? "Preparing audio…" : video.channelTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Open player: \(video.title)")
                if player.isPreparing { ProgressView() }
                Group {
                    Button { if player.isPlaying { player.pause() } else { player.play() } } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 40, height: 44)
                    }.accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                }
                Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }
                    .disabled(!player.queueStore.hasNext && (!player.queueStore.autoplay || player.isPreparing))
                    .accessibilityLabel("Next track")
            }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 8)
        }
    }
}
