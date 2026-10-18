import SwiftUI

struct EmptyMusicSection: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.weight(.bold))
                Spacer()
                Text("Coming soon").font(.caption.weight(.semibold)).foregroundStyle(HomePalette.coral)
            }

            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(HomePalette.ink)
                    .frame(width: 48, height: 48)
                    .background(HomePalette.mustard.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(subtitle).font(.subheadline).foregroundStyle(HomePalette.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
