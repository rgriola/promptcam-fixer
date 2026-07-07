// July 6, 2026 - GitHub Copilot (Claude Sonnet 4.6) - SwiftUI root for HDMI window
// Black background + full-screen camera preview.
//
// TEMPORARY: bright "HDMI CONNECTED" banner is included to prove whether the
// external window is actually reaching the physical display or being silently
// mirrored away by iOS. Remove once HDMI output is verified working.

import AVFoundation
import SwiftUI

/// Toggle this to false once the HDMI feed is verified.
private let kShowHDMIDiagnosticOverlay = true

struct CleanOutputView: View {
    /// Provider so the service can hand us the session lazily (session may be
    /// nil for a brief moment if HDMI connects before the camera comes up).
    let sessionProvider: () -> AVCaptureSession?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CleanPreviewView(session: sessionProvider())
                .ignoresSafeArea()

            if kShowHDMIDiagnosticOverlay {
                VStack {
                    Text("HDMI CONNECTED")
                        .font(.system(size: 120, weight: .black))
                        .foregroundStyle(.yellow)
                        .padding(.top, 40)
                    Spacer()
                    Text("PromptCam External Display")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
    }
}
