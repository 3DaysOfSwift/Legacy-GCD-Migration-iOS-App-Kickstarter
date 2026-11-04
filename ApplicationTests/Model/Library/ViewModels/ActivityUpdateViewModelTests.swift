@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class ActivityUpdateViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  fileprivate let vm = ActivityUpdateViewModel()
  func testActivityUpdateDataEmits() {
    let project = Project.template
    let update = Update.template
    let activity = .template
      |> Activity.lens.project .~ project
      |> Activity.lens.update .~ update

    self.vm.configureWith(activity: activity)

    XCTAssertEqual(self.vm.body, update.body?.htmlStripped()?.truncated(maxLength: 300) ?? "")
    XCTAssertEqual(self.vm.projectName, project.name)
    XCTAssertEqual(self.vm.projectImageURL?.absoluteString, project.photo.med)
    XCTAssertEqual(self.vm.projectName, project.name)
    XCTAssertEqual(self.vm.sequenceTitle?.string,
      Strings.dashboard_activity_update_number_posted_time_count_days_ago(
        space: " ",
        update_number: Format.wholeNumber(activity.update?.sequence ?? 1),
        time_count_days_ago: Format.relative(secondsInUTC: activity.createdAt)
      ).htmlStripped() ?? ""
    )
    XCTAssertEqual(self.vm.title, update.title)
  }

  func testCellAccessibilityDataEmits() {
    let project = Project.template
    let update = Update.template
    let activity = .template
      |> Activity.lens.project .~ project
      |> Activity.lens.update .~ update

    self.vm.configureWith(activity: activity)

    XCTAssertEqual(self.vm.cellAccessibilityLabel,
      "\(project.name) "
        + (Strings.dashboard_activity_update_number_posted_time_count_days_ago(
          space: " ",
          update_number: Format.wholeNumber(activity.update?.sequence ?? 1),
          time_count_days_ago: Format.relative(secondsInUTC: activity.createdAt)
        ).htmlStripped() ?? "")
    , "Cell a11y label emits sequence title.")
  }

  func testTappedProjectImageButton() {
    let project = Project.template
    let update = Update.template
    let activity = .template
      |> Activity.lens.project .~ project
      |> Activity.lens.update .~ update

    self.vm.configureWith(activity: activity)
    XCTAssertEqual(self.vm.activity, activity)
  }
}

@MainActor
private final class ActivityUpdateDelegateProbe: ActivityUpdateCellDelegate {
  var activities: [Activity] = []
  func activityUpdateCellTappedProjectImage(activity: Activity) { self.activities.append(activity) }
}

@MainActor
final class ActivityUpdateCellActionTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testProjectTapUsesMostRecentlyConfiguredActivity() {
    let cell = ActivityUpdateCell(style: .default, reuseIdentifier: nil)
    for key in ["projectNameLabel", "updateSequenceLabel", "titleLabel", "bodyLabel"] {
      cell.setValue(UILabel(), forKey: key)
    }
    cell.setValue(UIButton(), forKey: "projectImageButton")
    cell.setValue(UIImageView(), forKey: "projectImageView")
    let delegate = ActivityUpdateDelegateProbe()
    cell.delegate = delegate
    let activity = Activity.template |> Activity.lens.project .~ Project.template
    cell.configureWith(value: activity)
    cell.tappedProjectImage()
    XCTAssertEqual(delegate.activities, [activity])
  }
}
