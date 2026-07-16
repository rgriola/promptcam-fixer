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
          "Cue Vue needs access to Camera, Microphone & Photo Library."

     static let onboardingOptionalSummary =
          "GPS & Speech-to-Text are optional."

     static let onboardingBlockedRequiredMessage =
          "A required permission are not active. Tap Settings to enable access."

     static func description(for key: PermissionCopyKey) -> String {
          switch key {
          case .camera:
               return "Required to capture video."
          case .microphone:
               return "Required to record audio."
          case .photoLibrary:
               return "Required to save recordings."
          case .location:
               return "Optional: adds GPS tags to clips."
          case .speechToText:
               return "Optional: enables automatic transcript features."
          }
     }

     static func requiredPermissionRecoveryTitle(for key: PermissionCopyKey) -> String {
          switch key {
               
          case .camera:
               return "Camera Access Required"
          case .microphone:
               return "Microphone Access Required"
          case .photoLibrary:
               return "Photo Library Access Required"
          case .location:
               return "Location Access"
          case .speechToText:
               return "Speech to Text Access"
          }
     }

     static func requiredPermissionRecoveryMessage(for key: PermissionCopyKey) -> String {
          switch key {
          case .camera:
               return
                    "Cue Vuecannot record video without Camera access. Open Settings, enable Camera, then return to continue."
          case .microphone:
               return
                    "Cue Vue cannot record audio without Microphone access. Open Settings, enable Microphone, then return to continue."
          case .photoLibrary:
               return
                    "Cue Vue cannot save recordings without Photo Library access. Open Settings, enable Photos access, then return to continue."

          case .location:
               return "Location access is optional and only used for GPS metadata."

          case .speechToText:
               return optionalSpeechRecoveryMessage
          }
     }

     static let optionalSpeechRecoveryMessage =
          "Speech to Text is optional. Enable it in Settings if you want transcript features; recording still works without it."
}
