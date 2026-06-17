import AVFoundation
import SwiftUI

/// A compact picker presented when a new audio input is detected.
/// Lists all available audio sources and lets the user choose which
/// mic the app should use for recording and metering.
struct AudioSourcePickerView: View {
    let inputs: [AVAudioSessionPortDescription]
    let activeInputName: String?
    let onSelect: (AVAudioSessionPortDescription?) -> Void
    let onDismiss: () -> Void

    /// Seconds before the picker auto-dismisses if the user takes no action.
    private let autoDismissAfter: TimeInterval = 12

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Audio Source Detected")
                    .font(Theme.font16Semibold)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, Theme.space16)
            .padding(.vertical, Theme.space12)

            Divider()
                .overlay(Theme.separator)

            // Input list
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(inputs, id: \.uid) { port in
                        audioInputRow(port)
                    }
                }
                .padding(.vertical, Theme.space8)
            }
            .frame(maxHeight: 240)
        }
        .background(Theme.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLg)
                .strokeBorder(Theme.glassBorder, lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .task {
            try? await Task.sleep(for: .seconds(autoDismissAfter))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func audioInputRow(_ port: AVAudioSessionPortDescription) -> some View {
        let isActive = port.portName == activeInputName

        Button {
            onSelect(port)
        } label: {
            HStack(spacing: Theme.space12) {
                Image(systemName: iconName(for: port.portType))
                    .font(.system(size: 20))
                    .foregroundStyle(isActive ? Theme.accent : Theme.secondaryText)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(port.portName)
                        .font(Theme.font16Medium)
                        .foregroundStyle(Theme.primaryText)

                    Text(portTypeLabel(port.portType))
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
            .background(isActive ? Theme.accent.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
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

    private func portTypeLabel(_ portType: AVAudioSession.Port) -> String {
        switch portType {
        case .builtInMic:
            return "Built-in Microphone"
        case .headsetMic:
            return "Wired Headset"
        case .usbAudio:
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
