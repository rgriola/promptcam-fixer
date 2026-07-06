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
    /// Legacy path: retains the external UIScreen when scene delegate never fires.
    private weak var attachedScreen: UIScreen?
    private var didStartLegacyObservation = false

    /// Called once from `CameraViewModel.onAppear` after the capture session is running.
    /// Safe to call multiple times — later calls just update the stored reference.
    func configure(session: AVCaptureSession) {
        captureSession = session
        Log.hdmi.info("configure(session:) called; sceneAttached=\(self.attachedScene != nil, privacy: .public) screenAttached=\(self.attachedScreen != nil, privacy: .public)")
        logConnectedScreens(context: "configure")
        startLegacyObservationIfNeeded()
        if attachedScene != nil || attachedScreen != nil {
            refreshExternalWindow()
        }
        // If HDMI was already connected before we configured, the scene delegate
        // may have fired with a nil captureSession — try the legacy path now.
        attemptLegacyAttachIfNeeded()
    }

    // MARK: - Scene-delegate path (iOS 16+ recommended)

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
        tearDownWindow(reason: "scene detach")
    }

    // MARK: - Legacy UIScreen path (iPhone HDMI adapter fallback)

    private func startLegacyObservationIfNeeded() {
        guard !didStartLegacyObservation else { return }
        didStartLegacyObservation = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenConnect(_:)),
            name: UIScreen.didConnectNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenDisconnect(_:)),
            name: UIScreen.didDisconnectNotification,
            object: nil
        )
        Log.hdmi.debug("legacy UIScreen observers registered")
    }

    private func attemptLegacyAttachIfNeeded() {
        // If no scene delegate has fired yet and there is a non-main UIScreen
        // present, attach via the legacy path.
        guard attachedScene == nil, attachedScreen == nil else { return }
        let externals = UIScreen.screens.filter { $0 !== UIScreen.main }
        if let screen = externals.first {
            Log.hdmi.info("legacy attach on existing external screen bounds=\(String(describing: screen.bounds), privacy: .public)")
            legacyAttach(to: screen)
        }
    }

    @objc private nonisolated func handleScreenConnect(_ note: Notification) {
        guard let screen = note.object as? UIScreen else { return }
        Task { @MainActor in
            Log.hdmi.info("UIScreen.didConnectNotification bounds=\(String(describing: screen.bounds), privacy: .public)")
            self.legacyAttach(to: screen)
        }
    }

    @objc private nonisolated func handleScreenDisconnect(_ note: Notification) {
        guard let screen = note.object as? UIScreen else { return }
        Task { @MainActor in
            Log.hdmi.info("UIScreen.didDisconnectNotification")
            if self.attachedScreen === screen {
                self.attachedScreen = nil
                self.tearDownWindow(reason: "screen disconnect")
            }
        }
    }

    private func legacyAttach(to screen: UIScreen) {
        // If the scene-delegate path already handled this, don't double-attach.
        guard attachedScene == nil else {
            Log.hdmi.debug("legacyAttach skipped — scene path already active")
            return
        }
        attachedScreen = screen

        // Find a UIWindowScene we can host on. On iPhone HDMI adapter, the OS
        // may not create a dedicated external scene, so we host on the main
        // window scene and target the external screen via UIWindow.screen.
        let hostScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window: UIWindow
        if let hostScene {
            window = UIWindow(windowScene: hostScene)
        } else {
            window = UIWindow(frame: screen.bounds)
        }
        window.screen = screen
        window.backgroundColor = .black
        installRootView(on: window)
        window.isHidden = false
        externalWindow = window
        Log.hdmi.info("legacyAttach window installed frame=\(String(describing: window.frame), privacy: .public) screen==external=\(window.screen !== UIScreen.main, privacy: .public)")
    }

    // MARK: - Shared

    private func installRootView(on window: UIWindow) {
        let host = UIHostingController(rootView: CleanOutputView(sessionProvider: { [weak self] in
            self?.captureSession
        }))
        host.view.backgroundColor = .black
        window.rootViewController = host
    }

    private func tearDownWindow(reason: String) {
        externalWindow?.isHidden = true
        externalWindow = nil
        Log.hdmi.info("tore down external window (reason=\(reason, privacy: .public))")
    }

    private func refreshExternalWindow() {
        externalWindow?.rootViewController?.view.setNeedsLayout()
    }

    private func logConnectedScreens(context: String) {
        let screens = UIScreen.screens
        Log.hdmi.info("[\(context, privacy: .public)] UIScreen.screens.count=\(screens.count, privacy: .public)")
        for (i, s) in screens.enumerated() {
            let isMain = (s === UIScreen.main)
            Log.hdmi.info("  screen[\(i, privacy: .public)] bounds=\(String(describing: s.bounds), privacy: .public) main=\(isMain, privacy: .public)")
        }
        let sceneCount = UIApplication.shared.connectedScenes.count
        Log.hdmi.info("[\(context, privacy: .public)] connectedScenes.count=\(sceneCount, privacy: .public)")
        for scene in UIApplication.shared.connectedScenes {
            Log.hdmi.info("  scene role=\(String(describing: scene.session.role), privacy: .public) state=\(String(describing: scene.activationState), privacy: .public)")
        }
    }
}
