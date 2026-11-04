@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class ProjectTabCategoryDescriptionCellViewModelTests: XCTestCase {
  func testCategoryAndDescription() {
    let viewModel = ProjectTabCategoryDescriptionCellViewModel()
    let value = ProjectTabCategoryDescription(description: "Hello World", category: .environmentallyFriendlyFactories, id: 0)
    viewModel.configureWith(value: value)
    XCTAssertEqual(viewModel.categoryLabelText, ProjectTabCategory.environmentallyFriendlyFactories.rawValue)
    XCTAssertEqual(viewModel.descriptionLabelText, "Hello World")
  }
}
