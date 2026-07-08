// PromptCam — Network Monitor
// Broadcasts current network connectivity via `@Observable` so views/services
// can react to network restoration (e.g. retry failed iCloud thumbnail loads
// in the recording carousel without waiting for the next explicit user action).
// July 8, 2026 - GitHub Copilot (Claude Opus 4.7) - Phase 3: initial

import Foundation
import Network
import Observation

/// Live network connectivity state. Wraps `NWPathMonitor` on a background
/// queue and mirrors the current path's `.satisfied` state onto `@MainActor`
/// properties so SwiftUI views can drive UI off it directly.
///
/// Use `NetworkMonitor.shared` — one monitor per app is sufficient and each
/// `NWPathMonitor` holds a dispatch source, so spawning per-view instances
/// wastes system resources.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// True when the current path is satisfied (any reachable interface).
    /// Initial value is `true` — we assume connectivity until the first update
    /// reports otherwise, so views don't briefly flash an "offline" state on
    /// launch before `NWPathMonitor` fires its first callback.
    private(set) var isConnected: Bool = true

    /// True when the current path is metered (cellular / hotspot / low-data).
    /// Exposed for future features (e.g. throttle prefetch on cellular, warn
    /// before large iCloud downloads); not currently gating any behavior.
    private(set) var isExpensive: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(
        label: "com.promptcam.fixer.network-monitor",
        qos: .utility
    )

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor in
                guard let self else { return }
                if self.isConnected != connected {
                    Log.network.info("Connectivity changed: \(connected ? "online" : "offline", privacy: .public)")
                }
                self.isConnected = connected
                self.isExpensive = expensive
            }
        }
        monitor.start(queue: queue)
    }
}
