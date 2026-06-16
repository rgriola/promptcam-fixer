@testable import PromptCam
import XCTest

final class AudioMeterServiceTests: XCTestCase {

    // MARK: - normalizeDecibels

    func testNormalizeDecibels_silence_returnsZero() {
        XCTAssertEqual(AudioMeterService.normalizeDecibels(-60), 0.0, accuracy: 0.001)
    }

    func testNormalizeDecibels_fullScale_returnsOne() {
        XCTAssertEqual(AudioMeterService.normalizeDecibels(0), 1.0, accuracy: 0.001)
    }

    func testNormalizeDecibels_midRange() {
        // -30 dB is halfway in the -60..0 range
        XCTAssertEqual(AudioMeterService.normalizeDecibels(-30), 0.5, accuracy: 0.001)
    }

    func testNormalizeDecibels_belowSilence_clampsToZero() {
        XCTAssertEqual(AudioMeterService.normalizeDecibels(-100), 0.0, accuracy: 0.001)
    }

    func testNormalizeDecibels_aboveZero_clampsToOne() {
        XCTAssertEqual(AudioMeterService.normalizeDecibels(5), 1.0, accuracy: 0.001)
    }

    func testNormalizeDecibels_minus6dB() {
        // -6 dB → ((-6) - (-60)) / (0 - (-60)) = 54/60 = 0.9
        XCTAssertEqual(AudioMeterService.normalizeDecibels(-6), 0.9, accuracy: 0.001)
    }

    func testNormalizeDecibels_minus12dB() {
        // -12 dB → 48/60 = 0.8
        XCTAssertEqual(AudioMeterService.normalizeDecibels(-12), 0.8, accuracy: 0.001)
    }

    func testNormalizeDecibels_minus20dB() {
        // -20 dB → 40/60 ≈ 0.667
        XCTAssertEqual(AudioMeterService.normalizeDecibels(-20), 0.667, accuracy: 0.001)
    }
}
