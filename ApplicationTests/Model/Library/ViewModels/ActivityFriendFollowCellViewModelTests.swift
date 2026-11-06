@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import UIKit.UIActivity
import XCTest

@MainActor
final class ActivityFriendFollowCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = FriendsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
    makeProvider: {
      precondition(AppEnvironment.current.apiService is MockService)
      return AsyncFriendsProvider(service: AppEnvironment.current.apiService)
    }, sleep: { _ in })
  private lazy var vm: ActivityFriendFollowCellViewModel = ActivityFriendFollowCellViewModel(feature: self.feature, delay: {})
  override func tearDown() async throws {
    self.feature.reset()
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  private func advanceFriends(by interval: DispatchTimeInterval = .seconds(0)) async {
    await self.vm.waitForObservation()
    await self.feature.waitForOperations()
  }

  func testFriendDetails_Complete() async {
    let user = User.template
      |> \.avatar.small .~ "http://coolpic.com/cool.jpg"
      |> \.name .~ "Squiggles McTwiddle"

    let activity = Activity.template
      |> Activity.lens.user .~ user

    XCTAssertNil(self.vm.friendImageURL)
    XCTAssertNil(self.vm.title)

    self.vm.configureWith(activity: activity)

    XCTAssertEqual(self.vm.friendImageURL?.absoluteString, "http://coolpic.com/cool.jpg")
    XCTAssertEqual(self.vm.title?.string, "Squiggles McTwiddle is now following you!")
  }

  func testFriendDetails_Incomplete() async {
    let user = User.template
      |> \.name .~ "Squiggles McTwiddle"

    let activity = Activity.template
      |> Activity.lens.user .~ user

    XCTAssertNil(self.vm.friendImageURL)
    XCTAssertNil(self.vm.title)

    self.vm.configureWith(activity: activity)

    XCTAssertNotNil(self.vm.title)
    XCTAssertEqual(self.vm.title?.string, "Squiggles McTwiddle is now following you!")
  }

  func testFriendFollowing_Friend() async {
    let user = User.template
      |> \.avatar.small .~ "http://coolpic.com/cool.jpg"
      |> \.isFriend .~ true
      |> \.name .~ "Squiggles McTwiddle"

    let activity = Activity.template
      |> Activity.lens.user .~ user

    XCTAssertNil(self.vm.hideFollowButton)
    XCTAssertEqual([], self.segmentTrackingClient.events)

    self.vm.configureWith(activity: activity)

    XCTAssertEqual(self.vm.hideFollowButton, true)
    XCTAssertEqual([], self.segmentTrackingClient.events)
  }

  func testFriendFollowing_NonFriend() async {
    let user = User.template
      |> \.avatar.medium .~ "http://coolpic.com/cool.jpg"
      |> \.isFriend .~ false
      |> \.name .~ "Squiggles McTwiddle"

    let activity = Activity.template
      |> Activity.lens.user .~ user

    XCTAssertNil(self.vm.hideFollowButton)
    XCTAssertEqual([], self.segmentTrackingClient.events)

    self.vm.configureWith(activity: activity)

    XCTAssertEqual(self.vm.hideFollowButton, false)

    self.vm.followButtonTapped()
    XCTAssertEqual(self.vm.hideFollowButton, false)
    await self.vm.waitForObservation()
    XCTAssertEqual(self.vm.hideFollowButton, true)
  }

  func testRetainFriendStatusOnReuse_After_Following() async {
    let user = User.template
      |> \.avatar.small .~ "http://coolpic.com/cool.jpg"
      |> \.isFriend .~ false
      |> \.name .~ "Squiggles McTwiddle"

    let activity = Activity.template
      |> Activity.lens.user .~ user

    XCTAssertNil(self.vm.hideFollowButton)

    self.vm.configureWith(activity: activity)

    XCTAssertEqual(self.vm.hideFollowButton, false)

    self.vm.followButtonTapped()
    await self.feature.waitForOperations()
    await self.advanceFriends()
  }
}
