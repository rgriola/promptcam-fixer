import AVFoundation
import SwiftUI

/// A compact picker presented when a new audio input is detected.
/// Lists all available audio sources and lets the user choose which
/// mic the app should use for recording and metering.
///
/// Uses `StandardPanel` for consistent panel chrome.
struct AudioSourcePickerView: View {
    let inputs: [AVAudioSessionPortDescription]
    let activeInputName: String?
    let onSelect: (AVAudioSessionPortDescription?) -> Void
    let onDismiss: () -> Void

    /// Cache: maps port UID → AVCaptureDevice.localizedName.
    /// Built once when the view initializes so we don't re-query
    /// AVCaptureDevice on every render cycle.
    private let captureDeviceNames: [String: String] = {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        return Dictionary(uniqueKeysWithValues: session.devices.map {
            ($0.uniqueID, $0.localizedName)
        })
    }()

    var body: some View {
        StandardPanel(
            title: "Audio Sources",
            icon: "mic.badge.plus",
            autoDismissAfter: 12,
            onDismiss: onDismiss
        ) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(inputs, id: \.uid) { port in
                        audioInputRow(port)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func audioInputRow(_ port: AVAudioSessionPortDescription) -> some View {
        // Use the AVCaptureDevice product name when available (e.g. "DJI Mini Mic 3").
        // Fall back to portName (e.g. "Wireless Mic Rx") when no capture device matches.
        let displayName = captureDeviceNames[port.uid] ?? port.portName
        
        // portTypeLabel now has full port context so it can embed the
        // device-specific name (e.g. "USB · Wireless Mic Rx") when needed.
        let subtitle = portTypeLabel(port)

        let isActive = port.portName == activeInputName

        Button {
            onSelect(port)
        } label: {
            HStack(spacing: Theme.space12) {
                Image(systemName: iconName(for: port.portType))
                    .font(.system(size: 20))
                    .foregroundStyle(isActive ? Theme.accent : Theme.primaryText)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(Theme.font16Medium)
                        .foregroundStyle(Theme.primaryText)

                    Text(subtitle)
                        .font(Theme.font10Regular)
                        .foregroundStyle(Theme.tertiaryText)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, Theme.space16)
            .padding(.vertical, Theme.space12)
            .background {
                RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
                    .fill(Theme.black.opacity(isActive ? 0.5 : 0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
                            .strokeBorder(Theme.white.opacity(0.3), lineWidth: 1)
                    }
            }
            .contentShape(
                RoundedRectangle(
                    cornerRadius: Theme.radiusLg, style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func iconName(for portType: AVAudioSession.Port) -> String {
        switch portType {
        case .builtInMic:
            return "iphone"
        case .headsetMic:
            return "headphones"
        case .usbAudio:
            return "cable.connector"
        case .bluetoothHFP, .bluetoothA2DP:
            return "wave.3.right"
        default:
            return "mic.fill"
        }
    }

    private func portTypeLabel(_ port: AVAudioSessionPortDescription) -> String {
        switch port.portType {
        case .builtInMic:
            return "Built-in Microphone"
        case .headsetMic:
            return "Wired Headset"
        case .usbAudio:
            // If a product name was resolved, annotate with the USB class
            // descriptor so the creator sees both layers of identity.
            // e.g. "USB · Wireless Mic Rx" beneath "DJI Mini Mic 3".
            if captureDeviceNames[port.uid] != nil {
                return "USB · \(port.portName)"
            }
            return "USB Audio"
        case .bluetoothHFP:
            return "Bluetooth Hands-Free"
        case .bluetoothA2DP:
            return "Bluetooth Audio"
        default:
            return "External Input"
        }
    }
}
