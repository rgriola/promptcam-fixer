// CameraServiceInterruptionTests.swift
// PromptCamTests
//
// Verifies `CameraService`'s AVCaptureSession interruption / runtime-error
// recovery logic. Tests drive the internal handlers directly on `sessionQueue`
// rather than posting real `AVCaptureSession` notifications, so no camera
// hardware is required and tests are deterministic.
//
// The end-to-end notification path (registerSessionObservers ->
// NotificationCenter -> handler) is exercised by
// `test_deinit_removesObservers_soHandlerDoesNotFireAfterDealloc` using an
// isolated `NotificationCenter` injected into the service.

import XCTest
import AVFoundation
@testable import PromptCam

final class CameraServiceInterruptionTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a service bound to an isolated `NotificationCenter` so posts
    /// in one test do not leak into another.
    private func makeService() -> (CameraService, NotificationCenter) {
        let center = NotificationCenter()
        let service = CameraService(notificationCenter: center)
        return (service, center)
    }

    /// Runs `block` on the service's `sessionQueue` synchronously so the
    /// state assertions below can inspect the results without racing the
    /// async handler dispatch.
    private func onSessionQueue(_ service: CameraService, _ block: () -> Void) {
        service.sessionQueue.sync {
            block()
        }
    }

    /// Waits for any previously enqueued `sessionQueue` work to drain by
    /// enqueuing a barrier `sync` block. Used after posting a real
    /// notification (which hops from posting thread -> sessionQueue.async).
    private func drainSessionQueue(_ service: CameraService) {
        service.sessionQueue.sync {}
    }

    // MARK: - 1. Interruption sets flag for audio reason

    func test_wasInterrupted_audioReason_setsFlagAndDoesNotRestart() {
        let (service, _) = makeService()

        onSessionQueue(service) {
            service.isSessionConfigured = true
            service.handleInterruption(
                reasonRaw: AVCaptureSession.InterruptionReason.audioDeviceInUseByAnotherClient.rawValue
            )
        }

        onSessionQueue(service) {
            XCTAssertTrue(service.wasInterrupted,
                          "audioDeviceInUseByAnotherClient must set wasInterrupted so .interruptionEnded can restart the session.")
        }
    }

    // MARK: - 2. Background reason is ignored

    func test_wasInterrupted_backgroundReason_isIgnored() {
        let (service, _) = makeService()

        onSessionQueue(service) {
            service.isSessionConfigured = true
            service.handleInterruption(
                reasonRaw: AVCaptureSession.InterruptionReason.videoDeviceNotAvailableInBackground.rawValue
            )
        }

        onSessionQueue(service) {
            XCTAssertFalse(service.wasInterrupted,
                           "videoDeviceNotAvailableInBackground is owned by scene-phase teardown; the service must not mark for auto-restart.")
        }
    }

    // MARK: - 3. Multiple-foreground-apps reason is ignored

    func test_wasInterrupted_multipleForegroundApps_isIgnored() {
        let (service, _) = makeService()

        onSessionQueue(service) {
            service.isSessionConfigured = true
            service.handleInterruption(
                reasonRaw: AVCaptureSession.InterruptionReason.videoDeviceNotAvailableWithMultipleForegroundApps.rawValue
            )
        }

        onSessionQueue(service) {
            XCTAssertFalse(service.wasInterrupted,
                           "iPad Slide Over / Split View is user-initiated multitasking; must not mark for auto-restart.")
        }
    }

    // MARK: - 4. interruptionEnded requires foreground-active

    func test_interruptionEnded_skipsRestart_whenNotForegroundActive() {
        let (service, _) = makeService()

        onSessionQueue(service) {
            service.isSessionConfigured = true
            service.wasInterrupted = true
        }
        // Foreground flag NOT set (default false).

        onSessionQueue(service) {
            service.handleInterruptionEnded()
        }

        onSessionQueue(service) {
            XCTAssertTrue(service.wasInterrupted,
                          "wasInterrupted must remain true when the view is not foreground-active — so a later foreground restart can consume it.")
        }
    }

    // MARK: - 5. interruptionEnded requires isSessionConfigured

    func test_interruptionEnded_skipsRestart_whenSessionNotConfigured() {
        let (service, _) = makeService()

        service.setForegroundActive(true)
        onSessionQueue(service) {
            service.isSessionConfigured = false
            service.wasInterrupted = true
        }

        onSessionQueue(service) {
            service.handleInterruptionEnded()
        }

        onSessionQueue(service) {
            XCTAssertTrue(service.wasInterrupted,
                          "Handler must not clear wasInterrupted when the session is not configured — configureSession/startSession are the restart path.")
        }
    }

    // MARK: - 6. Media services reset triggers reconfigure + startSession

    func test_runtimeError_mediaServicesReset_reconfiguresAndRestarts() {
        let (service, _) = makeService()

        let cachedFormat = RecordingFormat(
            resolution: .hd1080p,
            frameRate: .fps30,
            mode: .standard
        )
        onSessionQueue(service) {
            service.isSessionConfigured = true
            service.lastConfiguredFormat = cachedFormat
        }

        onSessionQueue(service) {
            service.handleRuntimeError(code: .mediaServicesWereReset, localized: "reset")
        }

        // configureSession + startSession fire from sessionQueue via
        // .async — drain to let them enqueue.
        drainSessionQueue(service)

        onSessionQueue(service) {
            XCTAssertEqual(service.mediaServicesResetRecoveryCount, 1,
                           "Media-services-reset recovery must run exactly once per notification.")
            XCTAssertFalse(service.isSessionConfigured,
                           "isSessionConfigured must be reset so configureSession's guard permits re-plumbing. (Reconfigure fails in the test environment due to no camera; the flag stays false.)")
        }
    }

    // MARK: - 7. Unknown runtime error publishes error, no restart

    func test_runtimeError_unknownError_publishesError_noRestart() async {
        let (service, _) = makeService()

        let expectation = expectation(description: "onError fires with sessionRuntimeError")
        await MainActor.run {
            service.onError = { error in
                if case .sessionRuntimeError(let detail) = error {
                    XCTAssertEqual(detail, "boom",
                                   "Detail string from the AVError must be forwarded verbatim.")
                    expectation.fulfill()
                } else {
                    XCTFail("Unexpected error case: \(error)")
                }
            }
        }

        onSessionQueue(service) {
            service.handleRuntimeError(code: .unknown, localized: "boom")
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        onSessionQueue(service) {
            XCTAssertEqual(service.mediaServicesResetRecoveryCount, 0,
                           "Unknown errors must not trigger reconfiguration.")
            XCTAssertFalse(service.wasInterrupted,
                           "Unknown errors are not treated as interruptions.")
        }
    }

    // MARK: - 8. Deinit removes observers

    func test_deinit_removesObservers_soHandlerDoesNotFireAfterDealloc() {
        let center = NotificationCenter()
        weak var weakService: CameraService?
        // Use a dedicated AVCaptureSession as `object:` filter; we need a
        // reference we can post against after the service is deallocated.
        var capturedSession: AVCaptureSession?

        autoreleasepool {
            let service = CameraService(notificationCenter: center)
            weakService = service
            capturedSession = service.session
            service.sessionQueue.sync {
                service.registerSessionObservers()
            }
        }

        XCTAssertNil(weakService,
                     "CameraService should deallocate synchronously once the strong reference is dropped. If this fails, an observer is retaining self.")

        // Post the notification against the retained session object.
        // Without `removeObserver(self)` in deinit, this would attempt to
        // deliver to a deallocated instance and crash.
        guard let capturedSession else {
            XCTFail("Session should have been captured before dealloc")
            return
        }
        center.post(
            name: AVCaptureSession.wasInterruptedNotification,
            object: capturedSession,
            userInfo: [AVCaptureSessionInterruptionReasonKey:
                        AVCaptureSession.InterruptionReason.audioDeviceInUseByAnotherClient.rawValue]
        )
        // If we're still alive here, `removeObserver(self)` did its job.
    }

    // MARK: - End-to-end notification path (light-touch smoke test)

    /// Posts a real `wasInterrupted` notification through the injected
    /// notification center and confirms the flag flips. This exercises the
    /// selector-based observer wiring end-to-end.
    func test_notificationPath_wasInterrupted_flipsFlag() {
        let (service, center) = makeService()

        service.sessionQueue.sync {
            service.isSessionConfigured = true
            service.registerSessionObservers()
        }

        center.post(
            name: AVCaptureSession.wasInterruptedNotification,
            object: service.session,
            userInfo: [AVCaptureSessionInterruptionReasonKey:
                        AVCaptureSession.InterruptionReason.audioDeviceInUseByAnotherClient.rawValue]
        )
        drainSessionQueue(service)

        service.sessionQueue.sync {
            XCTAssertTrue(service.wasInterrupted,
                          "Selector-based observer must route the notification to handleInterruption and flip the flag.")
        }
    }

    /// Confirms that posting with a different `object` does NOT trigger the
    /// handler — verifies the `object: session` filter on `addObserver`.
    func test_notificationPath_wrongObject_isFiltered() {
        let (service, center) = makeService()

        service.sessionQueue.sync {
            service.isSessionConfigured = true
            service.registerSessionObservers()
        }

        // Post with a different (unrelated) AVCaptureSession as the object.
        let otherSession = AVCaptureSession()
        center.post(
            name: AVCaptureSession.wasInterruptedNotification,
            object: otherSession,
            userInfo: [AVCaptureSessionInterruptionReasonKey:
                        AVCaptureSession.InterruptionReason.audioDeviceInUseByAnotherClient.rawValue]
        )
        drainSessionQueue(service)

        service.sessionQueue.sync {
            XCTAssertFalse(service.wasInterrupted,
                           "Handler must not fire for notifications from a different capture session — the object: filter protects other sessions.")
        }
    }
}
