@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class OnboardingUseCaseTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  var useCase: OnboardingUseCase!


  override func setUp() async throws {
    try await super.setUp()

    self.useCase = OnboardingUseCase(for: Bundle.main)


  }

  func testUseCase_onboardingItems_EmitsAListOfAll5OboardingItemTypes_Once() {
    XCTAssertEqual(self.useCase.uiOutputs.onboardingItems.count, 5)
  }

  func testUseCase_completedAllowTrackingRequest_SetsAdvertisingID_WhenShouldRequestAuthStatus_isTrue() {
    let appTrackingTransparency = MockAppTrackingTransparency()
    appTrackingTransparency.requestAndSetAuthorizationStatusFlag = true
    appTrackingTransparency.shouldRequestAuthStatus = true

    withEnvironment(
      appTrackingTransparency: appTrackingTransparency
    ) {
      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)
      XCTAssertTrue(self.useCase.uiInputs.allowTrackingTapped())
    }
  }
}
