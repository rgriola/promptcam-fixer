// Recording Timer Panel
// June 13, 2026 - GitHub Copilot (Claude Sonnet 4.5)
//
// Displays recording duration with state-based styling.
// - Gray background when standby (duration = 0)
// - Red background when actively recording
import SwiftUI

/// Timer panel that displays recording duration in MM:SS format.
struct RecordingTimerPanel: View {
    /// Elapsed recording time in seconds.
    let duration: TimeInterval
    /// Whether recording is currently active.
    let isRecording: Bool
    
    var body: some View {
        Text(formattedTime)
            .font(.system(.body, design: .monospaced))
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, Theme.space12)
            .padding(.vertical, Theme.space8)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
    
    /// Background color based on recording state.
    private var backgroundColor: Color {
        isRecording ? .red : Color.gray.opacity(0.6)
    }
    
    /// Formats duration as MM:SS.
    private var formattedTime: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    VStack(spacing: 20) {
        RecordingTimerPanel(duration: 0, isRecording: false)
        RecordingTimerPanel(duration: 45, isRecording: true)
        RecordingTimerPanel(duration: 185, isRecording: true)
    }
    .padding()
    .background(Color.black)
}
