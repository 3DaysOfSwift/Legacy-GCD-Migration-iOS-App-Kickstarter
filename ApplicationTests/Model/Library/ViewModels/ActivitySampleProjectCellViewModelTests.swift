@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class ActivitySampleProjectCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  internal let vm = ActivitySampleProjectCellViewModel()
  func testGoToActivity() {
    let activity = Activity.template

    _ = self.vm.configureWith(activity: activity)
    var events = 0
    self.vm.onGoToActivity = { events += 1 }
    self.vm.seeAllActivityTapped()
    XCTAssertEqual(events, 1)
  }

  func testProjectCancellationActivity() {
    let project = Project.template
    let activity = .template
      |> Activity.lens.category .~ .cancellation
      |> Activity.lens.project .~ project

    let display = self.vm.configureWith(activity: activity)

    XCTAssertEqual(display.accessibilityHint, Strings.Opens_project())
    XCTAssertEqual(display.imageURL?.absoluteString, project.photo.med)
    XCTAssertEqual(display.subtitle, Strings.activity_funding_canceled())
    XCTAssertEqual(display.title, project.name)
  }

  func testProjectFailureActivity() {
    let project = Project.template
    let activity = .template
      |> Activity.lens.category .~ .failure
      |> Activity.lens.project .~ project

    let display = self.vm.configureWith(activity: activity)

    XCTAssertEqual(display.accessibilityHint, Strings.Opens_project())
    XCTAssertEqual(display.imageURL?.absoluteString, project.photo.med)
    XCTAssertEqual(display.subtitle, Strings.activity_project_was_not_successfully_funded())
    XCTAssertEqual(display.title, project.name)
  }

  func testProjectLaunchActivity() {
    let user = User.template
    let project = Project.template
    let activity = .template
      |> Activity.lens.category .~ .launch
      |> Activity.lens.user .~ user
      |> Activity.lens.project .~ project

    let display = self.vm.configureWith(activity: activity)

    XCTAssertEqual(display.accessibilityHint, Strings.Opens_project())
    XCTAssertEqual(display.imageURL?.absoluteString, project.photo.med)
    XCTAssertEqual(display.subtitle, Strings.activity_user_name_launched_project(user_name: user.name))
    XCTAssertEqual(display.title, project.name)
  }

  func testProjectSuccessActivity() {
    let project = Project.template
    let activity = .template
      |> Activity.lens.category .~ .success
      |> Activity.lens.project .~ project

    let display = self.vm.configureWith(activity: activity)

    XCTAssertEqual(display.accessibilityHint, Strings.Opens_project())
    XCTAssertEqual(display.imageURL?.absoluteString, project.photo.med)
    XCTAssertEqual(display.subtitle, Strings.activity_successfully_funded())
    XCTAssertEqual(display.title, project.name)
  }

  func testProjectUpdateActivity() {
    let project = .template
      |> Project.lens.name .~ "Socks for Goats"
      |> Project.lens.photo.med .~ "http://goats.jpg"

    let update = .template
      |> Update.lens.sequence .~ 42
      |> Update.lens.title .~ "In production!"

    let activity = .template
      |> Activity.lens.category .~ .update
      |> Activity.lens.project .~ project
      |> Activity.lens.update .~ update

    let display = self.vm.configureWith(activity: activity)

    XCTAssertEqual(display.accessibilityHint, Strings.Opens_update())
    XCTAssertEqual(display.imageURL?.absoluteString, project.photo.med)
    XCTAssertEqual(display.title, project.name)
    XCTAssertEqual(display.subtitle,
        Strings.activity_posted_update_number_title(
          update_number: Format.wholeNumber(update.sequence),
          update_title: update.title
        )
    )
  }
}
