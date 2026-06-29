import SwiftUI

struct RecordingThumbnailView: View {
    let recording: Recording
    let thumbnail: UIImage?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Theme.black

                if let image = thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        // Pin frame to the parent's proposed size BEFORE scaledToFill
                        // so the layout pass constrains the image rather than letting
                        // it expand to its intrinsic aspect ratio first.
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaledToFill()
                } else {
                    ProgressView().tint(Theme.primaryText)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            // Clip the ZStack — not just the image — so nothing escapes the square boundary
            .clipped()
            // Overlays are applied after clipping so they render sharp at the corners
            .overlay(alignment: .topLeading) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                    .padding(Theme.space4)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(recording.formattedDuration)
                    .font(Theme.font12Medium)
                    .foregroundStyle(Theme.primaryText)
                    .padding(.horizontal, Theme.space8)
                    .padding(.vertical, Theme.space4)
                    .background(.black.opacity(0.65),
                                in: RoundedRectangle(cornerRadius: Theme.radiusSm))
                    .padding(Theme.space4)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        }
        .buttonStyle(.plain)
    }
}
