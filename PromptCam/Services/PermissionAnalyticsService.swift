import AVFoundation
import CoreLocation
import Foundation
import Photos
import Speech

enum PermissionAnalyticsEvent: String, Sendable {
     case permissionGateShown = "permission_gate_shown"
     case permissionGrantAccessTapped = "permission_grant_access_tapped"
     case permissionOpenSettingsTapped = "permission_open_settings_tapped"
     case permissionSettingsReturned = "permission_settings_returned"
     case permissionRecoverySuccess = "permission_recovery_success"
     case permissionBlockedLoopDetected = "permission_blocked_loop_detected"
     case speechPermissionStatusObserved = "speech_permission_status_observed"
     case speechPermissionOpenSettingsTapped = "speech_permission_open_settings_tapped"
     case permissionSupportDiagnosticSummary = "permission_support_diagnostic_summary"
}

enum PermissionAnalyticsSurface: String, Sendable {
     case gate
     case runtimeAlert
     case settings
}

enum PermissionAnalyticsPermission: String, Sendable {
     case camera
     case microphone
     case photoLibrary
     case location
     case speechToText
     case unknown
}

struct PermissionAnalyticsPayload: Equatable, Sendable {
     let event: PermissionAnalyticsEvent
     let fields: [String: String]
}

enum PermissionAnalyticsPayloadBuilder {
     static func gateShown(
          snapshot: PermissionPolicySnapshot,
          sourceScreen: String
     ) -> PermissionAnalyticsPayload {
          PermissionAnalyticsPayload(
               event: .permissionGateShown,
               fields: [
                    "sourceScreen": sourceScreen,
                    "blockedPermissions": blockedPermissionString(from: snapshot),
               ]
          )
     }

     static func openSettingsTapped(
          permission: PermissionAnalyticsPermission,
          sourceSurface: PermissionAnalyticsSurface,
          snapshot: PermissionPolicySnapshot?
     ) -> PermissionAnalyticsPayload {
          var fields: [String: String] = [
               "permissionType": permission.rawValue,
               "sourceSurface": sourceSurface.rawValue,
          ]

          if let snapshot {
               fields["blockedPermissions"] = blockedPermissionString(from: snapshot)
          }

          return PermissionAnalyticsPayload(
               event: .permissionOpenSettingsTapped,
               fields: fields
          )
     }

     static func grantAccessTapped(
          snapshot: PermissionPolicySnapshot,
          sourceScreen: String
     ) -> PermissionAnalyticsPayload {
          PermissionAnalyticsPayload(
               event: .permissionGrantAccessTapped,
               fields: [
                    "sourceScreen": sourceScreen,
                    "undeterminedPermissions": undeterminedPermissionString(from: snapshot),
               ]
          )
     }

     static func settingsReturned(
          previousSnapshot: PermissionPolicySnapshot?,
          currentSnapshot: PermissionPolicySnapshot,
          timeInSettingsMs: Int?
     ) -> PermissionAnalyticsPayload {
          let diff = diffSummary(previous: previousSnapshot, current: currentSnapshot)

          var fields: [String: String] = [
               "changedPermissions": diff.changed,
               "unchangedPermissions": diff.unchanged,
          ]

          if let timeInSettingsMs {
               fields["timeInSettingsMs"] = String(timeInSettingsMs)
          }

          return PermissionAnalyticsPayload(
               event: .permissionSettingsReturned,
               fields: fields
          )
     }

     static func recoverySuccess(
          previousSnapshot: PermissionPolicySnapshot,
          currentSnapshot: PermissionPolicySnapshot,
          recoverySurface: PermissionAnalyticsSurface,
          recoveryDurationMs: Int?
     ) -> PermissionAnalyticsPayload {
          let recovered = recoveredPermissionString(
               previous: previousSnapshot, current: currentSnapshot)

          var fields: [String: String] = [
               "recoveredPermissions": recovered,
               "recoverySurface": recoverySurface.rawValue,
          ]

          if let recoveryDurationMs {
               fields["recoveryDurationMs"] = String(recoveryDurationMs)
          }

          return PermissionAnalyticsPayload(
               event: .permissionRecoverySuccess,
               fields: fields
          )
     }

     static func blockedLoopDetected(
          loopCount: Int,
          snapshot: PermissionPolicySnapshot,
          lastAction: String?
     ) -> PermissionAnalyticsPayload {
          var fields: [String: String] = [
               "loopCount": String(loopCount),
               "blockedPermissions": blockedPermissionString(from: snapshot),
          ]

          if let lastAction {
               fields["lastAction"] = lastAction
          }

          return PermissionAnalyticsPayload(
               event: .permissionBlockedLoopDetected,
               fields: fields
          )
     }

     static func speechPermissionStatusObserved(
          status: SFSpeechRecognizerAuthorizationStatus,
          sourceScreen: String
     ) -> PermissionAnalyticsPayload {
          PermissionAnalyticsPayload(
               event: .speechPermissionStatusObserved,
               fields: [
                    "speechStatus": speechStatusString(status),
                    "sourceScreen": sourceScreen,
               ]
          )
     }

     static func speechPermissionOpenSettingsTapped(
          sourceSurface: PermissionAnalyticsSurface,
          speechStatus: SFSpeechRecognizerAuthorizationStatus?
     ) -> PermissionAnalyticsPayload {
          var fields: [String: String] = [
               "sourceSurface": sourceSurface.rawValue
          ]

          if let speechStatus {
               fields["speechStatus"] = speechStatusString(speechStatus)
          }

          return PermissionAnalyticsPayload(
               event: .speechPermissionOpenSettingsTapped,
               fields: fields
          )
     }

     static func supportDiagnosticSummary(
          snapshot: PermissionPolicySnapshot,
          sourceScreen: String
     ) -> PermissionAnalyticsPayload {
          PermissionAnalyticsPayload(
               event: .permissionSupportDiagnosticSummary,
               fields: [
                    "sourceScreen": sourceScreen,
                    "camera": avStatusString(snapshot.camera),
                    "microphone": avStatusString(snapshot.microphone),
                    "photoLibrary": photoStatusString(snapshot.photoLibrary),
                    "location": locationStatusString(snapshot.location),
                    "speechToText": speechStatusString(snapshot.speechToText),
                    "requiredPermissionsGranted": snapshot.requiredPermissionsGranted
                         ? "true" : "false",
               ]
          )
     }

     static func blockedPermissionString(from snapshot: PermissionPolicySnapshot) -> String {
          var blocked: [String] = []

          if snapshot.camera != .authorized {
               blocked.append(PermissionAnalyticsPermission.camera.rawValue)
          }
          if snapshot.microphone != .authorized {
               blocked.append(PermissionAnalyticsPermission.microphone.rawValue)
          }
          if snapshot.photoLibrary != .authorized && snapshot.photoLibrary != .limited {
               blocked.append(PermissionAnalyticsPermission.photoLibrary.rawValue)
          }

          return blocked.joined(separator: ",")
     }

     static func undeterminedPermissionString(from snapshot: PermissionPolicySnapshot) -> String {
          var undetermined: [String] = []

          if snapshot.camera == .notDetermined {
               undetermined.append(PermissionAnalyticsPermission.camera.rawValue)
          }
          if snapshot.microphone == .notDetermined {
               undetermined.append(PermissionAnalyticsPermission.microphone.rawValue)
          }
          if snapshot.photoLibrary == .notDetermined {
               undetermined.append(PermissionAnalyticsPermission.photoLibrary.rawValue)
          }
          if snapshot.location == .notDetermined {
               undetermined.append(PermissionAnalyticsPermission.location.rawValue)
          }
          if snapshot.speechToText == .notDetermined {
               undetermined.append(PermissionAnalyticsPermission.speechToText.rawValue)
          }

          return undetermined.joined(separator: ",")
     }

     static func supportSummaryText(from snapshot: PermissionPolicySnapshot) -> String {
          "Camera=\(avStatusString(snapshot.camera)), Mic=\(avStatusString(snapshot.microphone)), Photos=\(photoStatusString(snapshot.photoLibrary)), Location=\(locationStatusString(snapshot.location)), Speech=\(speechStatusString(snapshot.speechToText)), RequiredReady=\(snapshot.requiredPermissionsGranted ? "Yes" : "No")"
     }

     private static func diffSummary(
          previous: PermissionPolicySnapshot?,
          current: PermissionPolicySnapshot
     ) -> (changed: String, unchanged: String) {
          guard let previous else {
               return (
                    changed: "camera,microphone,photoLibrary,location,speechToText",
                    unchanged: ""
               )
          }

          let currentStates = permissionStateMap(from: current)
          let previousStates = permissionStateMap(from: previous)
          let keys = ["camera", "microphone", "photoLibrary", "location", "speechToText"]

          var changed: [String] = []
          var unchanged: [String] = []

          for key in keys {
               let oldValue = previousStates[key] ?? "unknown"
               let newValue = currentStates[key] ?? "unknown"
               if oldValue == newValue {
                    unchanged.append(key)
               } else {
                    changed.append("\(key):\(oldValue)->\(newValue)")
               }
          }

          return (
               changed: changed.joined(separator: ","),
               unchanged: unchanged.joined(separator: ",")
          )
     }

     private static func recoveredPermissionString(
          previous: PermissionPolicySnapshot,
          current: PermissionPolicySnapshot
     ) -> String {
          var recovered: [String] = []

          if (previous.camera == .denied || previous.camera == .restricted)
               && current.camera == .authorized
          {
               recovered.append(PermissionAnalyticsPermission.camera.rawValue)
          }
          if (previous.microphone == .denied || previous.microphone == .restricted)
               && current.microphone == .authorized
          {
               recovered.append(PermissionAnalyticsPermission.microphone.rawValue)
          }
          if (previous.photoLibrary == .denied || previous.photoLibrary == .restricted)
               && (current.photoLibrary == .authorized || current.photoLibrary == .limited)
          {
               recovered.append(PermissionAnalyticsPermission.photoLibrary.rawValue)
          }

          return recovered.joined(separator: ",")
     }

     private static func permissionStateMap(from snapshot: PermissionPolicySnapshot) -> [String:
          String]
     {
          [
               "camera": avStatusString(snapshot.camera),
               "microphone": avStatusString(snapshot.microphone),
               "photoLibrary": photoStatusString(snapshot.photoLibrary),
               "location": locationStatusString(snapshot.location),
               "speechToText": speechStatusString(snapshot.speechToText),
          ]
     }

     private static func avStatusString(_ status: AVAuthorizationStatus) -> String {
          switch status {
          case .authorized: return "authorized"
          case .denied: return "denied"
          case .restricted: return "restricted"
          case .notDetermined: return "notDetermined"
          @unknown default: return "unknown"
          }
     }

     private static func photoStatusString(_ status: PHAuthorizationStatus) -> String {
          switch status {
          case .authorized: return "authorized"
          case .limited: return "limited"
          case .denied: return "denied"
          case .restricted: return "restricted"
          case .notDetermined: return "notDetermined"
          @unknown default: return "unknown"
          }
     }

     private static func locationStatusString(_ status: CLAuthorizationStatus) -> String {
          switch status {
          case .authorizedAlways: return "authorizedAlways"
          case .authorizedWhenInUse: return "authorizedWhenInUse"
          case .denied: return "denied"
          case .restricted: return "restricted"
          case .notDetermined: return "notDetermined"
          @unknown default: return "unknown"
          }
     }

     private static func speechStatusString(_ status: SFSpeechRecognizerAuthorizationStatus)
          -> String
     {
          switch status {
          case .authorized: return "authorized"
          case .denied: return "denied"
          case .restricted: return "restricted"
          case .notDetermined: return "notDetermined"
          @unknown default: return "unknown"
          }
     }
}

@MainActor
enum PermissionAnalyticsService {
     private struct SettingsOpenContext {
          let openedAt: Date
          let snapshot: PermissionPolicySnapshot?
          let sourceSurface: PermissionAnalyticsSurface
     }

     private static var blockedLoopCount = 0
     private static var settingsOpenContext: SettingsOpenContext?
     private static var lastSpeechStatusBySourceScreen: [String: String] = [:]

     static func trackGateShown(
          snapshot: PermissionPolicySnapshot, sourceScreen: String = "onboarding"
     ) {
          let payload = PermissionAnalyticsPayloadBuilder.gateShown(
               snapshot: snapshot,
               sourceScreen: sourceScreen
          )
          track(payload)

          if !snapshot.requiredPermissionsGranted {
               blockedLoopCount += 1
               if blockedLoopCount > 1 {
                    track(
                         PermissionAnalyticsPayloadBuilder.blockedLoopDetected(
                              loopCount: blockedLoopCount,
                              snapshot: snapshot,
                              lastAction: "gateShown"
                         )
                    )
               }
          } else {
               blockedLoopCount = 0
          }
     }

     static func trackOpenSettingsTapped(
          permission: PermissionAnalyticsPermission,
          sourceSurface: PermissionAnalyticsSurface,
          snapshot: PermissionPolicySnapshot? = nil
     ) {
          let payload = PermissionAnalyticsPayloadBuilder.openSettingsTapped(
               permission: permission,
               sourceSurface: sourceSurface,
               snapshot: snapshot
          )
          track(payload)

          settingsOpenContext = SettingsOpenContext(
               openedAt: Date(),
               snapshot: snapshot,
               sourceSurface: sourceSurface
          )

          if permission == .speechToText {
               let speechStatus = snapshot?.speechToText
               track(
                    PermissionAnalyticsPayloadBuilder.speechPermissionOpenSettingsTapped(
                         sourceSurface: sourceSurface,
                         speechStatus: speechStatus
                    )
               )
          }
     }

     static func trackGrantAccessTapped(
          snapshot: PermissionPolicySnapshot, sourceScreen: String = "onboarding"
     ) {
          let payload = PermissionAnalyticsPayloadBuilder.grantAccessTapped(
               snapshot: snapshot,
               sourceScreen: sourceScreen
          )
          track(payload)
     }

     static func trackSettingsReturnedIfNeeded(currentSnapshot: PermissionPolicySnapshot) {
          guard let context = settingsOpenContext else { return }

          let durationMs = max(0, Int(Date().timeIntervalSince(context.openedAt) * 1000))
          track(
               PermissionAnalyticsPayloadBuilder.settingsReturned(
                    previousSnapshot: context.snapshot,
                    currentSnapshot: currentSnapshot,
                    timeInSettingsMs: durationMs
               )
          )

          if let previousSnapshot = context.snapshot,
               previousSnapshot.shouldBlockAppEntry,
               !currentSnapshot.shouldBlockAppEntry
          {
               let recoveryPayload = PermissionAnalyticsPayloadBuilder.recoverySuccess(
                    previousSnapshot: previousSnapshot,
                    currentSnapshot: currentSnapshot,
                    recoverySurface: context.sourceSurface,
                    recoveryDurationMs: durationMs
               )

               if !(recoveryPayload.fields["recoveredPermissions"] ?? "").isEmpty {
                    track(recoveryPayload)
                    blockedLoopCount = 0
               }
          }

          settingsOpenContext = nil
     }

     static func trackSpeechPermissionStatusObserved(
          status: SFSpeechRecognizerAuthorizationStatus,
          sourceScreen: String
     ) {
          let statusValue =
               PermissionAnalyticsPayloadBuilder
               .speechPermissionStatusObserved(status: status, sourceScreen: sourceScreen)
               .fields["speechStatus"] ?? "unknown"

          if lastSpeechStatusBySourceScreen[sourceScreen] == statusValue {
               return
          }

          lastSpeechStatusBySourceScreen[sourceScreen] = statusValue
          track(
               PermissionAnalyticsPayloadBuilder.speechPermissionStatusObserved(
                    status: status,
                    sourceScreen: sourceScreen
               )
          )
     }

     static func trackSupportDiagnosticSummary(
          snapshot: PermissionPolicySnapshot,
          sourceScreen: String
     ) {
          track(
               PermissionAnalyticsPayloadBuilder.supportDiagnosticSummary(
                    snapshot: snapshot,
                    sourceScreen: sourceScreen
               )
          )
     }

     static func supportSummaryText(from snapshot: PermissionPolicySnapshot) -> String {
          PermissionAnalyticsPayloadBuilder.supportSummaryText(from: snapshot)
     }

     static func track(_ payload: PermissionAnalyticsPayload) {
          let sortedFields = payload.fields
               .sorted { $0.key < $1.key }
               .map { "\($0.key)=\($0.value)" }
               .joined(separator: " ")

          Log.analytics.debug(
               "event=\(payload.event.rawValue, privacy: .public) \(sortedFields, privacy: .public)"
          )
     }
}
