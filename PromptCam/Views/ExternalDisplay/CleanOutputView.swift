// July 6, 2026 - GitHub Copilot (Claude Sonnet 4.6) - SwiftUI root for HDMI window
// Black background + full-screen camera preview. No overlays, no controls, no teleprompter.

import AVFoundation
import SwiftUI

struct CleanOutputView: View {
    /// Provider so the service can hand us the session lazily (session may be
    /// nil for a brief moment if HDMI connects before the camera comes up).
    let sessionProvider: () -> AVCaptureSession?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CleanPreviewView(session: sessionProvider())
                .ignoresSafeArea()
        }
    }
}
