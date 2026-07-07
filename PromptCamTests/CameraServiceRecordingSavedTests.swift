// July 7, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Phase 1 tests: recording-saved callback
// Verifies CameraService fires onRecordingSavedToLibrary exactly when the
// injected PhotoLibrarySaver succeeds, and publishes an error otherwise.

import XCTest
import Photos
@testable import PromptCam

@MainActor
final class CameraServiceRecordingSavedTests: XCTestCase {

    // MARK: - Fakes

    /// Fake saver: records whether it was called and honors a preset result.
    final class FakeSaver: PhotoLibrarySaver, @unchecked Sendable {
        enum Outcome { case success, failure(Error) }
        let outcome: Outcome
        private(set) var savedURL: URL?

        init(outcome: Outcome) { self.outcome = outcome }

        func saveVideo(at url: URL) async throws {
            savedURL = url
            switch outcome {
            case .success: return
            case .failure(let error): throw error
            }
        }
    }

    struct StubError: Error, Equatable {}

    // MARK: - Helpers

    /// Writes a tiny placeholder file so `performSave` has something to hand
    /// to the saver + clean up. The fake saver never opens the file — it just
    /// records the URL.
    private func makeTempVideoURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        try Data([0x00]).write(to: url)
        return url
    }

    // MARK: - Tests

    func test_onRecordingSaved_firesWhenSaveSucceeds() async throws {
        let saver = FakeSaver(outcome: .success)
        let service = CameraService(photoSaver: saver)
        let url = try makeTempVideoURL()

        let expectation = expectation(description: "onRecordingSavedToLibrary fires")
        service.onRecordingSavedToLibrary = { expectation.fulfill() }

        // Call performSave directly to bypass the PHPhotoLibrary permission
        // guard, which is .notDetermined on a fresh test simulator and would
        // short-circuit before reaching the saver.
        service.performSave(url)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(saver.savedURL, url)
    }

    func test_onRecordingSaved_doesNotFireWhenSaveFails() async throws {
        let saver = FakeSaver(outcome: .failure(StubError()))
        let service = CameraService(photoSaver: saver)
        let url = try makeTempVideoURL()

        nonisolated(unsafe) var savedCallbackFired = false
        service.onRecordingSavedToLibrary = { savedCallbackFired = true }

        let errorExpectation = expectation(description: "onError fires")
        service.onError = { _ in errorExpectation.fulfill() }

        service.performSave(url)

        await fulfillment(of: [errorExpectation], timeout: 2.0)
        XCTAssertFalse(savedCallbackFired, "Save callback must not fire on failure")
    }

    func test_defaultInit_installsRealSaver() {
        // Just confirms the default arg on init keeps the type callable — no
        // assertion needed beyond compile. Guards against accidental removal
        // of the default init argument.
        let service = CameraService()
        XCTAssertNotNil(service)
    }
}
