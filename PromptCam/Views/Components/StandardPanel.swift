// June 17, 2026 — Standardised panel container for consistent UI across the app.
import SwiftUI

/// A reusable dark-glass panel container that provides consistent chrome
/// across all overlay panels in the app (Audio Source, Aperture, EV,
/// Teleprompter, etc.).
///
/// **What it provides** (so child panels don't have to):
/// - Dark glass background (`Theme.panelBg`)
/// - Glass border stroke (`Theme.glassBorder`)
/// - Large corner radius (`Theme.radiusLg`)
/// - Drop shadow
/// - Header with SF Symbol icon, title, and close (✕) button
/// - Divider below header
/// - Optional auto-dismiss timer
/// - Horizontal padding (`24pt`)
///
/// **What the child provides** (via `@ViewBuilder content`):
/// - The panel body: sliders, rows, buttons, lists, etc.
///
/// ## Usage
/// ```swift
/// StandardPanel(
///     title: "Audio Sources",
///     icon: "mic.badge.plus",
///     autoDismissAfter: 12,
///     onDismiss: { showPanel = false }
/// ) {
///     // Your panel content here
/// }
/// ```
struct StandardPanel<Content: View>: View {
    let title: String
    let icon: String
    let autoDismissAfter: TimeInterval?
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    /// Creates a standardised panel.
    /// - Parameters:
    ///   - title: Header title text.
    ///   - icon: SF Symbol name for the header icon.
    ///   - autoDismissAfter: Seconds before the panel auto-dismisses.
    ///     Pass `nil` to disable auto-dismiss.
    ///   - onDismiss: Called when the user taps ✕ or the timer fires.
    ///   - content: The panel body content.
    init(
        title: String,
        icon: String,
        autoDismissAfter: TimeInterval? = 12,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.autoDismissAfter = autoDismissAfter
        self.onDismiss = onDismiss
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.white)
                Text(title)
                    .font(Theme.font16Semibold)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button {
                    onDismiss()
                } label: { // close button
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.white)
                }
            }
            .padding(.horizontal, Theme.space16)
            .padding(.vertical, Theme.space12)

            Divider()
                .overlay(Theme.separator)

            // Content
            content()
                .padding(Theme.space16)
        }
        .background(Theme.bgGrad)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLg)
                .strokeBorder(Theme.glassBorder, lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .modifier(AutoDismissModifier(
            duration: autoDismissAfter,
            onDismiss: onDismiss
        ))
    }
}

// MARK: - Auto-Dismiss

/// Conditionally attaches an auto-dismiss timer to the panel.
private struct AutoDismissModifier: ViewModifier {
    let duration: TimeInterval?
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        if let duration {
            content
                .task {
                    try? await Task.sleep(for: .seconds(duration))
                    guard !Task.isCancelled else { return }
                    onDismiss()
                }
        } else {
            content
        }
    }
}

// MARK: - Standard Scrim + Panel Presentation Helper

/// Convenience view that wraps a `StandardPanel` with the standard
/// 10% scrim, tap-outside-to-dismiss, and scale+opacity transition.
///
/// Use this in the CameraView `ZStack` for consistent panel presentation:
/// ```swift
/// if showMyPanel {
///     StandardPanelOverlay(onDismiss: { showMyPanel = false }) {
///         StandardPanel(title: "My Panel", icon: "gear", onDismiss: { showMyPanel = false }) {
///             // content
///         }
///     }
/// }
/// ```
struct StandardPanelOverlay<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Color.black.opacity(0.1)
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.25)) {
                    onDismiss()
                }
            }

        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

