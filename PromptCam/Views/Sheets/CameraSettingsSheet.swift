// PromptCam — Settings Sheet
// Extracted from CameraView.swift (refactor June 1, 2026)
// Uses shared PermissionStatusDisplay helpers and PermissionStatusRow component.
// July 7, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Add Help section linking to InstructionsView
import AVFoundation
import CoreLocation
import Photos
import SwiftUI

// MARK: - Settings Sheet

/// Modal sheet showing app info and live permission statuses.
/// Permission statuses auto-refresh when the sheet appears and when
/// returning from iOS Settings via `scenePhase` observation.
struct CameraSettingsSheet: View {
    /// Device capabilities detected at launch.
    let capabilities: DeviceCapabilities
    /// Callback to dismiss settings sheet.
    let onClose: () -> Void

    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var photoStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var locationStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus
    /// Controls the format accordion open/closed state.
    @State private var formatsExpanded = false
    /// Controls presentation of the in-app instructions.
    @State private var showInstructions = false

    @Environment(\.scenePhase) private var scenePhase

    /// Settings view showing app info and live permission statuses.
    var body: some View {
        NavigationStack {
            List {

                Section("About") {
                    SettingStatusRow(title: "Version", value: appVersion)
                    SettingStatusRow(title: "Model Name", value: deviceInfo)
                }
                .settingsSectionHeaderStyle()

                Section("Support") {
                    /*
                    Button {
                        showInstructions = true
                    } label: {
                        Label("App Guide", systemImage: "service.dog.fill")
                            .font(Theme.font16Regular)
                            .foregroundStyle(Theme.white)
                    }
                    */

                    Button {
                        openSlackChannel()
                    } label: {
                        HStack {
                            Label("Slack #mvp\nMobile Video Production", systemImage: "bubble.left.and.bubble.right.fill")
                                .font(Theme.font16Regular)
                                .foregroundStyle(Theme.white)
                            Spacer()
                            Image(systemName: "chevron.up.forward.dotted.2")
                                .font(Theme.font16Regular)
                                .foregroundStyle(Theme.primaryText)
                        }
                    }
                }
                .settingsSectionHeaderStyle()

            
                Section("Permissions") {

                    PermissionStatusRow(
                        icon: "camera.fill",
                        iconColor: .blue,
                        title: "Camera",
                        status: PermissionStatusDisplay.label(for: cameraStatus),
                        statusColor: PermissionStatusDisplay.color(for: cameraStatus)
                    )

                    PermissionStatusRow(
                        icon: "mic.fill",
                        iconColor: .orange,
                        title: "Microphone",
                        status: PermissionStatusDisplay.label(for: micStatus),
                        statusColor: PermissionStatusDisplay.color(for: micStatus)
                    )

                    PermissionStatusRow(
                        icon: "photo.on.rectangle",
                        iconColor: .green,
                        title: "Photo Library",
                        status: PermissionStatusDisplay.label(for: photoStatus),
                        statusColor: PermissionStatusDisplay.color(for: photoStatus)
                    )

                    PermissionStatusRow(
                        icon: "location.fill",
                        iconColor: .teal,
                        title: "Location",
                        status: PermissionStatusDisplay.label(for: locationStatus),
                        statusColor: PermissionStatusDisplay.color(for: locationStatus)
                    )
                }
                .listRowBackground(Theme.black.opacity(0.1))
                .foregroundStyle(Theme.white)

                 // MARK: - Formats Accordion
                Section {
                    
                    DisclosureGroup(isExpanded: $formatsExpanded) {

                        // STANDARD sub-heading
                        Text("Standard")
                            .font(Theme.font12Medium)
                            .foregroundStyle(Theme.primaryText)
                            .textCase(.uppercase)
                            .listRowSeparator(.hidden)
                            .padding(.top, 4)

                        ForEach(capabilities.standardFormats, id: \.self) { format in
                            formatRow(format)
                        }

                        // CINEMATIC sub-heading — only when device supports the mode.
                        if capabilities.supportsCinematicMode {
                            Text("Cinematic")
                                .font(Theme.font12Medium)
                                .foregroundStyle(Theme.primaryText)
                                .textCase(.uppercase)
                                .listRowSeparator(.hidden)
                                .padding(.top, 8)

                            ForEach(capabilities.cinematicFormats, id: \.self) { format in
                                formatRow(format, icon: "circle.dotted.and.circle")
                            }
                        }

                    } label: {
                        Label("Video Formats", systemImage: "video.fill")
                            .font(Theme.font16Regular)
                    }

                } header: {
                    Text("Formats")
                        .foregroundStyle(Theme.primaryText)
                }
                .settingsSectionHeaderStyle()
                .tint(Theme.white)
                
            }
            .tint(Theme.white)
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseToolbarButton { onClose() }
                }
            }
            .onAppear { refreshStatuses() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { refreshStatuses() }
            }
            .sheet(isPresented: $showInstructions) {
                InstructionsView()
            }
        }
        .presentationBackground(Theme.bgGrad)
    }

    // MARK: - Computed Properties

    /// Human-readable app version/build string shown in settings.
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// Device model + OS version, e.g. "iPhone 17 Pro · iOS 26.0"
    private var deviceInfo: String {
        let os = UIDevice.current
        return "\(DeviceModel.marketingName) · \(os.systemName) \(os.systemVersion)"
    }

    /// Reusable format row — renders from a validated RecordingFormat pair.
    private func formatRow(_ format: RecordingFormat, icon: String = "video.fill") -> some View {
        HStack(spacing: Theme.space8) {
            Image(systemName: icon)
                .foregroundStyle(Theme.purple)
                .frame(width: 20)
            Text("\(format.resolution.rawValue) \(format.resolution.dimensionLabel) \(format.frameRate.rawValue)p")
                .font(Theme.font16Regular)
                .foregroundStyle(Theme.white)
        }
    }

    private func refreshStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        locationStatus = CLLocationManager().authorizationStatus
    }

    // MARK: - Slack Deep Link

    private static let slackTeamID    = "E7T3R16EM"
    private static let slackChannelID = "C08KEGNF00N"

    /// Opens the support Slack channel.
    /// Tries the native Slack app first; falls back to the web client.
    private func openSlackChannel() {
        let appURL = URL(string: "slack://channel?team=\(Self.slackTeamID)&id=\(Self.slackChannelID)")!
        let webURL = URL(string: "https://app.slack.com/client/\(Self.slackTeamID)/\(Self.slackChannelID)")!

        if UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else {
            UIApplication.shared.open(webURL)
        }
    }
}
