// July 7, 2026 - GitHub Copilot (Claude Sonnet 4.6) - Phase 2 tests: photo library change monitor
// Verifies register/unregister lifecycle, debounce coalescing, and idempotency.
// PHChange itself cannot be constructed in tests — we drive the change callback
// with a nil PHChange via unsafeBitCast, which works because our observer body
// only touches the parameter through PHPhotoLibraryChangeObserver's signature
// (it does not dereference change details).

import XCTest
import Photos
@testable import PromptCam

@MainActor
final class PhotoLibraryChangeMonitorTests: XCTestCase {

    // MARK: - Fake library

    /// Records register/unregister calls and holds a reference to the
    /// observer so tests can drive photoLibraryDidChange directly.
    final class FakeLibrary: PhotoLibraryObservable, @unchecked Sendable {
        private let lock = NSLock()
        private var _registerCount = 0
        private var _unregisterCount = 0
        private weak var _observer: PHPhotoLibraryChangeObserver?

        var registerCount: Int { lock.withLock { _registerCount } }
        var unregisterCount: Int { lock.withLock { _unregisterCount } }
        var observer: PHPhotoLibraryChangeObserver? { lock.withLock { _observer } }

        func register(_ observer: PHPhotoLibraryChangeObserver) {
            lock.withLock {
                _registerCount += 1
                _observer = observer
            }
        }

        func unregister(_ observer: PHPhotoLibraryChangeObserver) {
            lock.withLock {
                _unregisterCount += 1
                if _observer === observer { _observer = nil }
            }
        }
    }

    // MARK: - Helpers

    /// Drives the observer's `photoLibraryDidChange(_:)` without needing a
    /// real PHChange. Safe because our observer implementation only forwards
    /// the notification to schedule a debounced fire — it does not inspect
    /// the PHChange contents.
    private func fireChange(on observer: PHPhotoLibraryChangeObserver) {
        // Create a placeholder object that satisfies PHChange's type slot.
        // The observer body under test does not access any PHChange members.
        let placeholder: AnyObject = NSObject()
        let change = unsafeBitCast(placeholder, to: PHChange.self)
        observer.photoLibraryDidChange(change)
    }

    // MARK: - Tests

    func test_start_registersObserver() {
        let library = FakeLibrary()
        let monitor = PhotoLibraryChangeMonitor(library: library)

        monitor.start { }

        XCTAssertEqual(library.registerCount, 1)
        XCTAssertTrue(library.observer === monitor)
    }

    func test_startTwice_isIdempotent() {
        let library = FakeLibrary()
        let monitor = PhotoLibraryChangeMonitor(library: library)

        monitor.start { }
        monitor.start { }

        XCTAssertEqual(library.registerCount, 1, "second start() must be a no-op")
    }

    func test_stop_unregistersObserver() {
        let library = FakeLibrary()
        let monitor = PhotoLibraryChangeMonitor(library: library)

        monitor.start { }
        monitor.stop()

        XCTAssertEqual(library.unregisterCount, 1)
        XCTAssertNil(library.observer)
    }

    func test_stopWithoutStart_isNoOp() {
        let library = FakeLibrary()
        let monitor = PhotoLibraryChangeMonitor(library: library)

        monitor.stop()

        XCTAssertEqual(library.unregisterCount, 0)
    }

    func test_libraryChange_triggersCallbackAfterDebounce() async {
        let library = FakeLibrary()
        // Short debounce for a fast test.
        let monitor = PhotoLibraryChangeMonitor(library: library, debounceInterval: 0.05)

        let expectation = expectation(description: "onChange fires")
        monitor.start { expectation.fulfill() }

        guard let observer = library.observer else {
            XCTFail("Observer not registered"); return
        }
        fireChange(on: observer)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func test_multipleRapidChanges_coalesceIntoOneCallback() async {
        let library = FakeLibrary()
        let monitor = PhotoLibraryChangeMonitor(library: library, debounceInterval: 0.1)

        nonisolated(unsafe) var callCount = 0
        let expectation = expectation(description: "onChange fires once")
        expectation.assertForOverFulfill = true
        monitor.start {
            callCount += 1
            expectation.fulfill()
        }

        guard let observer = library.observer else {
            XCTFail("Observer not registered"); return
        }
        // Fire 5 changes back-to-back within the debounce window.
        for _ in 0..<5 { fireChange(on: observer) }

        await fulfillment(of: [expectation], timeout: 1.0)
        // Wait a bit longer to prove no additional callbacks fire.
        try? await Task.sleep(nanoseconds: 200_000_000) // 200 ms
        XCTAssertEqual(callCount, 1, "Rapid changes must coalesce into a single callback")
    }

    func test_stop_cancelsPendingDebounce() async {
        let library = FakeLibrary()
        let monitor = PhotoLibraryChangeMonitor(library: library, debounceInterval: 0.2)

        nonisolated(unsafe) var callCount = 0
        monitor.start { callCount += 1 }

        guard let observer = library.observer else {
            XCTFail("Observer not registered"); return
        }
        fireChange(on: observer)
        monitor.stop()

        // Wait past the debounce window; onChange must not fire.
        try? await Task.sleep(nanoseconds: 400_000_000) // 400 ms
        XCTAssertEqual(callCount, 0, "Pending callback must be cancelled by stop()")
    }
}
