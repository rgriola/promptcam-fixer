// CameraService+Recording.swift
// PromptCam
//
// Extracted from CameraService.swift — recording lifecycle and photo library save.

import AVFoundation
import Photos

// MARK: - Recording

extension CameraService {

    func startRecording() {
        sessionQueue.async {
            guard !self.movieFileOutput.isRecording else { return }
            guard self.isSessionConfigured else {
                self.publishError(.sessionNotReady)
                return
            }
            guard self.session.isRunning else {
                self.publishError(.sessionNotReady)
                return
            }
            guard self.movieFileOutput.connection(with: .video) != nil else {
                self.publishError(.sessionNotReady)
                return
            }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")

            self.currentOutputURL = outputURL
            self.movieFileOutput.startRecording(to: outputURL, recordingDelegate: self)
        }
    }

    func stopRecording() {
        sessionQueue.async {
            guard self.movieFileOutput.isRecording else { return }
            self.movieFileOutput.stopRecording()
        }
    }

    func saveRecordingToPhotoLibrary(_ outputFileURL: URL) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            self.publishError(.photoLibraryPermissionDenied)
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
        } completionHandler: { success, error in
            if let error {
                self.publishError(.photoLibrarySaveFailed(error.localizedDescription))
            } else if !success {
                self.publishError(.photoLibrarySaveFailed("Video save operation did not complete."))
            }

            try? FileManager.default.removeItem(at: outputFileURL)
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        publishRecordingState(true)
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        publishRecordingState(false)
        // Dispatch to sessionQueue for serialized state access.
        sessionQueue.async { [self] in
            if let error {
                publishError(CameraError.recordingFailed(error.localizedDescription))
                // Clean up the temp file that would otherwise be leaked.
                try? FileManager.default.removeItem(at: outputFileURL)
                return
            }
            saveRecordingToPhotoLibrary(outputFileURL)
        }
    }
}
