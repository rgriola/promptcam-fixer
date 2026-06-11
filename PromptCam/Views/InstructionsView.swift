// June 7, 2026 - 11:45am - GitHub Copilot (GPT-5.3-Codex)
import SwiftUI

/// Swipeable in-app instructions — presented as a sheet from the camera header grid button.
struct InstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private let pageCount = 1  // Start with one page, more can be added later

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.bgGrad.ignoresSafeArea()

            TabView(selection: $currentPage) {
                guideDogPage.tag(0)
                // Additional pages can be added here as swipeable tabs
            }
            .tabViewStyle(.page(indexDisplayMode: pageCount > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Dismiss button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.icon16)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(Theme.space16)
                    .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Page 1: Guide Dog

    private var guideDogPage: some View {
        ScrollView {
            VStack(spacing: Theme.space24) {
                Spacer().frame(height: Theme.space32)

                Image(systemName: "service.dog.fill")
                    .scaleEffect(x: -1, y: 1)
                    .font(Theme.display44)
                    .foregroundStyle(Theme.purple)

                Text("Guide Dog")
                    .font(Theme.font20Bold)
                    .foregroundStyle(Theme.primaryText)

                Text("This is the instructions page to walk through how to use Prompter Cam Fixer.")
                    .font(Theme.font16Regular)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.space24)

                Spacer()

                // "Got it" button on the page
                Button {
                    dismiss()
                } label: {
                    Text("Got it")
                        .font(Theme.font16Semibold)
                        .foregroundStyle(Theme.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.space16)
                        .background(Theme.purple)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
                }
                .padding(.horizontal, Theme.space24)
                .padding(.bottom, 60)
            }
        }
    }
}
