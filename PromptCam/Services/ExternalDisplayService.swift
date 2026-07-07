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
    private var didBindSession = false
    private var sessionRunningObserver: NSObjectProtocol?

    /// Toggle to true to overlay a yellow "HDMI CONNECTED" banner while debugging.
    static var showDiagnosticOverlay = false

    init(sessionProvider: @escaping () -> AVCaptureSession?) {
        self.sessionProvider = sessionProvider
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        // NotificationCenter automatically releases observers when they dealloc
        // for the block-based API; explicit removal here would need main-actor
        // isolation. Safe to skip — view controllers dealloc on the main queue.
    }

    override func loadView() {
        let root = UIView()
        root.backgroundColor = .black
        previewView.backgroundColor = .black
        previewView.previewLayer.videoGravity = .resizeAspectFill
        previewView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: root.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()

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

        // Assign the session exactly ONCE, and only after it's running.
        // Repeated assignments (via polling) or an assignment while the session
        // is stopped can cause the shared session to reshuffle connections,
        // which knocks out the phone's own AVCaptureVideoPreviewLayer.
        bindSessionWhenRunning()
    }

    /// Binds the capture session to our preview layer exactly once, gated on
    /// the session being in the `isRunning` state. If already running, binds
    /// synchronously; otherwise subscribes to `didStartRunningNotification`.
    private func bindSessionWhenRunning() {
        guard !didBindSession else { return }
        guard let session = sessionProvider() else {
            Log.hdmi.info("bindSessionWhenRunning: no session yet — will retry on didStartRunning")
            observeSessionRunning(nil)
            return
        }
        if session.isRunning {
            performBind(session: session, reason: "immediate")
        } else {
            Log.hdmi.info("bindSessionWhenRunning: session not running yet — waiting for didStartRunning")
            observeSessionRunning(session)
        }
    }

    private func observeSessionRunning(_ session: AVCaptureSession?) {
        if let observer = sessionRunningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        sessionRunningObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.didStartRunningNotification,
            object: session, // nil accepts any session (used if not known yet)
            queue: .main
        ) { [weak self] _ in
            // queue:.main guarantees delivery on the main thread; jump onto the
            // main actor explicitly to satisfy Swift 6 isolation without
            // sending non-Sendable AVCaptureSession across a Task boundary.
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let s = self.sessionProvider() else { return }
                self.performBind(session: s, reason: "didStartRunning")
            }
        }
    }

    private func performBind(session: AVCaptureSession, reason: String) {
        guard !didBindSession else { return }
        didBindSession = true
        previewView.previewLayer.session = session
        if let observer = sessionRunningObserver {
            NotificationCenter.default.removeObserver(observer)
            sessionRunningObserver = nil
        }
        let conn = previewView.previewLayer.connection
        Log.hdmi.info("performBind[\(reason, privacy: .public)] session=set running=\(session.isRunning, privacy: .public) connection=\(conn != nil ? "set" : "nil", privacy: .public) enabled=\(conn?.isEnabled == true, privacy: .public) active=\(conn?.isActive == true, privacy: .public) viewFrame=\(String(describing: self.view.frame), privacy: .public)")
    }
}
