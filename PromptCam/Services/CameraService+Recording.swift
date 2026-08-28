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
        performSave(outputFileURL)
    }

    /// Performs the actual save via the injected `PhotoLibrarySaver` and
    /// dispatches success/failure callbacks. Split from the permission-guarded
    /// entry point so unit tests can bypass PhotoKit authorization.
    func performSave(_ outputFileURL: URL) {
        let saver = self.photoSaver
        Task { [weak self] in
            do {
                try await saver.saveVideo(at: outputFileURL)
                await MainActor.run { [weak self] in
                    self?.onRecordingSavedToLibrary?()
                }
            } catch {
                self?.publishError(.photoLibrarySaveFailed(error.localizedDescription))
            }
            try? FileManager.default.removeItem(at: outputFileURL)
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    // AVFoundation calls these on an arbitrary thread — do not assume main actor.
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
