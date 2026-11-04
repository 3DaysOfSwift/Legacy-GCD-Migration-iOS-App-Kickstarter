@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class CategoryPillCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  func testConfigurationSelectionAndTap() {
    let vm = CategoryPillCellViewModel()
    var titles: [String] = []
    var selections: [Bool] = []
    var tapped: [(IndexPath, KsApi.Category)] = []
    vm.onTitle = { titles.append($0) }
    vm.onSelection = { selections.append($0) }
    vm.onTap = { tapped.append(($0, $1)) }
    let index = IndexPath(item: 0, section: 0)

    vm.pillCellTapped()
    vm.configure(with: ("title", .art, nil))
    vm.pillCellTapped()
    XCTAssertTrue(tapped.isEmpty)
    vm.configure(with: ("updated", .art, index))
    vm.setIsSelected(selected: true)
    vm.setIsSelected(selected: true)
    vm.setIsSelected(selected: false)
    vm.pillCellTapped()

    XCTAssertEqual(titles, ["title", "updated"])
    XCTAssertEqual(selections, [true, false])
    XCTAssertEqual(tapped.count, 1)
    XCTAssertEqual(tapped.first?.0, index)
    XCTAssertEqual(tapped.first?.1, .art)
  }
}
