@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class ThanksCategoryCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = ThanksCategoryCellViewModel()

  func testNotifyDelegate() {
    let category = Category.template

    var selected: KsApi.Category?
    self.vm.onGoToDiscovery = { selected = $0 }
    self.vm.seeAllProjectsButtonTapped()
    XCTAssertNil(selected)
    _ = self.vm.configureWith(category: category)
    self.vm.seeAllProjectsButtonTapped()
    XCTAssertEqual(selected?.id, category.id)
  }

  func testSeeAllProjectCategoryButtonTitle() {
    let category = Category.template
      |> Category.lens.name .~ "Art"

    XCTAssertEqual(self.vm.configureWith(category: category), "See all Art projects")
  }
}
