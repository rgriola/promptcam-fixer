import Foundation

/// Maps hardware machine identifiers to marketing model names.
enum DeviceModel {

    /// Returns the marketing name for the current device, e.g. "iPhone 17 Pro".
    static var marketingName: String {
        let identifier = machineIdentifier
        return modelMap[identifier] ?? identifier // fallback to raw identifier
    }

    /// Reads the hw.machine sysctl to get the device identifier (e.g. "iPhone17,1").
    private static var machineIdentifier: String {
        #if targetEnvironment(simulator)
        // In simulator, hw.machine returns "arm64". Use the simulated model instead.
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "Unknown"
            }
        }
        #endif
    }

    // MARK: - Model Map

    // swiftlint:disable line_length
    private static let modelMap: [String: String] = [
        // iPhone 17 series (2025)
        "iPhone18,1": "iPhone 17",
        "iPhone18,2": "iPhone 17 Air",
        "iPhone18,3": "iPhone 17 Pro",
        "iPhone18,4": "iPhone 17 Pro Max",

        // iPhone 16 series (2024)
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16",
        "iPhone17,5": "iPhone 16 Plus",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,6": "iPhone 16e",

        // iPhone 15 series (2023)
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",

        // iPhone 14 series (2022)
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",

        // iPhone 13 series (2021)
        "iPhone14,5": "iPhone 13",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",

        // iPhone SE
        "iPhone14,6": "iPhone SE (3rd gen)",
        "iPhone12,8": "iPhone SE (2nd gen)",

        // iPhone 12 series (2020)
        "iPhone13,2": "iPhone 12",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",

        // iPad models (common)
        "iPad13,16": "iPad Air (5th gen)",
        "iPad13,17": "iPad Air (5th gen)",
        "iPad14,3":  "iPad Pro 11-inch (4th gen)",
        "iPad14,4":  "iPad Pro 11-inch (4th gen)",
        "iPad14,5":  "iPad Pro 12.9-inch (6th gen)",
        "iPad14,6":  "iPad Pro 12.9-inch (6th gen)",
    ]
    // swiftlint:enable line_length
}
