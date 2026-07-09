// July 9, 2026 - GitHub Copilot (Claude Opus 4.7)
// Unit tests for CarouselDragMath — the pure math powering the recordings
// carousel's snap, direction-lock, and drift correction behavior.

import CoreGraphics
import XCTest

@testable import PromptCam

final class CarouselDragMathTests: XCTestCase {

     // MARK: - baseOffset

     func testBaseOffsetForIndexZeroIsZero() {
          XCTAssertEqual(CarouselDragMath.baseOffset(forIndex: 0, slotWidth: 94), 0)
     }

     func testBaseOffsetScalesWithIndex() {
          XCTAssertEqual(CarouselDragMath.baseOffset(forIndex: 3, slotWidth: 94), -282)
     }

     // Simulates Fix C: an item BEFORE the active one is removed. Active
     // recording's index drops by 1; baseOffset must move by one slot toward 0.
     func testRecenteringWhenItemBeforeActiveRemoved() {
          // Before: active at index 3.
          // After delete of index 1: active is now at index 2.
          XCTAssertEqual(CarouselDragMath.baseOffset(forIndex: 2, slotWidth: 94), -188)
     }

     // Simulates a new recording being saved and inserted at index 0.
     func testRecenteringWhenItemInsertedBeforeActive() {
          // Before: active at index 2.
          // After insert at index 0: active is now at index 3.
          XCTAssertEqual(CarouselDragMath.baseOffset(forIndex: 3, slotWidth: 94), -282)
     }

     // MARK: - Direction lock (Fix D scaffolding)

     func testDirectionLockAcceptsPurelyHorizontalDrag() {
          XCTAssertTrue(
               CarouselDragMath.shouldEngageHorizontal(dx: 40, dy: 0)
          )
     }

     func testDirectionLockAcceptsDominantlyHorizontalDrag() {
          // dx/dy = 5.0 > 1.2
          XCTAssertTrue(
               CarouselDragMath.shouldEngageHorizontal(dx: 40, dy: 8)
          )
     }

     func testDirectionLockRejectsVerticalDrag() {
          // dx/dy = 0.3 < 1.2
          XCTAssertFalse(
               CarouselDragMath.shouldEngageHorizontal(dx: 6, dy: 20)
          )
     }

     func testDirectionLockRejectsDiagonalDrag() {
          // dx/dy = 1.0 < 1.2 (45deg)
          XCTAssertFalse(
               CarouselDragMath.shouldEngageHorizontal(dx: 30, dy: 30)
          )
     }

     func testDirectionLockZeroTranslationIsRejected() {
          XCTAssertFalse(
               CarouselDragMath.shouldEngageHorizontal(dx: 0, dy: 0)
          )
     }

     // MARK: - Target index resolution

     func testTargetIndexLeftFlickAdvancesNext() {
          // Starting at index 2, small drag left, high leftward velocity.
          let base = CarouselDragMath.baseOffset(forIndex: 2, slotWidth: 94)
          let target = CarouselDragMath.targetIndex(
               baseOffset: base,
               dragOffset: -60,
               slotWidth: 94,
               velocity: -700,
               count: 10
          )
          XCTAssertEqual(target, 3)
     }

     func testTargetIndexRightFlickReturnsPrev() {
          // Starting at index 2, small drag right, high rightward velocity.
          let base = CarouselDragMath.baseOffset(forIndex: 2, slotWidth: 94)
          let target = CarouselDragMath.targetIndex(
               baseOffset: base,
               dragOffset: 60,
               slotWidth: 94,
               velocity: 700,
               count: 10
          )
          XCTAssertEqual(target, 1)
     }

     func testTargetIndexSlowDragRoundsToNearest() {
          // Starting at index 3, small right drag with no velocity should stay put.
          let base = CarouselDragMath.baseOffset(forIndex: 3, slotWidth: 94)
          let target = CarouselDragMath.targetIndex(
               baseOffset: base,
               dragOffset: 20,
               slotWidth: 94,
               velocity: 0,
               count: 10
          )
          XCTAssertEqual(target, 3)
     }

     func testTargetIndexClampsAtLastIndexOnLeftFlick() {
          let base = CarouselDragMath.baseOffset(forIndex: 9, slotWidth: 94)
          let target = CarouselDragMath.targetIndex(
               baseOffset: base,
               dragOffset: -60,
               slotWidth: 94,
               velocity: -800,
               count: 10
          )
          XCTAssertEqual(target, 9)
     }

     func testTargetIndexClampsAtFirstIndexOnRightFlick() {
          let base = CarouselDragMath.baseOffset(forIndex: 0, slotWidth: 94)
          let target = CarouselDragMath.targetIndex(
               baseOffset: base,
               dragOffset: 60,
               slotWidth: 94,
               velocity: 800,
               count: 10
          )
          XCTAssertEqual(target, 0)
     }

     func testTargetIndexEmptyListReturnsZero() {
          let target = CarouselDragMath.targetIndex(
               baseOffset: 0,
               dragOffset: 0,
               slotWidth: 94,
               velocity: 0,
               count: 0
          )
          XCTAssertEqual(target, 0)
     }
}
