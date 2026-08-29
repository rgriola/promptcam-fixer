// CameraService+Recording.swift
// PromptCam
//
// Extracted from CameraService.swift — recording lifecycle and photo library save.

import Accelerate
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

            self.logAudioBindingSnapshot(context: "startRecording")

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
        let audioConnections = connections.filter { connection in
            connection.inputPorts.contains { $0.mediaType == .audio }
        }
        Log.audio.notice(
            "\(Log.ts(), privacy: .public) [record] STARTED connections=\(connections.count, privacy: .public) audioConnections=\(audioConnections.count, privacy: .public)"
        )
        if audioConnections.isEmpty {
            Log.audio.error("\(Log.ts(), privacy: .public) [record] no audio connection on the file output — this file cannot contain audio")
        }
        publishRecordingState(true)
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        publishRecordingState(false)
        analyzeRecordedAudio(url: outputFileURL)
        // Dispatch to sessionQueue for serialized state access.
        sessionQueue.async { [self] in
            logAudioBindingSnapshot(context: "stopRecording")
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

// MARK: - Audio Diagnostics

extension CameraService {

    /// Logs what the capture session is bound to alongside what `AVAudioSession`
    /// is actually routing.
    ///
    /// iOS exposes a *single* audio `AVCaptureDevice` that proxies whatever the
    /// audio session route is; its `uniqueID` is always `built-in_audio:0` and
    /// never equals an `AVAudioSessionPortDescription.uid`. Only `localizedName`
    /// tracks the route, so that is what the verdict compares.
    nonisolated func logAudioBindingSnapshot(context: String) {
        let session = AVAudioSession.sharedInstance()
        let routeInput = session.currentRoute.inputs.first
        let routeUID = routeInput?.uid ?? "none"
        let routeName = routeInput?.portName ?? "none"
        let routeType = routeInput?.portType.rawValue ?? "none"
        let preferredName = session.preferredInput?.portName ?? "(system default)"

        let boundUID = audioDevice?.uniqueID ?? "none"
        let boundName = audioDevice?.localizedName ?? "none"

        let connectionState: String
        if let connection = movieFileOutput.connection(with: .audio) {
            connectionState = "enabled=\(connection.isEnabled)/active=\(connection.isActive)"
        } else {
            connectionState = "ABSENT"
        }

        let followsRoute = routeInput.map { $0.portName == boundName } ?? false

        Log.audio.notice(
            "\(Log.ts(), privacy: .public) [\(context, privacy: .public)] route='\(routeName, privacy: .public)' type=\(routeType, privacy: .public) uid=\(routeUID, privacy: .public) preferred='\(preferredName, privacy: .public)' | captureDevice='\(boundName, privacy: .public)' proxyUID=\(boundUID, privacy: .public) attached=\(self.audioInput != nil, privacy: .public) conn=\(connectionState, privacy: .public) | FOLLOWS_ROUTE=\(followsRoute ? "YES" : "NO", privacy: .public)"
        )

        guard !followsRoute else { return }

        Log.audio.error(
            "\(Log.ts(), privacy: .public) [\(context, privacy: .public)] capture device '\(boundName, privacy: .public)' did not follow route '\(routeName, privacy: .public)' — recording may capture the wrong mic"
        )
        let candidates = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
        for device in candidates {
            Log.audio.error(
                "\(Log.ts(), privacy: .public) [\(context, privacy: .public)] candidate '\(device.localizedName, privacy: .public)' uniqueID=\(device.uniqueID, privacy: .public)"
            )
        }
    }

    /// Decodes the finished file's audio track and reports its measured peak, so
    /// a silent-but-present track is distinguishable from a missing one.
    ///
    /// Runs detached so the save path's timing is unchanged; the reader keeps its
    /// own handle, so the temp file being deleted mid-read is tolerable.
    nonisolated func analyzeRecordedAudio(url: URL) {
        Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            do {
                guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                    Log.audio.error("\(Log.ts(), privacy: .public) [file] \(url.lastPathComponent, privacy: .public) has NO audio track")
                    return
                }
                let duration = try await track.load(.timeRange).duration.seconds
                let dataRate = try await track.load(.estimatedDataRate)
                let peak = try Self.peakAmplitude(of: track, in: asset)
                let peakDb = peak > 0 ? 20 * log10(peak) : -Float.infinity

                Log.audio.notice(
                    "\(Log.ts(), privacy: .public) [file] \(url.lastPathComponent, privacy: .public) audioTrack duration=\(duration, format: .fixed(precision: 2), privacy: .public)s bitrate=\(Int(dataRate), privacy: .public)bps peak=\(peakDb, format: .fixed(precision: 1), privacy: .public) dBFS"
                )
                if peakDb < -60 {
                    Log.audio.error(
                        "\(Log.ts(), privacy: .public) [file] RECORDED AUDIO IS SILENT (peak \(peakDb, format: .fixed(precision: 1), privacy: .public) dBFS) — compare against the [meter] levels logged during this take"
                    )
                }
            } catch {
                Log.audio.error("\(Log.ts(), privacy: .public) [file] audio analysis failed – \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func peakAmplitude(of track: AVAssetTrack, in asset: AVAsset) throws -> Float {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        guard reader.canAdd(output) else { return 0 }
        reader.add(output)
        reader.startReading()

        var peak: Float = 0
        while let sample = output.copyNextSampleBuffer() {
            defer { CMSampleBufferInvalidate(sample) }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &pointer
            ) == kCMBlockBufferNoErr, let pointer else { continue }

            let count = length / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            pointer.withMemoryRebound(to: Float.self, capacity: count) { floats in
                var localPeak: Float = 0
                vDSP_maxmgv(floats, 1, &localPeak, vDSP_Length(count))
                peak = max(peak, localPeak)
            }
        }
        return peak
    }
}
