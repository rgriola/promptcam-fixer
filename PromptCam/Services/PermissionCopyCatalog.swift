// July 9, 2026 - 4:02pm - GitHub Copilot
// PromptCam — Permission Copy Catalog
// Centralizes user-facing permission copy so messaging stays consistent.

import Foundation

enum PermissionCopyKey: CaseIterable {
    case camera
    case microphone
    case photoLibrary
    case location
    case speechToText
}

enum PermissionCopyCatalog {
    static let onboardingTitle = "Cue Vue"

    static let onboardingRequiredSummary =
        "Camera, Mic & Photo Library access required."

    static let onboardingOptionalSummary =
        "GPS & Speech-to-Text are optional."

    static let onboardingBlockedRequiredMessage =
        "A required permission is not active. Tap Settings to enable access."

    static func description(for key: PermissionCopyKey) -> String {
        switch key {
        case .camera:
            "Required to capture video."
        case .microphone:
            "Required to record audio."
        case .photoLibrary:
            "Required to save videos."
        case .location:
            "Optional: GPS tag on video."
        case .speechToText:
            "Optional: Speech-to-Text for scripting."
        }
    }

    static func requiredPermissionRecoveryTitle(for key: PermissionCopyKey) -> String {
        switch key {
        case .camera:
            "Camera Access Required"
        case .microphone:
            "Microphone Access Required"
        case .photoLibrary:
            "Photo Library Access Required"
        case .location:
            "Location Access"
        case .speechToText:
            "Speech to Text Access"
        }
    }

    static func requiredPermissionRecoveryMessage(for key: PermissionCopyKey) -> String {
        switch key {
        case .camera:
            "Camera access required. Open Settings, enable Camera, then return to continue."

        case .microphone:
            "Microphone access required. Open Settings, enable Microphone, then return to continue."

        case .photoLibrary:
            "Photo Library access required. Open Settings, enable Photos access, then return to continue."

        case .location:
            "GPS Data is optional for tagging videos."

        case .speechToText:
            optionalSpeechRecoveryMessage
        }
    }

    static let optionalSpeechRecoveryMessage =
        "Speech to Text is optional. Open Settings to enable."
}
