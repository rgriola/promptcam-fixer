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
        Log.hdmi.info("attach(to:) scene role=\(String(describing: windowScene.session.role), privacy: .public) activation=\(String(describing: windowScene.activationState), privacy: .public)")
        guard attachedScene !== windowScene else {
            Log.hdmi.debug("attach(to:) same scene already attached — ignoring")
            return
        }
        attachedScene = windowScene

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        installRootView(on: window)
        // Non-interactive external windows still need to be visible; makeKeyAndVisible
        // is safe here (external scenes ignore the "key" part but honor visibility).
        window.isHidden = false
        externalWindow = window
        Log.hdmi.info("attach(to:) window installed frame=\(String(describing: window.frame), privacy: .public) hidden=\(window.isHidden, privacy: .public) rootVC=\(String(describing: type(of: window.rootViewController)), privacy: .public)")
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

    /// Builds the external window's rootViewController in pure UIKit.
    ///
    /// SwiftUI + `UIHostingController` on a non-key external `UIWindow` has been
    /// observed to render nothing on the physical HDMI even when the window is
    /// fully installed and laid out. A plain `UIViewController` hosting an
    /// `AVCaptureVideoPreviewLayer` directly avoids the SwiftUI rendering path.
    private func installRootView(on window: UIWindow) {
        let vc = ExternalDisplayHostViewController(sessionProvider: { [weak self] in
            self?.captureSession
        })
        vc.view.frame = window.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.rootViewController = vc
        window.layoutIfNeeded()
        Log.hdmi.info("installRootView UIKit rootVC frame=\(String(describing: vc.view.frame), privacy: .public)")
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

// MARK: - UIKit-only external display view controller

/// Pure UIKit host for the HDMI window. Owns a preview view that mirrors the
/// running capture session and a bright diagnostic label proving the window
/// is reaching the physical display.
@MainActor
final class ExternalDisplayHostViewController: UIViewController {
    private let sessionProvider: () -> AVCaptureSession?
    private let previewView = PreviewView()
    private let diagnosticLabel = UILabel()

    /// Toggle to false once HDMI output is verified.
    static var showDiagnosticOverlay = true

    init(sessionProvider: @escaping () -> AVCaptureSession?) {
        self.sessionProvider = sessionProvider
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        // Use PreviewView directly as the controller's view — no extra containers.
        previewView.backgroundColor = .black
        previewView.previewLayer.videoGravity = .resizeAspectFill
        view = previewView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        previewView.previewLayer.session = sessionProvider()
        Log.hdmi.info("ExternalDisplayHostVC viewDidLoad session=\(self.previewView.previewLayer.session != nil ? "set" : "nil", privacy: .public) running=\(self.previewView.previewLayer.session?.isRunning == true, privacy: .public)")

        if Self.showDiagnosticOverlay {
            diagnosticLabel.text = "HDMI CONNECTED"
            diagnosticLabel.font = .systemFont(ofSize: 120, weight: .black)
            diagnosticLabel.textColor = .yellow
            diagnosticLabel.textAlignment = .center
            diagnosticLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(diagnosticLabel)
            NSLayoutConstraint.activate([
                diagnosticLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                diagnosticLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 40)
            ])
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Ensure preview always has the latest session reference.
        if previewView.previewLayer.session !== sessionProvider() {
            previewView.previewLayer.session = sessionProvider()
        }
        Log.hdmi.info("ExternalDisplayHostVC viewWillAppear session=\(self.previewView.previewLayer.session != nil ? "set" : "nil", privacy: .public) running=\(self.previewView.previewLayer.session?.isRunning == true, privacy: .public) frame=\(String(describing: self.view.frame), privacy: .public)")
    }
}
