@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions
import ReactiveExtensions_TestHelpers
import ReactiveSwift
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
  private lazy var vm: ActivityFriendFollowCellViewModel = ActivityFriendFollowCellViewModel(feature: self.feature)
  let hideFollowButton = TestObserver<Bool, Never>()
  let friendImageURL = TestObserver<String?, Never>()
  let title = TestObserver<String, Never>()

  override func setUp() {
    super.setUp()

    MainActor.assumeIsolated {
      self.vm.outputs.hideFollowButton.observe(self.hideFollowButton.observer)
      self.vm.outputs.friendImageURL.map { $0?.absoluteString }.observe(self.friendImageURL.observer)
      self.vm.outputs.title.map { $0.string }.observe(self.title.observer)
    }
  }

  override func tearDown() async throws {
    self.feature.reset()
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  private func advanceFriends(by interval: DispatchTimeInterval = .seconds(0)) async {
    await self.feature.waitForOperations()
    await self.scheduler.advance(by: interval)
    await self.feature.waitForOperations()
    await self.scheduler.advance()
  }

  func testFriendDetails_Complete() async {
    let user = User.template
      |> \.avatar.small .~ "http://coolpic.com/cool.jpg"
      |> \.name .~ "Squiggles McTwiddle"

    let activity = Activity.template
      |> Activity.lens.user .~ user

    self.friendImageURL.assertValueCount(0)
    self.title.assertValueCount(0)

    self.vm.inputs.configureWith(activity: activity)

    self.friendImageURL.assertValues(["http://coolpic.com/cool.jpg"])
    self.title.assertValues(["Squiggles McTwiddle is now following you!"])
  }

  func testFriendDetails_Incomplete() async {
    let user = User.template
      |> \.name .~ "Squiggles McTwiddle"

    let activity = Activity.template
      |> Activity.lens.user .~ user

    self.friendImageURL.assertValueCount(0)
    self.title.assertValueCount(0)

    self.vm.inputs.configureWith(activity: activity)

    self.friendImageURL.assertValueCount(1)
    self.title.assertValues(["Squiggles McTwiddle is now following you!"])
  }

  func testFriendFollowing_Friend() async {
    let user = User.template
      |> \.avatar.small .~ "http://coolpic.com/cool.jpg"
      |> \.isFriend .~ true
      |> \.name .~ "Squiggles McTwiddle"

    let activity = Activity.template
      |> Activity.lens.user .~ user

    self.hideFollowButton.assertValueCount(0)
    XCTAssertEqual([], self.segmentTrackingClient.events)

    self.vm.inputs.configureWith(activity: activity)

    self.hideFollowButton.assertValues([true], "Hide Follow Button")
    XCTAssertEqual([], self.segmentTrackingClient.events)
  }

  func testFriendFollowing_NonFriend() async {
    let user = User.template
      |> \.avatar.medium .~ "http://coolpic.com/cool.jpg"
      |> \.isFriend .~ false
      |> \.name .~ "Squiggles McTwiddle"

    let activity = Activity.template
      |> Activity.lens.user .~ user

    self.hideFollowButton.assertValueCount(0)
    XCTAssertEqual([], self.segmentTrackingClient.events)

    self.vm.inputs.configureWith(activity: activity)

    self.hideFollowButton.assertValues([false], "Show Follow Button")

    self.vm.inputs.followButtonTapped()
    await self.feature.waitForOperations()

    self.hideFollowButton.assertValues([false], "Follow Button does not change")
  }

  func testRetainFriendStatusOnReuse_After_Following() async {
    let user = User.template
      |> \.avatar.small .~ "http://coolpic.com/cool.jpg"
      |> \.isFriend .~ false
      |> \.name .~ "Squiggles McTwiddle"

    let activity = Activity.template
      |> Activity.lens.user .~ user

    self.hideFollowButton.assertValueCount(0)

    self.vm.inputs.configureWith(activity: activity)

    self.hideFollowButton.assertValues([false], "Show Follow Button")

    self.vm.inputs.followButtonTapped()
    await self.feature.waitForOperations()
    await self.advanceFriends()
  }
}
