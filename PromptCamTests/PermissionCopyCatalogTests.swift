// PermissionCopyCatalogTests.swift
// PromptCamTests
//
// Verifies centralized permission copy mappings used by onboarding.

import XCTest

@testable import PromptCam

final class PermissionCopyCatalogTests: XCTestCase {

     func testOnboardingSummaryCopyIsNonEmpty() {
          XCTAssertFalse(PermissionCopyCatalog.onboardingTitle.isEmpty)
          XCTAssertFalse(PermissionCopyCatalog.onboardingRequiredSummary.isEmpty)
          XCTAssertFalse(PermissionCopyCatalog.onboardingOptionalSummary.isEmpty)
          XCTAssertFalse(PermissionCopyCatalog.onboardingBlockedRequiredMessage.isEmpty)
     }

     func testRequiredPermissionDescriptionsContainRequired() {
          XCTAssertTrue(PermissionCopyCatalog.description(for: .camera).contains("Required"))
          XCTAssertTrue(PermissionCopyCatalog.description(for: .microphone).contains("Required"))
          XCTAssertTrue(PermissionCopyCatalog.description(for: .photoLibrary).contains("Required"))
     }

     func testOptionalPermissionDescriptionsContainOptional() {
          XCTAssertTrue(PermissionCopyCatalog.description(for: .location).contains("Optional"))
          XCTAssertTrue(PermissionCopyCatalog.description(for: .speechToText).contains("Optional"))
     }

     func testAllPermissionKeysReturnDescription() {
          for key in PermissionCopyKey.allCases {
               XCTAssertFalse(PermissionCopyCatalog.description(for: key).isEmpty)
          }
     }
}
