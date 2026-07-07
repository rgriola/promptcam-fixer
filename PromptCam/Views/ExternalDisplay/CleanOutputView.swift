// July 6, 2026 - GitHub Copilot (Claude Sonnet 4.6) - SwiftUI root for HDMI window
// NOTE: No longer used by ExternalDisplayService — it now uses a pure UIKit
// host (ExternalDisplayHostViewController) for reliable rendering on non-key
// external UIWindows. This view is kept for previews and as a fallback.

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
