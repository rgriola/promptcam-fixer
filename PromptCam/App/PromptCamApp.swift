import SwiftUI

@main
struct PromptCamApp: App {
    var body: some Scene {
        WindowGroup {
            CameraView(viewModel: CameraViewModel())
        }
    }
}
