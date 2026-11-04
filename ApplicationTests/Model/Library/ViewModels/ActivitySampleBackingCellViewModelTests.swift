@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class ActivitySampleBackingCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  internal let vm = ActivitySampleBackingCellViewModel()
  func testBackingDataEmits() {
    let backer = User.template
      |> \.name .~ "Best Friend"
      |> \.avatar.medium .~ "http://coolpic.com/cool.png"

    let creator = User.projectCreator
      |> \.name .~ "Super Cool Creator"

    let project = .template
      |> Project.lens.name .~ "Super Sweet Project Name"
      |> Project.lens.creator .~ creator

    let activity = .template
      |> Activity.lens.category .~ .backing
      |> Activity.lens.project .~ project
      |> Activity.lens.user .~ backer

    let display = self.vm.configureWith(activity: activity)

    XCTAssertEqual(display.title.string, "Best Friend backed Super Sweet Project Name by Super Cool Creator")
    XCTAssertEqual(display.imageURL?.absoluteString, backer.avatar.medium)
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
