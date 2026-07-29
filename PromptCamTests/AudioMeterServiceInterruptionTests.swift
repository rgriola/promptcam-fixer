@testable import PromptCam
import AVFoundation
import XCTest

/// Verifies the interruption-suspension state machine that prevents the
/// voice-dictation restart loop from thrashing `mediaservicesd` (which was
/// starving `AVCaptureSession`'s audio path and freezing the camera
/// preview).
///
/// These tests exercise the state flag directly rather than posting real
/// `AVAudioSession.interruptionNotification`s — the test host does not
/// have a live audio session, and the state-machine correctness is the
/// entire point of the fix.
final class AudioMeterServiceInterruptionTests: XCTestCase {

    private var service: AudioMeterService!

    override func setUp() {
        super.setUp()
        service = AudioMeterService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - State flag transitions

    func test_isInterrupted_startsFalse() {
        XCTAssertFalse(service.isInterrupted)
    }

    func test_handleInterruption_began_setsFlagTrue() {
        service.handleInterruption(typeRaw: AVAudioSession.InterruptionType.began.rawValue)
        XCTAssertTrue(service.isInterrupted, "expected .began to set isInterrupted")
    }

    func test_handleInterruption_ended_clearsFlag() {
        service.handleInterruption(typeRaw: AVAudioSession.InterruptionType.began.rawValue)
        XCTAssertTrue(service.isInterrupted)

        service.handleInterruption(typeRaw: AVAudioSession.InterruptionType.ended.rawValue)
        XCTAssertFalse(service.isInterrupted, "expected .ended to clear isInterrupted")
    }

    func test_handleInterruption_nilPayload_defaultsToBegan() {
        // Real notifications occasionally arrive with a missing type key.
        // The service treats an unknown value as `.began` (fail-safe: we
        // suspend the pipeline rather than let it thrash).
        service.handleInterruption(typeRaw: nil)
        XCTAssertTrue(service.isInterrupted)
    }

    // MARK: - Multiple .began events

    func test_handleInterruption_multipleBegans_stayInterrupted() {
        // iOS occasionally posts .began twice (system dictation + AVCapture
        // audio session). The flag must remain true.
        service.handleInterruption(typeRaw: AVAudioSession.InterruptionType.began.rawValue)
        service.handleInterruption(typeRaw: AVAudioSession.InterruptionType.began.rawValue)
        XCTAssertTrue(service.isInterrupted)
    }

    // MARK: - Ordering: .ended without prior .began is a no-op regression guard

    func test_handleInterruption_endedWithoutBegan_flagStaysFalse() {
        service.handleInterruption(typeRaw: AVAudioSession.InterruptionType.ended.rawValue)
        XCTAssertFalse(service.isInterrupted)
    }
}
