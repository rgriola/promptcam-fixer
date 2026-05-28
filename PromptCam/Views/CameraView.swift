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
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
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
        VStack(spacing: 12) {
            TextField("Script", text: $viewModel.config.text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            HStack {
                VStack(alignment: .leading) {
                    Text("Speed")
                    Slider(value: $viewModel.config.speedPointsPerSecond, in: 5...150, step: 1)
                }

                VStack(alignment: .leading) {
                    Text("Font")
                    Slider(value: $viewModel.config.fontSize, in: 16...72, step: 1)
                }
            }

            HStack(spacing: 12) {
                Button(viewModel.isScrolling ? "Pause" : "Scroll") {
                    viewModel.toggleScrolling()
                }
                .buttonStyle(.bordered)

                Button(viewModel.isRecording ? "Stop" : "Record") {
                    viewModel.toggleRecording()
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isRecording ? .red : .blue)
            }
        }
    }
}
