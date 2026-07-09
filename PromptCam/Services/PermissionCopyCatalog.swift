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
     static let onboardingTitle = "PromptCam"

     static let onboardingRequiredSummary =
          "PromptCam needs Camera, Microphone, and Photo Library to record and save videos."

     static let onboardingOptionalSummary =
          "Location and Speech-to-Text are optional and can be enabled later in Settings."

     static let onboardingBlockedRequiredMessage =
          "One or more required permissions are off. Tap Settings on the row to enable access."

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
}
