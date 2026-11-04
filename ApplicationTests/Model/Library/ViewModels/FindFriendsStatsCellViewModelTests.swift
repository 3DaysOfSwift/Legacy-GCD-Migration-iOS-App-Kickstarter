@testable import Kickstarter_iOS
@testable import KsApi
import Prelude
import XCTest

@MainActor
final class FindFriendsStatsCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testTextAndFollowAllAfterReuse() {
    let vm = FindFriendsStatsCellViewModel()
    XCTAssertNil(vm.countForFollowAllAction())
    let small = FriendStatsEnvelope.template
      |> FriendStatsEnvelope.lens.stats.friendProjectsCount .~ 3
      |> FriendStatsEnvelope.lens.stats.remoteFriendsCount .~ 2
    vm.configureWith(stats: small, source: .settings)
    XCTAssertEqual(vm.hideFollowAllButton, true)
    XCTAssertEqual(vm.countForFollowAllAction(), 2)
    let large = FriendStatsEnvelope.template
      |> FriendStatsEnvelope.lens.stats.friendProjectsCount .~ 450
      |> FriendStatsEnvelope.lens.stats.remoteFriendsCount .~ 45
    vm.configureWith(stats: large, source: .settings)
    XCTAssertEqual(vm.backedProjectsCountText, "450")
    XCTAssertEqual(vm.followAllText, "Follow all 45 friends")
    XCTAssertEqual(vm.friendsCountText, "45")
    XCTAssertEqual(vm.hideFollowAllButton, false)
    XCTAssertEqual(vm.countForFollowAllAction(), 45)
    let popular = FriendStatsEnvelope.template
      |> FriendStatsEnvelope.lens.stats.friendProjectsCount .~ 1_200
      |> FriendStatsEnvelope.lens.stats.remoteFriendsCount .~ 1_000
    vm.configureWith(stats: popular, source: .settings)
    XCTAssertEqual(vm.countForFollowAllAction(), 1_000)
    XCTAssertEqual(vm.hideFollowAllButton, false)
  }
}
