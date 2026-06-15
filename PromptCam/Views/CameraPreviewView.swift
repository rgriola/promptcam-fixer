// May 29, 2026 - 11:23pm - GitHub Copilot
import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var onTap: ((CGPoint, CGPoint) -> Void)?
    var onLongPress: ((CGPoint, CGPoint) -> Void)?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = videoGravity
        view.previewLayer.session = session

        let longPressRecognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress))
        longPressRecognizer.minimumPressDuration = 0.55
        longPressRecognizer.allowableMovement = 12

        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tapRecognizer.require(toFail: longPressRecognizer)

        view.addGestureRecognizer(longPressRecognizer)
        view.addGestureRecognizer(tapRecognizer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.parent = self
        uiView.previewLayer.session = session
        uiView.previewLayer.videoGravity = videoGravity
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: CameraPreviewView

        init(parent: CameraPreviewView) {
            self.parent = parent
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let view = sender.view as? PreviewView else { return }
            let viewPoint = sender.location(in: view)
            let devicePoint = view.previewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
            parent.onTap?(devicePoint, viewPoint)
        }

        @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
            guard sender.state == .began else { return }
            guard let view = sender.view as? PreviewView else { return }

            let viewPoint = sender.location(in: view)
            let devicePoint = view.previewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
            parent.onLongPress?(devicePoint, viewPoint)
        }
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Layer is not AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}
