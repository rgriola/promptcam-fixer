// PromptCam — Shared Permission Status Display Helpers
// Consolidated from CameraSettingsSheet + PermissionsOnboardingView (refactor June 1, 2026)
import AVFoundation
import CoreLocation
import Photos
import Speech
import SwiftUI

// MARK: - Permission Status Display

/// Shared label and color mappers for AVFoundation, Photos, and CoreLocation
/// authorization statuses. Used by both the settings sheet and the onboarding
/// screen to avoid duplication.
enum PermissionStatusDisplay {

    // MARK: - AVFoundation (Camera / Microphone)

    /// Human-readable label for camera or microphone authorization status.
    static func label(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Granted"
        case .notDetermined: return "Not Set"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    /// Semantic color for camera or microphone authorization status.
    static func color(for status: AVAuthorizationStatus) -> Color {
        switch status {
        case .authorized: return .green
        case .notDetermined: return .orange
        case .denied, .restricted: return .red
        @unknown default: return .gray
        }
    }

    // MARK: - Photos Library

    /// Human-readable label for photo library authorization status.
    static func label(for status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized, .limited: return "Granted"
        case .notDetermined: return "Not Set"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    /// Semantic color for photo library authorization status.
    static func color(for status: PHAuthorizationStatus) -> Color {
        switch status {
        case .authorized, .limited: return .green
        case .notDetermined: return .orange
        case .denied, .restricted: return .red
        @unknown default: return .gray
        }
    }

    // MARK: - Location

    /// Human-readable label for location authorization status.
    static func label(for status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: return "Granted"
        case .notDetermined: return "Not Set"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    /// Semantic color for location authorization status.
    static func color(for status: CLAuthorizationStatus) -> Color {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: return .green
        case .notDetermined: return .orange
        case .denied, .restricted: return .red
        @unknown default: return .gray
        }
    }

    // MARK: - Speech Recognition (Speech-to-Text)

    /// Human-readable label for speech recognition authorization status.
    static func label(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Granted"
        case .notDetermined: return "Not Set"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    /// Semantic color for speech recognition authorization status.
    static func color(for status: SFSpeechRecognizerAuthorizationStatus) -> Color {
        switch status {
        case .authorized: return .green
        case .notDetermined: return .orange
        case .denied, .restricted: return .red
        @unknown default: return .gray
        }
    }
}

// MARK: - Open Settings Button

/// Reusable button that deep-links to the app's iOS Settings page.
/// Used in permission rows when a permission has been denied or restricted.
struct OpenSettingsButton: View {
    var permission: PermissionAnalyticsPermission = .unknown
    var sourceSurface: PermissionAnalyticsSurface = .settings
    /// Live permission snapshot at tap time. Required for accurate
    /// settings-return diff and recovery-success analytics.
    var snapshot: PermissionPolicySnapshot? = nil

    var body: some View {
        Button {
            PermissionAnalyticsService.trackOpenSettingsTapped(
                permission: permission,
                sourceSurface: sourceSurface,
                snapshot: snapshot
            )
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            Text("Settings")
                .font(Theme.font12Medium)
                .foregroundStyle(.blue)
        }
    }
}
