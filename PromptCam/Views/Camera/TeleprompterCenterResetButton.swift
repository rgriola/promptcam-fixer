// PromptCam — Teleprompter Utility Controls (Align + Reset)
// Extracted from CameraView.swift (refactor June 1, 2026)
// July 10, 2026 - GitHub Copilot (GPT-5.3-Codex) - Shared utility button so
// visual size and hit target match; consumes grouped layout tokens.
import SwiftUI

// MARK: - Teleprompter Utility Stack

/// Vertical utility controls (Align on top, Reset below) placed on the
/// teleprompter edge. Keeps ownership and positioning colocated.
struct TeleprompterUtilityStackView: View {
    let textAlignment: TeleprompterTextAlignment
    let isRecording: Bool
    let onAlignmentTap: () -> Void
    let onResetTap: () -> Void

    var body: some View {
        VStack(spacing: CameraLayout.Teleprompter.utilityStackSpacing) {
            AlignmentToggleButton(
                alignment: textAlignment,
                isEnabled: !isRecording,
                action: onAlignmentTap
            )

            TeleprompterCenterResetButton(
                isDisabled: isRecording,
                action: onResetTap
            )
        }
    }
}

// MARK: - Shared Utility Button

/// Base component for teleprompter utility controls. The rendered frame,
/// background, and hit-test shape share one size so the visible box always
/// matches the tap target.
struct TeleprompterUtilityButton: View {
    let icon: String
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(Theme.icon16)
                    .foregroundStyle(Theme.white)
                Text(title)
                    .font(Theme.font10Regular)
                    .foregroundStyle(Theme.primaryText)
            }
            .frame(
                width: CameraLayout.Teleprompter.utilityButtonWidth,
                height: CameraLayout.Teleprompter.utilityButtonHeight
            )
            .background(
                RoundedRectangle(
                    cornerRadius: CameraLayout.Teleprompter.utilityButtonCornerRadius,
                    style: .continuous
                )
                .fill(Theme.black.opacity(0.35))
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: CameraLayout.Teleprompter.utilityButtonCornerRadius,
                    style: .continuous
                )
            )
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
    }
}

// MARK: - Reset Button

/// Snaps the first line of script to the teleprompter viewport center.
struct TeleprompterCenterResetButton: View {
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        TeleprompterUtilityButton(
            icon: "arrow.up.and.down.text.horizontal",
            title: "Reset",
            isEnabled: !isDisabled,
            action: action
        )
        .accessibilityLabel("Reset script position")
        .accessibilityHint("Centers script to the teleprompter center.")
    }
}

// MARK: - Alignment Toggle Button

/// Cycles teleprompter text alignment (center → left → right → center).
struct AlignmentToggleButton: View {
    let alignment: TeleprompterTextAlignment
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        TeleprompterUtilityButton(
            icon: alignment.iconName,
            title: "Align",
            isEnabled: isEnabled,
            action: action
        )
        .accessibilityLabel("Text alignment: \(alignment.rawValue)")
        .accessibilityHint("Cycles between center, left, and right alignment")
    }
}

// MARK: - Previews

#Preview("TeleprompterUtilityStackView") {
    ZStack {
        Theme.cameraBg.ignoresSafeArea()
        TeleprompterUtilityStackView(
            textAlignment: .center,
            isRecording: false,
            onAlignmentTap: {},
            onResetTap: {}
        )
    }
}

