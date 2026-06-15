// PromptCam — Settings Sheet
// Extracted from CameraView.swift (refactor June 1, 2026)
// Uses shared PermissionStatusDisplay helpers and PermissionStatusRow component.
import AVFoundation
import Photos
import SwiftUI

// MARK: - Settings Sheet

/// Modal sheet showing app info and live permission statuses.
/// Permission statuses auto-refresh when the sheet appears and when
/// returning from iOS Settings via `scenePhase` observation.
struct CameraSettingsSheet: View {
    /// Callback to dismiss settings sheet.
    let onClose: () -> Void

    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var photoStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    @Environment(\.scenePhase) private var scenePhase

    /// Settings view showing app info and live permission statuses.
    var body: some View {
        NavigationStack {
            List {

                Section("About") {
                    SettingStatusRow(title: "Version", value: appVersion)
                    SettingStatusRow(title: "Device", value: deviceInfo)
                }
                .listRowBackground(Theme.black.opacity(0.1))
                .foregroundStyle(Theme.white)

                Section("Camera Modes") {
                    ForEach(availableCameraModes, id: \.self) { mode in
                        HStack(spacing: Theme.space8) {
                            Image(systemName: iconForMode(mode))
                                .foregroundStyle(Theme.purple)
                                .frame(width: 20)
                            Text(mode)
                                .font(Theme.font16Regular)
                                .foregroundStyle(Theme.white)
                        }
                    }
                }
                .listRowBackground(Theme.black.opacity(0.1))
                .foregroundStyle(Theme.white)
                
                Section("Permissions") {

                    PermissionStatusRow(
                        icon: "camera.fill",
                        iconColor: .blue,
                        title: "Camera",
                        status: PermissionStatusDisplay.label(for: cameraStatus),
                        statusColor: PermissionStatusDisplay.color(for: cameraStatus),
                        isDenied: cameraStatus == .denied || cameraStatus == .restricted
                    )

                    PermissionStatusRow(
                        icon: "mic.fill",
                        iconColor: .orange,
                        title: "Microphone",
                        status: PermissionStatusDisplay.label(for: micStatus),
                        statusColor: PermissionStatusDisplay.color(for: micStatus),
                        isDenied: micStatus == .denied || micStatus == .restricted
                    )

                    PermissionStatusRow(
                        icon: "photo.on.rectangle",
                        iconColor: .green,
                        title: "Photo Library",
                        status: PermissionStatusDisplay.label(for: photoStatus),
                        statusColor: PermissionStatusDisplay.color(for: photoStatus),
                        isDenied: photoStatus == .denied || photoStatus == .restricted
                    )
                }
                .listRowBackground(Theme.black.opacity(0.1))
                .foregroundStyle(Theme.white)
                
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseToolbarButton { onClose() }
                }
            }
            .onAppear { refreshStatuses() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { refreshStatuses() }
            }
        }
        .presentationBackground(Theme.bgGrad)
    }

    // MARK: - Computed Properties

    /// Human-readable app version/build string shown in settings.
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// Device model + OS version, e.g. "iPhone 17 Pro · iOS 26.0"
    private var deviceInfo: String {
        let os = UIDevice.current
        return "\(DeviceModel.marketingName) · \(os.systemName) \(os.systemVersion)"
    }

    /// Lists camera modes available on this device (e.g. Standard, Cinematic, Slo-mo).
    private var availableCameraModes: [String] {
        var modes: [String] = []

        // Check back camera for standard + cinematic + slo-mo
        if let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            modes.append("Standard")

            // Check for high frame rate (slo-mo) support
            let hasSloMo = backCamera.formats.contains { format in
                format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 120 }
            }
            if hasSloMo { modes.append("Slo-mo") }
        }

        // Check for cinematic / depth
        if AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) != nil
            || AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) != nil {
            modes.append("Cinematic")
        }

        // Front camera
        if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil {
            modes.append("Front Camera")
        }

        return modes
    }

    /// SF Symbol icon for each camera mode.
    private func iconForMode(_ mode: String) -> String {
        switch mode {
        case "Standard":    return "video.fill"
        case "Cinematic":   return "circle.dotted.and.circle"
        case "Slo-mo":      return "slowmo"
        case "Front Camera": return "person.fill"
        default:            return "camera.fill"
        }
    }

    private func refreshStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
}
