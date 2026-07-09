// PromptCam — Permissions Onboarding
// Refactored June 1, 2026 — uses shared PermissionStatusDisplay helpers and Theme tokens.
import AVFoundation
import CoreLocation
import Photos
import Speech
import SwiftUI

/// Full-screen onboarding view that requests camera, microphone,
/// and photo library permissions before allowing access to the camera.
/// Shown only on first launch; subsequent launches skip to the camera.
struct PermissionsOnboardingView: View {
    /// Callback fired when the user taps Continue to proceed to camera.
    let onContinue: () -> Void

    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(
        for: .video)
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(
        for: .audio)
    @State private var photoStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(
        for: .readWrite)
    @State private var locationStatus: CLAuthorizationStatus = CLLocationManager()
        .authorizationStatus
    @State private var speechStatus: SFSpeechRecognizerAuthorizationStatus =
        SFSpeechRecognizer.authorizationStatus()
    @State private var isRequesting = false
    @State private var hasTrackedGateShown = false

    @Environment(\.scenePhase) private var scenePhase

    private let permissionService = PermissionService()

    /// Centralized gate reducer derived from current permission statuses.
    private var gateState: RequiredAccessGateState {
        RequiredAccessGateState(
            snapshot: PermissionPolicySnapshot(
                camera: cameraStatus,
                microphone: micStatus,
                photoLibrary: photoStatus,
                location: locationStatus,
                speechToText: speechStatus
            ))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)

            // App icon and title
            VStack(spacing: Theme.space12) {
                Image(systemName: "video.fill")
                    .font(Theme.display44)
                    .foregroundStyle(Theme.white)

                Text(PermissionCopyCatalog.onboardingTitle)
                    .font(Theme.font28Bold)
                    .foregroundStyle(Theme.white)

                Text(PermissionCopyCatalog.onboardingRequiredSummary)
                    .font(Theme.font16Regular)
                    .foregroundStyle(Theme.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.space32)

                Text(PermissionCopyCatalog.onboardingOptionalSummary)
                    .font(Theme.font12Regular)
                    .foregroundStyle(Theme.secondaryText)
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
                    permission: .camera,
                    description: PermissionCopyCatalog.description(for: .camera),
                    status: PermissionStatusDisplay.label(for: cameraStatus),
                    statusColor: PermissionStatusDisplay.color(for: cameraStatus),
                    showSettingsLink: cameraStatus == .denied || cameraStatus == .restricted,
                    snapshot: gateState.snapshot
                )

                OnboardingPermissionRow(
                    icon: "mic.fill",
                    iconColor: .orange,
                    title: "Microphone",
                    permission: .microphone,
                    description: PermissionCopyCatalog.description(for: .microphone),
                    status: PermissionStatusDisplay.label(for: micStatus),
                    statusColor: PermissionStatusDisplay.color(for: micStatus),
                    showSettingsLink: micStatus == .denied || micStatus == .restricted,
                    snapshot: gateState.snapshot
                )

                OnboardingPermissionRow(
                    icon: "photo.on.rectangle",
                    iconColor: .green,
                    title: "Photo Library",
                    permission: .photoLibrary,
                    description: PermissionCopyCatalog.description(for: .photoLibrary),
                    status: PermissionStatusDisplay.label(for: photoStatus),
                    statusColor: PermissionStatusDisplay.color(for: photoStatus),
                    showSettingsLink: photoStatus == .denied || photoStatus == .restricted,
                    snapshot: gateState.snapshot
                )

                OnboardingPermissionRow(
                    icon: "location.fill",
                    iconColor: .teal,
                    title: "Location",
                    permission: .location,
                    description: PermissionCopyCatalog.description(for: .location),
                    status: PermissionStatusDisplay.label(for: locationStatus),
                    statusColor: PermissionStatusDisplay.color(for: locationStatus),
                    showSettingsLink: locationStatus == .denied || locationStatus == .restricted,
                    snapshot: gateState.snapshot
                )

                OnboardingPermissionRow(
                    icon: "waveform",
                    iconColor: .purple,
                    title: "Speech to Text",
                    permission: .speechToText,
                    description: PermissionCopyCatalog.description(for: .speechToText),
                    status: PermissionStatusDisplay.label(for: speechStatus),
                    statusColor: PermissionStatusDisplay.color(for: speechStatus),
                    showSettingsLink: speechStatus == .denied || speechStatus == .restricted,
                    snapshot: gateState.snapshot
                )
            }
            .padding(.horizontal, Theme.space24)

            Spacer()

            // Action buttons
            VStack(spacing: Theme.space12) {
                if gateState.hasBlockedRequiredPermission {
                    Text(PermissionCopyCatalog.onboardingBlockedRequiredMessage)
                        .font(Theme.font12Regular)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.space24)
                }

                if gateState.hasUndeterminedPermission {
                    Button {
                        PermissionAnalyticsService.trackGrantAccessTapped(
                            snapshot: gateState.snapshot)
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
                        .background(gateState.canContinue ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundStyle(gateState.canContinue ? .white : .gray)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!gateState.canContinue)
            }
            .padding(.horizontal, Theme.space24)
            .padding(.bottom, 40)
        }
        .background(Theme.bgGrad)
        .onAppear {
            trackGateShownIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshStatuses()
                trackBlockedGateReentryIfNeeded()
            }
        }
        .onChange(of: gateState.canContinue) { _, _ in
            trackGateShownIfNeeded()
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
            if speechStatus == .notDetermined {
                _ = await permissionService.requestSpeechToTextAccess()
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
        speechStatus = SFSpeechRecognizer.authorizationStatus()
        PermissionAnalyticsService.trackSpeechPermissionStatusObserved(
            status: speechStatus,
            sourceScreen: "onboarding"
        )
    }

    private func trackGateShownIfNeeded() {
        guard !gateState.canContinue, !hasTrackedGateShown else { return }
        hasTrackedGateShown = true
        PermissionAnalyticsService.trackGateShown(snapshot: gateState.snapshot)
    }

    /// Re-fires `permission_gate_shown` when the app returns from background
    /// while the gate is still blocked. This is what allows the analytics
    /// service to detect real blocked loops within a single session.
    private func trackBlockedGateReentryIfNeeded() {
        guard !gateState.canContinue else { return }
        PermissionAnalyticsService.trackGateShown(snapshot: gateState.snapshot)
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
    let permission: PermissionAnalyticsPermission
    let description: String
    let status: String
    let statusColor: Color
    let showSettingsLink: Bool
    var snapshot: PermissionPolicySnapshot? = nil

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
                    OpenSettingsButton(
                        permission: permission,
                        sourceSurface: .gate,
                        snapshot: snapshot
                    )
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
