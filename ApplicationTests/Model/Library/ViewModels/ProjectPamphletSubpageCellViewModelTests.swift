@testable import Kickstarter_iOS
import XCTest

@MainActor
final class ProjectPamphletSubpageCellViewModelTests: XCTestCase {
  func testCommentsUpdatesAndSeparators() {
    let viewModel = ProjectPamphletSubpageCellViewModel()
    viewModel.configureWith(subpage: .comments(123, .first))
    XCTAssertEqual(viewModel.labelText, Strings.project_menu_buttons_comments())
    XCTAssertEqual(viewModel.countLabelText, "123")
    XCTAssertFalse(viewModel.topSeparatorViewHidden)
    XCTAssertFalse(viewModel.separatorViewHidden)
    viewModel.configureWith(subpage: .updates(nil, .middle))
    XCTAssertEqual(viewModel.labelText, Strings.project_menu_buttons_updates())
    XCTAssertEqual(viewModel.countLabelText, "0")
    XCTAssertTrue(viewModel.topSeparatorViewHidden)
    XCTAssertFalse(viewModel.separatorViewHidden)
    viewModel.configureWith(subpage: .reportProject(.last))
    XCTAssertTrue(viewModel.separatorViewHidden)
    XCTAssertEqual(viewModel.labelText, Strings.project_menu_buttons_updates())
  }
}
