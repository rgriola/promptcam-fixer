// PromptCam — Feature Tour Step Model
// June 26, 2026 - Coach marks system for first-use onboarding and Guide Dog replay.
import Foundation

/// A single step in the feature tour, defining which element to spotlight and what to explain.
struct TourStep: Identifiable, Equatable {
    /// Matches the ID used in `.tourAnchor(_:)` on the target view.
    let id: String
    /// SF Symbol shown in the tooltip header.
    let icon: String
    /// Short bold title for the tooltip.
    let title: String
    /// One-to-two sentence description shown in the tooltip body.
    let description: String
}

/// Static catalog of all available tour steps.
enum TourCatalog {
    /// Six essential steps shown on first launch and on-demand via the Guide Dog button.
    static let essentials: [TourStep] = [
        TourStep(
            id: "vu-meter",
            icon: "waveform",
            title: "Audio Input",
            description: "These bars show your live audio level. Tap to select or change your microphone input."
        ),
        TourStep(
            id: "scroll-button",
            icon: "play.fill",
            title: "Start Scrolling",
            description: "Tap to start and pause the teleprompter. Use this to control your reading pace while filming."
        ),
        TourStep(
            id: "reset-script",
            icon: "arrow.trianglehead.counterclockwise",
            title: "Reset Script",
            description: "Returns the script to the beginning so you can start your take over."
        ),
        TourStep(
            id: "script-button",
            icon: "sparkle.text.clipboard",
            title: "Script Editor",
            description: "Write, paste, or clean up your script. Removes extra formatting from apps like Outlook."
        ),
        TourStep(
            id: "adjust-button",
            icon: "text.viewfinder",
            title: "Teleprompter Controls",
            description: "Adjust scroll speed, font size, and text contrast to match your reading style."
        ),
        TourStep(
            id: "library-button",
            icon: "photo.on.rectangle",
            title: "Your Videos",
            description: "Tap to view, share, or delete your recorded videos."
        ),
    ]
}
