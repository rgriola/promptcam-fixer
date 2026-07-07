// PromptCam — Permissions Onboarding
// Refactored June 1, 2026 — uses shared PermissionStatusDisplay helpers and Theme tokens.
import AVFoundation
import CoreLocation
import Photos
import SwiftUI

/// Full-screen onboarding view that requests camera, microphone,
/// and photo library permissions before allowing access to the camera.
/// Shown only on first launch; subsequent launches skip to the camera.
struct PermissionsOnboardingView: View {
    /// Callback fired when the user taps Continue to proceed to camera.
    let onContinue: () -> Void

    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var photoStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var locationStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus
    @State private var isRequesting = false

    @Environment(\.scenePhase) private var scenePhase

    private let permissionService = PermissionService()

    /// Continue is enabled once camera + mic are both authorized.
    private var canContinue: Bool {
        cameraStatus == .authorized && micStatus == .authorized
    }

    /// True when at least one permission is still in not-determined state.
    private var hasUndetermined: Bool {
        cameraStatus == .notDetermined
            || micStatus == .notDetermined
            || photoStatus == .notDetermined
            || locationStatus == .notDetermined
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)

            // App icon and title
            VStack(spacing: Theme.space12) {
                Image(systemName: "video.fill")
                    .font(Theme.display44)
                    .foregroundStyle(Theme.white)

                Text("A1-Teleprompter")
                    .font(Theme.font28Bold)
                    .foregroundStyle(Theme.white)

                Text("Required access to camera, mic, photo library & location.")
                    .font(Theme.font16Regular)
                    .foregroundStyle(Theme.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.space32)
            }

            Spacer().frame(height: 40)

            // Permission rows
            VStack(spacing: Theme.space16) {
                OnboardingPermissionRow(
                    icon: "camera.fill",
                    iconColor: .blue,
                    title: "Camera",
                    description: "Need Video.",
                    status: PermissionStatusDisplay.label(for: cameraStatus),
                    statusColor: PermissionStatusDisplay.color(for: cameraStatus),
                    showSettingsLink: cameraStatus == .denied || cameraStatus == .restricted
                )

                OnboardingPermissionRow(
                    icon: "mic.fill",
                    iconColor: .orange,
                    title: "Microphone",
                    description: "No Audio, No Bueno",
                    status: PermissionStatusDisplay.label(for: micStatus),
                    statusColor: PermissionStatusDisplay.color(for: micStatus),
                    showSettingsLink: micStatus == .denied || micStatus == .restricted
                )

                OnboardingPermissionRow(
                    icon: "photo.on.rectangle",
                    iconColor: .green,
                    title: "Photo Library",
                    description: "Saves your recording",
                    status: PermissionStatusDisplay.label(for: photoStatus),
                    statusColor: PermissionStatusDisplay.color(for: photoStatus),
                    showSettingsLink: photoStatus == .denied || photoStatus == .restricted
                )

                OnboardingPermissionRow(
                    icon: "location.fill",
                    iconColor: .teal,
                    title: "Location",
                    description: "GPS tags your video",
                    status: PermissionStatusDisplay.label(for: locationStatus),
                    statusColor: PermissionStatusDisplay.color(for: locationStatus),
                    showSettingsLink: locationStatus == .denied || locationStatus == .restricted
                )
            }
            .padding(.horizontal, Theme.space24)

            Spacer()

            // Action buttons
            VStack(spacing: Theme.space12) {
                if hasUndetermined {
                    Button {
                        requestAllPermissions()
                    } label: {
                        HStack(spacing: Theme.space8) {
                            if isRequesting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Grant Permissions")
                                .font(Theme.font16Semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.blue)
                        .foregroundStyle(Theme.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isRequesting)
                }

                Button {
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(Theme.font16Semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(canContinue ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundStyle(canContinue ? .white : .gray)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canContinue)
            }
            .padding(.horizontal, Theme.space24)
            .padding(.bottom, 40)
        }
        .background(Theme.bgGrad)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshStatuses()
            }
        }
    }

    // MARK: - Actions

    private func requestAllPermissions() {
        isRequesting = true
        Task {
            if cameraStatus == .notDetermined {
                _ = await permissionService.requestCameraAccess()
            }
            if micStatus == .notDetermined {
                _ = await permissionService.requestMicrophoneAccess()
            }
            if photoStatus == .notDetermined {
                _ = await permissionService.requestPhotoLibraryAccess()
            }
            if locationStatus == .notDetermined {
                // CoreLocation has no async API — fires the dialog and returns.
                // Status is refreshed when the scene becomes active again.
                permissionService.requestLocationAccess()
            }
            refreshStatuses()
            isRequesting = false
        }
    }

    private func refreshStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        locationStatus = CLLocationManager().authorizationStatus
    }
}

// MARK: - Onboarding Permission Row

/// Card-style permission row used only on the onboarding screen.
/// Differs from `PermissionStatusRow` (settings) in visual treatment:
/// rounded card with icon circle, description text, and background fill.
private struct OnboardingPermissionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let status: String
    let statusColor: Color
    let showSettingsLink: Bool

    var body: some View {
        HStack(spacing: 14) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(Theme.font16Semibold)
                    .foregroundStyle(iconColor)
            }

            // Title + description
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.font16Semibold)
                    .foregroundStyle(Theme.white)
                Text(description)
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.white)
            }

            Spacer()

            // Status badge
            VStack(spacing: Theme.space4) {
                HStack(spacing: Theme.space4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(status)
                        .font(Theme.font12Medium)
                        .foregroundStyle(statusColor)
                }

                if showSettingsLink {
                    OpenSettingsButton()
                }
            }
        }
        .padding(Theme.space16)
        .cardBackground()
    }
}

#Preview("Onboarding") {
    PermissionsOnboardingView(onContinue: {})
}
