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
final class FindFriendsFriendFollowCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = FriendsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
    makeProvider: {
      precondition(AppEnvironment.current.apiService is MockService)
      return AsyncFriendsProvider(service: AppEnvironment.current.apiService)
    }, sleep: { _ in })
  private lazy var vm: FindFriendsFriendFollowCellViewModelType = FindFriendsFriendFollowCellViewModel(feature: self.feature)

  let cellAccessibilityValue = TestObserver<String, Never>()
  let enableFollowButton = TestObserver<Bool, Never>()
  let enableUnfollowButton = TestObserver<Bool, Never>()
  let followButtonAccessibilityLabel = TestObserver<String, Never>()
  let imageURL = TestObserver<String?, Never>()
  let location = TestObserver<String, Never>()
  let friendName = TestObserver<String, Never>()
  let projectsBackedText = TestObserver<String, Never>()
  let projectsCreatedText = TestObserver<String, Never>()
  let hideFollowButton = TestObserver<Bool, Never>()
  let hideUnfollowButton = TestObserver<Bool, Never>()
  let hideProjectsCreated = TestObserver<Bool, Never>()
  let unfollowButtonAccessibilityLabel = TestObserver<String, Never>()

  override func setUp() {
    super.setUp()

    MainActor.assumeIsolated {
      self.vm.outputs.enableFollowButton.observe(self.enableFollowButton.observer)
      self.vm.outputs.enableUnfollowButton.observe(self.enableUnfollowButton.observer)
      self.vm.outputs.imageURL.map { $0?.absoluteString }.observe(self.imageURL.observer)
      self.vm.outputs.location.observe(self.location.observer)
      self.vm.outputs.name.observe(self.friendName.observer)
      self.vm.outputs.projectsBackedText.observe(self.projectsBackedText.observer)
      self.vm.outputs.projectsCreatedText.observe(self.projectsCreatedText.observer)
      self.vm.outputs.hideFollowButton.observe(self.hideFollowButton.observer)
      self.vm.outputs.hideUnfollowButton.observe(self.hideUnfollowButton.observer)
      self.vm.outputs.hideProjectsCreated.observe(self.hideProjectsCreated.observer)
      self.vm.outputs.followButtonAccessibilityLabel.observe(self.followButtonAccessibilityLabel.observer)
      self.vm.outputs.unfollowButtonAccessibilityLabel.observe(self.unfollowButtonAccessibilityLabel.observer)
      self.vm.outputs.cellAccessibilityValue.observe(self.cellAccessibilityValue.observer)
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
    let brooklyn = Location.template
      |> Location.lens.displayableName .~ "Brooklyn, NY"

    let friend = User.template
      |> \.avatar.medium .~ "http://coolpic.com/cool.jpg"
      |> \.id .~ 145
      |> \.location .~ brooklyn
      |> \.name .~ "Jed"
      |> \.stats.backedProjectsCount .~ 20
      |> \.stats.createdProjectsCount .~ 2

    self.imageURL.assertValueCount(0)
    self.location.assertValueCount(0)
    self.friendName.assertValueCount(0)
    self.projectsBackedText.assertValueCount(0)
    self.projectsCreatedText.assertValueCount(0)
    self.hideProjectsCreated.assertValueCount(0)

    self.vm.inputs.configureWith(friend: friend)

    self.imageURL.assertValues(["http://coolpic.com/cool.jpg"])
    self.location.assertValues(["Brooklyn, NY"])
    self.friendName.assertValues(["Jed"])
    self.projectsBackedText.assertValues(["20 backed"])
    self.projectsCreatedText.assertValues(["2 created"])
    self.hideProjectsCreated.assertValues([false], "Show projects created text")
  }

  func testFriendDetails_Incomplete() async {
    let friend = User.template
      |> \.name .~ "Ned"

    self.location.assertValueCount(0)
    self.friendName.assertValueCount(0)
    self.projectsBackedText.assertValueCount(0)
    self.hideProjectsCreated.assertValueCount(0)

    self.vm.inputs.configureWith(friend: friend)

    self.imageURL.assertValueCount(1)
    self.location.assertValues([""], "Location emits empty string")
    self.friendName.assertValues(["Ned"])
    self.projectsBackedText.assertValues(["0 backed"], "Projects text emits")
    self.projectsCreatedText.assertValueCount(0, "Created projects does not emit")
    self.hideProjectsCreated.assertValues([true], "Hide projects created text")
  }

  func testFollowing_Friend() async {
    let friend = User.template
      |> \.name .~ "Jed"
      |> \.id .~ 245
      |> \.isFriend .~ true

    self.hideFollowButton.assertValueCount(0)
    self.hideUnfollowButton.assertValueCount(0)
    self.enableFollowButton.assertValueCount(0)
    self.enableUnfollowButton.assertValueCount(0)
    self.followButtonAccessibilityLabel.assertValueCount(0)
    self.unfollowButtonAccessibilityLabel.assertValueCount(0)
    self.cellAccessibilityValue.assertValueCount(0)

    self.vm.inputs.configureWith(friend: friend)

    self.hideFollowButton.assertValues([true], "Hide Follow Button")
    self.hideUnfollowButton.assertValues([false], "Show Unfollow Button")
    self.enableFollowButton.assertValues([false], "Disable Follow Button")
    self.enableUnfollowButton.assertValues([true], "Enable Unfollow Button")
    self.followButtonAccessibilityLabel
      .assertValues(["Follow Jed"], "Accessibility label assigned to the Button")
    self.unfollowButtonAccessibilityLabel.assertValues(
      ["Unfollow Jed"],
      "Accessibility label assigned to the Button"
    )
    self.cellAccessibilityValue.assertValues(["Followed"])

    XCTAssertEqual([], self.segmentTrackingClient.events)

    self.vm.inputs.unfollowButtonTapped()
    await self.feature.waitForOperations()

    self.hideFollowButton.assertValues([true], "Follow Button does not change")
    self.hideUnfollowButton.assertValues([false], "Unfollow Button does not change")
    self.enableFollowButton.assertValues([false], "Enable Follow Button does not emit")
    self.enableUnfollowButton.assertValues(
      [true, false, true],
      "Enable Unfollow Button emits false/true with loader"
    )

    self.followButtonAccessibilityLabel
      .assertValues(["Follow Jed"], "Accessibility label assigned to the Button")
    self.unfollowButtonAccessibilityLabel.assertValues(
      ["Unfollow Jed"],
      "Accessibility label assigned to the Button"
    )

    await self.advanceFriends()

    self.hideFollowButton.assertValues([true, false], "Show Follow Button")
    self.hideUnfollowButton.assertValues([false, true], "Hide Unfollow Button")
    self.enableFollowButton.assertValues([false, true], "Enable Follow Button")
    self.enableUnfollowButton.assertValues([true, false, true, false], "Disable Unfollow Button")
    self.cellAccessibilityValue.assertValues(["Followed", "Not followed"])

    self.vm.inputs.followButtonTapped()
    await self.feature.waitForOperations()

    self.hideFollowButton.assertValues([true, false], "Follow Button does not change")
    self.hideUnfollowButton.assertValues([false, true], "Unfollow Button does not change")
    self.enableFollowButton.assertValues(
      [false, true, false, true],
      "Enable Follow Button emits false/true with loader"
    )
    self.enableUnfollowButton.assertValues([true, false, true, false], "Unfollow Button does not change")

    await self.advanceFriends()

    self.hideFollowButton.assertValues([true, false, true], "Hide Follow Button")
    self.hideUnfollowButton.assertValues([false, true, false], "Show Unfollow Button")
    self.enableFollowButton.assertValues([false, true, false, true, false], "Disable Follow Button")
    self.enableUnfollowButton.assertValues([true, false, true, false, true], "Enable Unfollow Button")
    self.cellAccessibilityValue.assertValues(["Followed", "Not followed", "Followed"])

    self.vm.inputs.unfollowButtonTapped()
    await self.feature.waitForOperations()

    self.hideFollowButton.assertValues([true, false, true], "Follow Button does not change")
    self.hideUnfollowButton.assertValues([false, true, false], "Unfollow Button does not change")
    self.enableFollowButton
      .assertValues([false, true, false, true, false], "Enable Follow Button does not emit")
    self.enableUnfollowButton.assertValues(
      [true, false, true, false, true, false, true],
      "Enable Unfollow Button emits false/true with loader"
    )

    await self.advanceFriends()

    self.hideFollowButton.assertValues([true, false, true, false], "Show Follow Button")
    self.hideUnfollowButton.assertValues([false, true, false, true], "Hide Unfollow Button")
    self.enableFollowButton.assertValues([false, true, false, true, false, true], "Enable Follow Button")
    self.enableUnfollowButton.assertValues(
      [true, false, true, false, true, false, true, false],
      "Disable Unfollow Button"
    )

    // Accessibility labels remains the same through all the sequences of following/unfollowing
    self.followButtonAccessibilityLabel
      .assertValues(["Follow Jed"], "Accessibility label assigned to the Button")
    self.unfollowButtonAccessibilityLabel.assertValues(
      ["Unfollow Jed"],
      "Accessibility label assigned to the Button"
    )
  }

  func testFollowing_NonFriend() async {
    let friend = User.template
      |> \.name .~ "Zed"
      |> \.id .~ 200
      |> \.isFriend .~ false

    self.hideFollowButton.assertValueCount(0)
    self.hideUnfollowButton.assertValueCount(0)
    self.enableFollowButton.assertValueCount(0)
    self.enableUnfollowButton.assertValueCount(0)

    self.vm.inputs.configureWith(friend: friend)

    self.hideFollowButton.assertValues([false], "Show Follow Button")
    self.hideUnfollowButton.assertValues([true], "Hide Unfollow Button")
    self.enableFollowButton.assertValues([true], "Enable Follow Button")
    self.enableUnfollowButton.assertValues([false], "Disable Unfollow Button")
    self.followButtonAccessibilityLabel
      .assertValues(["Follow Zed"], "Accessibility label assigned to the Button")
    self.unfollowButtonAccessibilityLabel.assertValues(
      ["Unfollow Zed"],
      "Accessibility label assigned to the Button"
    )

    XCTAssertEqual([], self.segmentTrackingClient.events)

    self.vm.inputs.followButtonTapped()
    await self.feature.waitForOperations()

    self.hideFollowButton.assertValues([false], "Follow Button does not change")
    self.hideUnfollowButton.assertValues([true], "Unfollow Button does not change")
    self.enableFollowButton.assertValues(
      [true, false, true],
      "Enable Unfollow Button emits false/true with loader"
    )
    self.enableUnfollowButton.assertValues([false], "Enable Unfollow Button does not emit")

    await self.advanceFriends()

    self.hideFollowButton.assertValues([false, true], "Hide Follow Button")
    self.hideUnfollowButton.assertValues([true, false], "Show Unfollow Button")
    self.enableFollowButton.assertValues([true, false, true, false], "Disable Follow Button")
    self.enableUnfollowButton.assertValues([false, true], "Enable Unfollow Button")

    self.vm.inputs.unfollowButtonTapped()
    await self.feature.waitForOperations()

    self.hideFollowButton.assertValues([false, true], "Follow Button does not change")
    self.hideUnfollowButton.assertValues([true, false], "Unfollow Button does not change")
    self.enableFollowButton.assertValues([true, false, true, false], "Enable Follow Button does not emit")
    self.enableUnfollowButton.assertValues(
      [false, true, false, true],
      "Enable Unfollow Button emits false/true with loader"
    )

    await self.advanceFriends()

    self.hideFollowButton.assertValues([false, true, false], "Show Follow Button")
    self.hideUnfollowButton.assertValues([true, false, true], "Hide Unfollow Button")
    self.enableFollowButton.assertValues([true, false, true, false, true], "Enable Follow Button")
    self.enableUnfollowButton.assertValues([false, true, false, true, false], "Disable Unfollow Button")

    self.vm.inputs.followButtonTapped()
    await self.feature.waitForOperations()

    self.hideFollowButton.assertValues([false, true, false], "Follow Button does not change")
    self.hideUnfollowButton.assertValues([true, false, true], "Unfollow Button does not change")
    self.enableFollowButton.assertValues(
      [true, false, true, false, true, false, true],
      "Enable Follow Button emits false/true with loader"
    )
    self.enableUnfollowButton
      .assertValues([false, true, false, true, false], "Unfollow Button does not change")

    await self.advanceFriends()

    self.hideFollowButton.assertValues([false, true, false, true], "Hide Follow Button")
    self.hideUnfollowButton.assertValues([true, false, true, false], "Show Unfollow Button")
    self.enableFollowButton.assertValues(
      [true, false, true, false, true, false, true, false],
      "Disable Follow Button"
    )
    self.enableUnfollowButton.assertValues([false, true, false, true, false, true], "Enable Unfollow Button")
  }

  func testFollowFriend_WithError() async {
    let error = ErrorEnvelope(
      errorMessages: ["Something went wrong."],
      ksrCode: .UnknownCode,
      httpCode: 404,
      exception: nil
    )

    let friend = User.template
      |> \.name .~ "Zed"
      |> \.id .~ 200
      |> \.isFriend .~ false

    await withEnvironment(apiService: MockService(followFriendError: error)) {
      self.hideFollowButton.assertValueCount(0)
      self.hideUnfollowButton.assertValueCount(0)
      self.enableFollowButton.assertValueCount(0)
      self.enableUnfollowButton.assertValueCount(0)

      self.vm.inputs.configureWith(friend: friend)

      self.hideFollowButton.assertValues([false], "Show Follow Button")
      self.hideUnfollowButton.assertValues([true], "Hide Unfollow Button")
      self.enableFollowButton.assertValues([true], "Enable Follow Button")
      self.enableUnfollowButton.assertValues([false], "Disable Unfollow Button")

      XCTAssertEqual([], self.segmentTrackingClient.events)

      self.vm.inputs.followButtonTapped()
    await self.feature.waitForOperations()

      self.hideFollowButton.assertValues([false], "Follow Button does not change")
      self.hideUnfollowButton.assertValues([true], "Unfollow Button does not change")
      self.enableFollowButton.assertValues(
        [true, false, true],
        "Enable Unfollow Button emits false/true with loader"
      )
      self.enableUnfollowButton.assertValues([false], "Enable Unfollow Button does not emit")

      await self.advanceFriends()

      self.hideFollowButton.assertValues([false], "Follow Button does not emit")
      self.hideUnfollowButton.assertValues([true], "Unfollow Button does not emit")
      self.enableFollowButton.assertValues([true, false, true], "Follow Button remains enabled")
      self.enableUnfollowButton.assertValues([false], "Enable Unfollow Button does not emit")
    }
  }

  func testUnfollowFriend_WithError() async {
    let error = ErrorEnvelope(
      errorMessages: ["Something went wrong."],
      ksrCode: .UnknownCode,
      httpCode: 404,
      exception: nil
    )

    let friend = User.template
      |> \.name .~ "Jed"
      |> \.id .~ 245
      |> \.isFriend .~ true

    await withEnvironment(apiService: MockService(unfollowFriendError: error)) {
      self.hideFollowButton.assertValueCount(0)
      self.hideUnfollowButton.assertValueCount(0)
      self.enableFollowButton.assertValueCount(0)
      self.enableUnfollowButton.assertValueCount(0)

      self.vm.inputs.configureWith(friend: friend)

      self.hideFollowButton.assertValues([true], "Hide Follow Button")
      self.hideUnfollowButton.assertValues([false], "Show Unfollow Button")
      self.enableFollowButton.assertValues([false], "Disable Follow Button")
      self.enableUnfollowButton.assertValues([true], "Enable Unfollow Button")

      XCTAssertEqual([], self.segmentTrackingClient.events)

      self.vm.inputs.unfollowButtonTapped()
    await self.feature.waitForOperations()

      self.hideFollowButton.assertValues([true], "Follow Button does not change")
      self.hideUnfollowButton.assertValues([false], "Unfollow Button does not change")
      self.enableFollowButton.assertValues([false], "Enable Follow Button does not emit")
      self.enableUnfollowButton.assertValues(
        [true, false, true],
        "Enable Unfollow Button emits false/true with loader"
      )

      await self.advanceFriends()

      self.hideFollowButton.assertValues([true], "Follow Button does not emit")
      self.hideUnfollowButton.assertValues([false], "Unfollow Button does not emit")
      self.enableFollowButton.assertValues([false], "Follow Button remains disabled")
      self.enableUnfollowButton.assertValues([true, false, true], "Unfollow Button remains enabled")
    }
  }

  func testFriendDetails_NilCreatedProjectsCount() async {
    let friend = User.template
      |> \.stats.createdProjectsCount .~ nil

    self.hideProjectsCreated.assertValues([])

    self.vm.inputs.configureWith(friend: friend)

    self.hideProjectsCreated.assertValues([true])
  }
}
