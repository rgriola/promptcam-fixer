// July 6, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Clean HDMI output singleton
// Owns the external-display window lifecycle.
// See HDMI-Cleanoutput.md for the full contract.
//
// NOTE: iOS does not support AVCaptureAudioPreviewOutput (macOS-only). Mic-audio
// monitoring to the HDMI route requires AVAudioEngine and is tracked as a
// follow-up. Recording audio is unaffected — mic still writes to the file.

import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class ExternalDisplayService {
    static let shared = ExternalDisplayService()
    private init() {}

    private var captureSession: AVCaptureSession?
    private var externalWindow: UIWindow?
    private weak var attachedScene: UIWindowScene?

    /// Called once from `CameraViewModel.onAppear` after the capture session is running.
    /// Safe to call multiple times — later calls just update the stored reference.
    func configure(session: AVCaptureSession) {
        captureSession = session
        if attachedScene != nil {
            refreshExternalWindow()
        }
        print("[ExternalDisplayService] configured session; sceneAttached=\(attachedScene != nil)")
    }

    /// Called by `ExternalSceneDelegate.scene(_:willConnectTo:options:)`.
    func attach(to windowScene: UIWindowScene) {
        guard attachedScene !== windowScene else { return }
        attachedScene = windowScene

        let window = UIWindow(windowScene: windowScene)
        let host = UIHostingController(rootView: CleanOutputView(sessionProvider: { [weak self] in
            self?.captureSession
        }))
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.isHidden = false
        externalWindow = window
        print("[ExternalDisplayService] attached external scene")
    }

    /// Called by `ExternalSceneDelegate.sceneDidDisconnect`.
    func detach(from windowScene: UIWindowScene) {
        guard attachedScene === windowScene else { return }
        attachedScene = nil
        externalWindow?.isHidden = true
        externalWindow = nil
        print("[ExternalDisplayService] detached external scene")
    }

    private func refreshExternalWindow() {
        externalWindow?.rootViewController?.view.setNeedsLayout()
    }
}
