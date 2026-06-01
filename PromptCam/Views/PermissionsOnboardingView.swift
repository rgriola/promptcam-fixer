import AVFoundation
import Photos
import SwiftUI

/// Full-screen onboarding view that requests camera, microphone,
/// and photo library permissions before allowing access to the camera.
struct PermissionsOnboardingView: View {
    /// Callback fired when the user taps Continue to proceed to camera.
    let onContinue: () -> Void

    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var photoStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
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
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)

            // App icon and title
            VStack(spacing: 12) {
                Image(systemName: "video.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.blue)

                Text("PromptCam")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("To get started, PromptCam needs access to\nyour camera, microphone, and photo library.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer().frame(height: 40)

            // Permission rows
            VStack(spacing: 16) {
                PermissionRow(
                    icon: "camera.fill",
                    iconColor: .blue,
                    title: "Camera",
                    description: "Record videos with your camera",
                    status: avStatusLabel(cameraStatus),
                    statusColor: avStatusColor(cameraStatus),
                    showSettingsLink: cameraStatus == .denied || cameraStatus == .restricted
                )

                PermissionRow(
                    icon: "mic.fill",
                    iconColor: .orange,
                    title: "Microphone",
                    description: "Capture audio with your recordings",
                    status: avStatusLabel(micStatus),
                    statusColor: avStatusColor(micStatus),
                    showSettingsLink: micStatus == .denied || micStatus == .restricted
                )

                PermissionRow(
                    icon: "photo.on.rectangle",
                    iconColor: .green,
                    title: "Photo Library",
                    description: "Save and review your recordings",
                    status: phStatusLabel(photoStatus),
                    statusColor: phStatusColor(photoStatus),
                    showSettingsLink: photoStatus == .denied || photoStatus == .restricted
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                if hasUndetermined {
                    Button {
                        requestAllPermissions()
                    } label: {
                        HStack(spacing: 8) {
                            if isRequesting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Grant Permissions")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isRequesting)
                }

                Button {
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(canContinue ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundStyle(canContinue ? .white : .gray)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canContinue)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
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
            refreshStatuses()
            isRequesting = false
        }
    }

    private func refreshStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Status Labels

    private func avStatusLabel(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Granted"
        case .notDetermined: return "Not Set"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    private func avStatusColor(_ status: AVAuthorizationStatus) -> Color {
        switch status {
        case .authorized: return .green
        case .notDetermined: return .orange
        case .denied, .restricted: return .red
        @unknown default: return .gray
        }
    }

    private func phStatusLabel(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized, .limited: return "Granted"
        case .notDetermined: return "Not Set"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    private func phStatusColor(_ status: PHAuthorizationStatus) -> Color {
        switch status {
        case .authorized, .limited: return .green
        case .notDetermined: return .orange
        case .denied, .restricted: return .red
        @unknown default: return .gray
        }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
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
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            // Title + description
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status badge
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(status)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                if showSettingsLink {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Settings")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("Onboarding") {
    PermissionsOnboardingView(onContinue: {})
}
