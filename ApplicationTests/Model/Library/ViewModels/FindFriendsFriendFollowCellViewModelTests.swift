@testable import Kickstarter_iOS
@testable import KsApi
import Prelude
import XCTest

@MainActor
final class FindFriendsFriendFollowCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = FriendsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
    makeProvider: { AsyncFriendsProvider(service: AppEnvironment.current.apiService) }, sleep: { _ in }
  )
  private lazy var vm = FindFriendsFriendFollowCellViewModel(feature: self.feature, delay: {})

  override func tearDown() async throws {
    self.feature.reset()
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  func testCompleteAndIncompleteFriendPresentation() {
    let location = Location.template |> Location.lens.displayableName .~ "Brooklyn, NY"
    let friend = User.template
      |> \.avatar.medium .~ "http://coolpic.com/cool.jpg"
      |> \.location .~ location
      |> \.name .~ "Jed"
      |> \.stats.backedProjectsCount .~ 20
      |> \.stats.createdProjectsCount .~ 2
    self.vm.configureWith(friend: friend)
    XCTAssertEqual(self.vm.imageURL?.absoluteString, "http://coolpic.com/cool.jpg")
    XCTAssertEqual(self.vm.location, "Brooklyn, NY")
    XCTAssertEqual(self.vm.name, "Jed")
    XCTAssertEqual(self.vm.projectsBackedText, "20 backed")
    XCTAssertEqual(self.vm.projectsCreatedText, "2 created")
    XCTAssertEqual(self.vm.hideProjectsCreated, false)
    self.vm.configureWith(friend: User.template |> \.name .~ "Ned")
    XCTAssertEqual(self.vm.location, "")
    XCTAssertEqual(self.vm.projectsBackedText, "0 backed")
    XCTAssertEqual(self.vm.hideProjectsCreated, true)
  }

  func testFollowAndUnfollowState() async {
    let friend = User.template |> \.name .~ "Zed" |> \.isFriend .~ false
    self.vm.configureWith(friend: friend)
    XCTAssertEqual(self.vm.hideFollowButton, false)
    XCTAssertEqual(self.vm.enableFollowButton, true)
    XCTAssertEqual(self.vm.followButtonAccessibilityLabel, "Follow Zed")
    XCTAssertEqual(self.vm.unfollowButtonAccessibilityLabel, "Unfollow Zed")
    XCTAssertEqual(self.vm.cellAccessibilityValue, "Not followed")
    self.vm.followButtonTapped()
    XCTAssertEqual(self.vm.enableFollowButton, false)
    await self.vm.waitForObservations()
    XCTAssertEqual(self.vm.hideFollowButton, true)
    XCTAssertEqual(self.vm.hideUnfollowButton, false)
    XCTAssertEqual(self.vm.cellAccessibilityValue, "Followed")
    self.vm.unfollowButtonTapped()
    XCTAssertEqual(self.vm.enableUnfollowButton, false)
    await self.vm.waitForObservations()
    XCTAssertEqual(self.vm.hideFollowButton, false)
    XCTAssertEqual(self.vm.hideUnfollowButton, true)
  }
  func testFollowErrorRestoresButtonWithoutChangingFriendship() async {
    let error = ErrorEnvelope(errorMessages: ["Something went wrong."], ksrCode: .UnknownCode, httpCode: 404, exception: nil)
    await withEnvironment(apiService: MockService(followFriendError: error)) {
      self.vm.configureWith(friend: User.template |> \.isFriend .~ false)
      self.vm.followButtonTapped()
      XCTAssertEqual(self.vm.enableFollowButton, false)
      await self.vm.waitForObservations()
      XCTAssertEqual(self.vm.enableFollowButton, true)
      XCTAssertEqual(self.vm.hideFollowButton, false)
      XCTAssertEqual(self.vm.hideUnfollowButton, true)
    }
  }

  func testUnfollowErrorRestoresButtonWithoutChangingFriendship() async {
    let error = ErrorEnvelope(errorMessages: ["Something went wrong."], ksrCode: .UnknownCode, httpCode: 404, exception: nil)
    await withEnvironment(apiService: MockService(unfollowFriendError: error)) {
      self.vm.configureWith(friend: User.template |> \.isFriend .~ true)
      self.vm.unfollowButtonTapped()
      XCTAssertEqual(self.vm.enableUnfollowButton, false)
      await self.vm.waitForObservations()
      XCTAssertEqual(self.vm.enableUnfollowButton, true)
      XCTAssertEqual(self.vm.hideFollowButton, true)
      XCTAssertEqual(self.vm.hideUnfollowButton, false)
    }
  }

}
