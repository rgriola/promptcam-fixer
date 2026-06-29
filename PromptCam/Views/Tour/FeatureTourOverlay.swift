// PromptCam — Feature Tour Overlay
// June 26, 2026 - Full-screen coach-marks overlay using hole-punch technique.
// June 29, 2026 - Added explicit frame on dimLayer ZStack before compositingGroup to
//                 guarantee a non-zero compositing context regardless of animation state.
import SwiftUI
import OSLog

/// Full-screen guided tour overlay that spotlights one camera control at a time.
///
/// Each step highlights an element registered via `.tourAnchor(_:)`, dims the rest of the screen,
/// and shows an explanatory tooltip card. Navigation is forward-only by default; Back is available
/// after the first step.
struct FeatureTourOverlay: View {

    // MARK: - Inputs

    /// Coordinator that drives step navigation and owns `isActive`.
    let coordinator: TourCoordinator
    /// Global CGRect frames keyed by anchor ID, collected via `TourAnchorKey`.
    let frames: [String: CGRect]
    /// Called when the tour is fully dismissed (Finish or Skip).
    let onEnd: () -> Void

    // MARK: - Derived

    private var spotlightRect: CGRect? {
        guard let step = coordinator.currentStep else { return nil }
        let frame = frames[step.id]
        if frame == nil {
            Log.ui.warning("[Tour] anchor '\(step.id, privacy: .public)' has no registered frame — tooltip will use fallback position")
        }
        return frame
    }

    /// Spotlight rect expanded by padding for visual breathing room.
    private var paddedSpotlight: CGRect? {
        spotlightRect.map { $0.insetBy(dx: -14, dy: -12) }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Touch absorber — prevents camera controls from receiving taps during tour.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { /* swallow */ }

                // Dim layer with transparent spotlight cutout.
                dimLayer(spotlight: paddedSpotlight)

                // Tooltip card — always shown when a step is active.
                // Renders with a centered fallback position when the anchor frame isn’t ready yet.
                if let step = coordinator.currentStep {
                    let _ = { () -> Void in
                        let hasFrame = paddedSpotlight != nil
                        Log.ui.debug("[Tour] rendering step '\(step.id, privacy: .public)' — hasFrame=\(hasFrame, privacy: .public)")
                    }()
                    tooltipCard(step: step, spotlight: paddedSpotlight, screenSize: geo.size)
                        .frame(width: min(geo.size.width - 40, 400))
                        .position(
                            x: geo.size.width / 2,
                            y: tooltipY(spotlight: paddedSpotlight, screenSize: geo.size)
                        )
                        .animation(.spring(duration: 0.4), value: coordinator.currentIndex)
                }
            }
        }
        // .ignoresSafeArea() is REQUIRED here.
        // tourAnchor frames use .global (origin = physical screen top-left).
        // This GeometryReader must also report full-screen dimensions so that
        // the spotlight position and tooltip position share the same origin.
        // The dimLayer ZStack also uses .ignoresSafeArea(), making all three consistent.
        .ignoresSafeArea()
    }

    // MARK: - Dim Layer

    /// Semi-transparent dim overlay with a hole punched at the spotlight rect.
    @ViewBuilder
    private func dimLayer(spotlight: CGRect?) -> some View {
        ZStack {
            // Dark semi-transparent fill — .ignoresSafeArea() here ensures the black
            // extends into the dynamic island and home indicator regions even when the
            // ZStack itself is sized to the safe-area content area.
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            // Rounded-rectangle cutout using destination-out blend mode.
            // The compositingGroup on the outer ZStack flattens this into a bitmap
            // so the blend mode punches through to transparency (showing content beneath).
            if let s = spotlight {
                RoundedRectangle(cornerRadius: 16)
                    .frame(width: s.width, height: s.height)
                    .position(x: s.midX, y: s.midY)
                    .blendMode(.destinationOut)
                    .animation(.spring(duration: 0.45), value: s.midX)
                    .animation(.spring(duration: 0.45), value: s.midY)
            }
        }
        .compositingGroup()
        .ignoresSafeArea()
    }

    // MARK: - Tooltip Card

    private func tooltipCard(step: TourStep, spotlight: CGRect?, screenSize: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header: SF Symbol icon + title
            HStack(spacing: 10) {
                Image(systemName: step.icon)
                    .font(.title3)
                    .foregroundStyle(Theme.yellow)
                    .frame(width: 26, alignment: .center)
                Text(step.title)
                    .font(Theme.font16Bold)
                    .foregroundStyle(Theme.white)
                Spacer()
            }

            // Description body
            Text(step.description)
                .font(Theme.font12Medium)
                .foregroundStyle(Theme.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)

            Divider()
                .background(Theme.white.opacity(0.2))

            // Navigation row: Back — progress — Skip? Next/Finish
            HStack(spacing: 0) {
                // Back
                Button {
                    withAnimation(.spring(duration: 0.4)) {
                        coordinator.back()
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(Theme.font12Semibold)
                        .foregroundStyle(coordinator.isFirst ? Theme.white.opacity(0.25) : Theme.white)
                }
                .disabled(coordinator.isFirst)

                Spacer()

                // Step counter
                Text(coordinator.progress)
                    .font(Theme.mono12Medium)
                    .foregroundStyle(Theme.white.opacity(0.45))

                Spacer()

                // Skip (only on on-demand tour) + Next/Finish
                HStack(spacing: 14) {
                    if !coordinator.isRequired {
                        Button("Skip") {
                            withAnimation(.easeOut(duration: 0.25)) {
                                coordinator.end()
                            }
                            onEnd()
                        }
                        .font(Theme.font12Semibold)
                        .foregroundStyle(Theme.white.opacity(0.5))
                    }

                    Button {
                        if coordinator.isLast {
                            withAnimation(.easeOut(duration: 0.25)) {
                                coordinator.end()
                            }
                            onEnd()
                        } else {
                            withAnimation(.spring(duration: 0.4)) {
                                coordinator.next()
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(coordinator.isLast ? "Finish" : "Next")
                            if !coordinator.isLast {
                                Image(systemName: "chevron.right")
                            }
                        }
                        .font(Theme.font12Semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.yellow)
                        .foregroundStyle(Color.black)
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Tooltip Positioning

    /// Returns the Y center for the tooltip card.
    /// Prefers above the spotlight; falls back to below if not enough space.
    /// Falls back to 40% of screen height when no anchor frame is available yet.
    private func tooltipY(spotlight: CGRect?, screenSize: CGSize) -> CGFloat {
        guard let spotlight = spotlight else {
            // Anchor frame not yet collected — center the card at 40% screen height.
            return screenSize.height * 0.40
        }

        let estimatedCardHeight: CGFloat = 190
        let gap: CGFloat = 24
        let topSafeArea: CGFloat = 60

        let aboveCenterY = spotlight.minY - gap - estimatedCardHeight / 2
        if aboveCenterY - estimatedCardHeight / 2 >= topSafeArea {
            return aboveCenterY
        }

        // Not enough space above — place below spotlight.
        return spotlight.maxY + gap + estimatedCardHeight / 2
    }
}
