// July 6, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Clean HDMI output singleton
// Owns the external-display window lifecycle via the modern scene delegate path.
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
        Log.hdmi.info("configure(session:) called; sceneAttached=\(self.attachedScene != nil, privacy: .public)")
        logConnectedScenes(context: "configure")
        if attachedScene != nil {
            refreshExternalWindow()
        }
    }

    // MARK: - Scene delegate lifecycle

    func attach(to windowScene: UIWindowScene) {
        Log.hdmi.info("attach(to:) scene role=\(String(describing: windowScene.session.role), privacy: .public)")
        guard attachedScene !== windowScene else {
            Log.hdmi.debug("attach(to:) same scene already attached — ignoring")
            return
        }
        attachedScene = windowScene

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        installRootView(on: window)
        window.isHidden = false
        externalWindow = window
        Log.hdmi.info("attach(to:) window installed frame=\(String(describing: window.frame), privacy: .public) hidden=\(window.isHidden, privacy: .public)")
    }

    func detach(from windowScene: UIWindowScene) {
        Log.hdmi.info("detach(from:) called")
        guard attachedScene === windowScene else {
            Log.hdmi.debug("detach(from:) not the attached scene — ignoring")
            return
        }
        attachedScene = nil
        externalWindow?.isHidden = true
        externalWindow = nil
        Log.hdmi.info("tore down external window")
    }

    // MARK: - Shared

    private func installRootView(on window: UIWindow) {
        let host = UIHostingController(rootView: CleanOutputView(sessionProvider: { [weak self] in
            self?.captureSession
        }))
        host.view.backgroundColor = .black
        host.view.frame = window.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.rootViewController = host
        window.layoutIfNeeded()
        Log.hdmi.info("installRootView on window frame=\(String(describing: window.frame), privacy: .public) hostViewFrame=\(String(describing: host.view.frame), privacy: .public)")
    }

    private func refreshExternalWindow() {
        externalWindow?.rootViewController?.view.setNeedsLayout()
    }

    private func logConnectedScenes(context: String) {
        let scenes = UIApplication.shared.connectedScenes
        Log.hdmi.info("[\(context, privacy: .public)] connectedScenes.count=\(scenes.count, privacy: .public)")
        for scene in scenes {
            Log.hdmi.info("  scene role=\(String(describing: scene.session.role), privacy: .public) state=\(String(describing: scene.activationState), privacy: .public)")
        }
    }
}
