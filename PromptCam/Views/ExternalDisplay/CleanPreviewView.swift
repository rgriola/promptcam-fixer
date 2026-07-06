// July 6, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Gesture-free preview for HDMI window
// Reuses PreviewView (from CameraPreviewView.swift) but binds NO gesture recognizers.

import AVFoundation
import SwiftUI

struct CleanPreviewView: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}
