@testable import Kickstarter_iOS
@testable import KsApi

import Prelude
import XCTest

@MainActor
internal final class EmptyStatesViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = EmptyStatesViewModel()

  func testGoToDiscovery_Non_Activity() {
    self.vm.configureWith(emptyState: .starred)
    _ = self.vm.viewWillAppear()
    guard case let .discovery(params) = self.vm.mainButtonTapped() else {
      return XCTFail("Expected discovery")
    }
    XCTAssertEqual(params, DiscoveryParams.defaults |> DiscoveryParams.lens.sort .~ .magic)
  }

  func testGoToDiscovery_Activity() {
    self.vm.configureWith(emptyState: .activity)
    _ = self.vm.viewWillAppear()
    guard case let .discovery(params) = self.vm.mainButtonTapped() else {
      return XCTFail("Expected discovery")
    }
    XCTAssertNil(params)
  }

  func testGoToFriends_SocialStates() {
    for state in [EmptyState.socialNoPledges, .socialDisabled] {
      self.vm.configureWith(emptyState: state)
      _ = self.vm.viewWillAppear()
      guard case .friends = self.vm.mainButtonTapped() else {
        return XCTFail("Expected friends for \(state)")
      }
    }
  }

  func testLateStateOnlyPresentsAfterAppearance() {
    XCTAssertNil(self.vm.setEmptyState(.starred))
    XCTAssertNotNil(self.vm.viewWillAppear())
    XCTAssertEqual(self.vm.setEmptyState(.socialDisabled)?.title, Strings.Its_better_with_friends())
    XCTAssertNil(self.vm.viewWillAppear())
  }

  func testMainButtonTapped_TrackingEvents() {
    self.vm.configureWith(emptyState: .activity)
    _ = self.vm.viewWillAppear()
    _ = self.vm.mainButtonTapped()

    XCTAssertEqual(["CTA Clicked"], self.segmentTrackingClient.events)
    XCTAssertEqual(self.segmentTrackingClient.properties(forKey: "context_page"), ["activity_feed"])
    XCTAssertEqual(self.segmentTrackingClient.properties(forKey: "context_cta"), ["discover"])
  }
}
