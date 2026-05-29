// May 29, 2026 - 12:57pm - GitHub Copilot
import SwiftUI

struct CameraView: View {
    @StateObject var viewModel: CameraViewModel

    var body: some View {
        ZStack {
            CameraPreviewView(session: viewModel.session)
                .ignoresSafeArea()

            TeleprompterOverlayView(
                text: viewModel.config.text,
                fontSize: viewModel.config.fontSize,
                speed: viewModel.config.speedPointsPerSecond,
                isScrolling: viewModel.isScrolling
            )
            .padding(.top, 40)

            VStack {
                Spacer()

                controls
                    .padding(Theme.space16)
                    .background(Theme.glassMaterial, in: RoundedRectangle(cornerRadius: Theme.radiusLg))
                    .padding(.horizontal, Theme.space16)
                    .padding(.bottom, Theme.space24)
            }
        }
        .alert("Permissions Required", isPresented: $viewModel.showPermissionsAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Enable camera, microphone, and photo library permissions in Settings.")
        }
        .alert("Error", isPresented: Binding(get: {
            viewModel.errorMessage != nil
        }, set: { _ in
            viewModel.errorMessage = nil
        })) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    private var controls: some View {
        VStack(spacing: Theme.space12) {
            TextField("Script", text: $viewModel.config.text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            .font(Theme.font16Regular)
            .foregroundStyle(Theme.primaryText)

            HStack {
                VStack(alignment: .leading) {
                    Text("Speed")
                        .font(Theme.font12Medium)
                        .foregroundStyle(Theme.secondaryText)
                    Slider(value: $viewModel.config.speedPointsPerSecond, in: 5...150, step: 1)
                }

                VStack(alignment: .leading) {
                    Text("Font")
                        .font(Theme.font12Medium)
                        .foregroundStyle(Theme.secondaryText)
                    Slider(value: $viewModel.config.fontSize, in: 16...72, step: 2)
                }
            }

            HStack(spacing: Theme.space12) {
                Button(viewModel.isScrolling ? "Pause" : "Scroll") {
                    viewModel.toggleScrolling()
                }
                .buttonStyle(.bordered)
                .font(Theme.font16Semibold)

                Button(viewModel.isRecording ? "Stop" : "Record") {
                    viewModel.toggleRecording()
                }
                .buttonStyle(.borderedProminent)
                .font(Theme.font16Semibold)
                .tint(viewModel.isRecording ? Theme.red : Theme.blue)
            }
        }
    }
}
