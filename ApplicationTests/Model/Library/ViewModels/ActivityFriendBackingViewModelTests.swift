@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class ActivityFriendBackingViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  fileprivate let vm = ActivityFriendBackingViewModel()

  func testFrientTitle_ParentCategory() {
    let games = Project.Category.template
      |> \.id .~ 12
      |> \.name .~ "Games"

    self.vm.configureWith(
      activity:
      .template
        |> Activity.lens.category .~ .backing
        |> Activity.lens.project .~ (.template |> \.category .~ games)
    )

    XCTAssertEqual(self.vm.friendTitle.string, "Blob backed a Games project.")
  }

  func testFrientTitle_SubCategory() {
    let illustration = Project.Category.template
      |> \.id .~ 25
      |> \.name .~ "Illustration"
      |> \.parentId .~ 1
      |> \.parentName .~ "Art"

    self.vm.configureWith(
      activity:
      .template
        |> Activity.lens.category .~ .backing
        |> Activity.lens.project .~ (.template |> \.category .~ illustration)
    )

    XCTAssertEqual(self.vm.friendTitle.string, "Blob backed an Art project.")
  }

  func testAccessibility() {
    let games = Project.Category.template
      |> \.id .~ 12
      |> \.name .~ "Games"

    self.vm.configureWith(
      activity:
      .template
        |> Activity.lens.category .~ .backing
        |> Activity.lens.project .~ (.template |> \.category .~ games)
    )

    XCTAssertEqual(self.vm.cellAccessibilityLabel, "Blob backed a Games project., The Project")
  }
  func testProgressIsClampedAndRetainedWhenReusedWithoutProject() {
    let project = Project.template |> Project.lens.stats.fundingProgress .~ 2.5
    self.vm.configureWith(activity: Activity.template |> Activity.lens.project .~ project)
    XCTAssertEqual(self.vm.fundingProgressPercentage, 1)
    self.vm.configureWith(activity: Activity.template |> Activity.lens.project .~ nil)
    XCTAssertEqual(self.vm.fundingProgressPercentage, 1)
    XCTAssertEqual(self.vm.projectName, "")
  }

}
