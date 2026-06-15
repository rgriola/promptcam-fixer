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
                } // This needs work. 
                .listRowBackground(Theme.black.opacity(0.1))
                .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(Theme.glassBorder, lineWidth: 1)
                    .padding(.horizontal, Theme.space16)
                )
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

    /// Human-readable app version/build string shown in settings.
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func refreshStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
}
