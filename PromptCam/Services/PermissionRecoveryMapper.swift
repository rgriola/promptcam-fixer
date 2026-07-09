import Speech

enum PermissionRecoveryAction: Equatable, Sendable {
     case dismiss
     case openSettings
}

struct PermissionRecoveryMessage: Equatable, Sendable {
     let title: String
     let message: String
     let action: PermissionRecoveryAction
}

enum PermissionRecoveryMapper {
     /// Maps runtime camera errors + current policy snapshot into user-facing
     /// recovery guidance with a concrete next action.
     static func runtimeRecovery(
          for error: CameraError,
          snapshot: PermissionPolicySnapshot
     ) -> PermissionRecoveryMessage {
          if snapshot.camera == .denied || snapshot.camera == .restricted {
               return requiredPermissionRecovery(for: .camera)
          }

          if snapshot.microphone == .denied || snapshot.microphone == .restricted {
               return requiredPermissionRecovery(for: .microphone)
          }

          if snapshot.photoLibrary == .denied || snapshot.photoLibrary == .restricted {
               return requiredPermissionRecovery(for: .photoLibrary)
          }

          switch error {
          case .photoLibraryPermissionDenied:
               return requiredPermissionRecovery(for: .photoLibrary)
          case .photoLibrarySaveFailed(let detail):
               if looksLikePermissionFailure(detail) {
                    return requiredPermissionRecovery(for: .photoLibrary)
               }
               return PermissionRecoveryMessage(
                    title: "Save Failed",
                    message: error.errorDescription ?? "Failed to save recording.",
                    action: .dismiss
               )
          default:
               return PermissionRecoveryMessage(
                    title: "Error",
                    message: error.errorDescription ?? "Unknown error.",
                    action: .dismiss
               )
          }
     }

     /// Optional speech-to-text recovery guidance for non-blocking surfaces.
     static func optionalSpeechRecoveryMessage(
          for status: SFSpeechRecognizerAuthorizationStatus
     ) -> String? {
          switch status {
          case .denied, .restricted:
               return PermissionCopyCatalog.optionalSpeechRecoveryMessage
          default:
               return nil
          }
     }

     private static func requiredPermissionRecovery(for key: PermissionCopyKey)
          -> PermissionRecoveryMessage
     {
          PermissionRecoveryMessage(
               title: PermissionCopyCatalog.requiredPermissionRecoveryTitle(for: key),
               message: PermissionCopyCatalog.requiredPermissionRecoveryMessage(for: key),
               action: .openSettings
          )
     }

     private static func looksLikePermissionFailure(_ detail: String) -> Bool {
          let normalized = detail.lowercased()
          return normalized.contains("permission")
               || normalized.contains("denied")
               || normalized.contains("restricted")
               || normalized.contains("not authorized")
               || normalized.contains("unauthorized")
     }
}
