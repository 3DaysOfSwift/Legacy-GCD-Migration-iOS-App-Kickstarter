@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class ActivitySampleFollowCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  internal let vm = ActivitySampleFollowCellViewModel()
  func testFriendFollowDataEmits() {
    let user = User.template
      |> \.name .~ "Cool Person"
      |> \.avatar.medium .~ "http://coolpic.com/cool.png"

    let activity = .template
      |> Activity.lens.category .~ .follow
      |> Activity.lens.user .~ user

    let display = self.vm.configureWith(activity: activity)

    XCTAssertEqual(display.text, Strings.activity_user_name_is_now_following_you(user_name: user.name))
    XCTAssertEqual(display.imageURL?.absoluteString, user.avatar.medium)
  }

  func testGoToActivity() {
    let activity = Activity.template

    _ = self.vm.configureWith(activity: activity)
    var events = 0
    self.vm.onGoToActivity = { events += 1 }
    self.vm.seeAllActivityTapped()
    XCTAssertEqual(events, 1)
  }
}
