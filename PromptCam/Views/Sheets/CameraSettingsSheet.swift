// PromptCam — Settings Sheet
// Extracted from CameraView.swift (refactor June 1, 2026)
// Uses shared PermissionStatusDisplay helpers and PermissionStatusRow component.
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

    @Environment(\.scenePhase) private var scenePhase

    /// Settings view showing app info and live permission statuses.
    var body: some View {
        NavigationStack {
            List {

                Section("About") {
                    SettingStatusRow(title: "Version", value: appVersion)
                    SettingStatusRow(title: "Model Name", value: deviceInfo)
                }
                .listRowBackground(Theme.black.opacity(0.1))
                .foregroundStyle(Theme.white)

                // MARK: - Formats Accordion
                Section {
                    DisclosureGroup(isExpanded: $formatsExpanded) {

                        // STANDARD sub-heading
                        Text("Standard")
                            .font(Theme.font12Medium)
                            .foregroundStyle(Theme.secondaryText)
                            .textCase(.uppercase)
                            .listRowSeparator(.hidden)
                            .padding(.top, 4)

                        ForEach(standardFormats, id: \.self) { format in
                            formatRow(format)
                        }

                        // CINEMATIC sub-heading — only when device supports the mode.
                        if capabilities.supportsCinematicMode {
                            Text("Cinematic")
                                .font(Theme.font12Medium)
                                .foregroundStyle(Theme.secondaryText)
                                .textCase(.uppercase)
                                .listRowSeparator(.hidden)
                                .padding(.top, 8)

                            ForEach(cinematicFormats, id: \.self) { format in
                                formatRow(format, icon: "circle.dotted.and.circle")
                            }
                        }

                    } label: {
                        Label("Video Formats", systemImage: "video.fill")
                            .font(Theme.font16Regular)
                            .foregroundStyle(Theme.white)
                    }
                } header: {
                    Text("Formats")
                        .foregroundStyle(Theme.primaryText)
                }
                .listRowBackground(Theme.black.opacity(0.1))
                .foregroundStyle(Theme.white)
                
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

    /// Standard recording formats available on this device.
    /// Produces entries like "HD 1920×1080 30p", "4K 3840×2160 24p".
    private var standardFormats: [String] {
        var formats: [String] = []
        for resolution in capabilities.standardResolutions {
            for frameRate in capabilities.standardFrameRates {
                formats.append("\(resolution.rawValue) \(resolution.dimensionLabel) \(frameRate.rawValue)p")
            }
        }
        return formats
    }

    /// Cinematic recording formats available on this device.
    /// Produces entries like "HD 1920×1080 24p", "4K 3840×2160 30p".
    private var cinematicFormats: [String] {
        var formats: [String] = []
        for resolution in capabilities.cinematicResolutions {
            for frameRate in capabilities.cinematicFrameRates {
                formats.append("\(resolution.rawValue) \(resolution.dimensionLabel) \(frameRate.rawValue)p")
            }
        }
        return formats
    }

    /// Reusable format row with icon.
    private func formatRow(_ format: String, icon: String = "video.fill") -> some View {
        HStack(spacing: Theme.space8) {
            Image(systemName: icon)
                .foregroundStyle(Theme.purple)
                .frame(width: 20)
            Text(format)
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
}
