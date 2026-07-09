import Foundation

enum PermissionAnalyticsEvent: String, Sendable {
     case permissionGateShown = "permission_gate_shown"
     case permissionGrantAccessTapped = "permission_grant_access_tapped"
     case permissionOpenSettingsTapped = "permission_open_settings_tapped"
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
}

enum PermissionAnalyticsService {
     static func trackGateShown(
          snapshot: PermissionPolicySnapshot, sourceScreen: String = "onboarding"
     ) {
          let payload = PermissionAnalyticsPayloadBuilder.gateShown(
               snapshot: snapshot,
               sourceScreen: sourceScreen
          )
          track(payload)
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
