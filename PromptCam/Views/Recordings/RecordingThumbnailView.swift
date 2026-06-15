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
                        .scaledToFill()
                } else {
                    ProgressView().tint(Theme.primaryText)
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(recording.formattedDuration)
                            .font(Theme.font12Medium)
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, Theme.space8)
                            .padding(.vertical, Theme.space4)
                            .background(.black.opacity(0.65),
                                        in: RoundedRectangle(cornerRadius: Theme.radiusSm))
                            .padding(Theme.space4)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        }
        .buttonStyle(.plain)
    }
}
