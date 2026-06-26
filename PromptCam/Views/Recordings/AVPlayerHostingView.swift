// PromptCam — AVPlayer Host
// Wraps AVPlayerViewController in a UIViewControllerRepresentable with
// showsPlaybackControls = false so we can build our own controls without
// the native AirPlay / PiP / Done buttons appearing on top of our UI.
import AVKit
import SwiftUI

/// A thin SwiftUI wrapper around `AVPlayerViewController`.
///
/// Setting `showsPlaybackControls = false` removes ALL native chrome —
/// no AirPlay, no PiP, no Done button — giving us a clean video canvas.
struct AVPlayerHostingView: UIViewControllerRepresentable {

    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false          // ← removes all native chrome
        vc.allowsPictureInPicturePlayback = false // ← no PiP
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Player reference stays stable; no updates needed.
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
