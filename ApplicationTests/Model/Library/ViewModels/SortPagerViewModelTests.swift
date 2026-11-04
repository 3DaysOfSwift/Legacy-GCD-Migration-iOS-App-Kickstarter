@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class SortPagerViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testSelectionStylesAndDelegateAcrossAppearances() {
    let vm = SortPagerViewModel()
    let sorts: [DiscoveryParams.Sort] = [.magic, .popular, .newest, .endingSoon]
    var created: [[DiscoveryParams.Sort]] = []
    var selected: [Int] = []
    var delegates: [DiscoveryParams.Sort] = []
    var styles: [(Int?, Bool)] = []
    var pinned: [(Int, Bool)] = []
    vm.createSortButtons = { created.append($0) }
    vm.setSelectedButton = { selected.append($0) }
    vm.notifyDelegateOfSelectedSort = { delegates.append($0) }
    vm.updateSortStyle = { id, _, animated in styles.append((id, animated)) }
    vm.pinSelectedIndicatorToPage = { pinned.append(($0, $1)) }
    vm.configureWith(sorts: sorts)
    vm.viewWillAppear()
    vm.viewDidAppear()
    vm.sortButtonTapped(index: 2)
    vm.select(sort: .popular)
    vm.updateStyle(categoryId: 3)
    vm.viewWillAppear()
    XCTAssertEqual(created, [sorts])
    XCTAssertEqual(selected, [0, 2, 1])
    XCTAssertEqual(delegates, [.newest])
    XCTAssertEqual(styles.count, 2)
    XCTAssertNil(styles[0].0)
    XCTAssertFalse(styles[0].1)
    XCTAssertEqual(styles[1].0, 3)
    XCTAssertTrue(styles[1].1)
    XCTAssertEqual(pinned.map(\.0), [0, 1])
    XCTAssertEqual(pinned.map(\.1), [false, true])
  }

  func testRotationPinsCurrentPageAndRevealsAfterDelay() async {
    let vm = SortPagerViewModel(sleep: {})
    var pinned: [(Int, Bool)] = []
    vm.pinSelectedIndicatorToPage = { pinned.append(($0, $1)) }
    vm.configureWith(sorts: [.magic, .popular])
    vm.viewWillAppear()
    XCTAssertTrue(vm.indicatorViewIsHidden)
    vm.select(sort: .popular)
    vm.willRotateToInterfaceOrientation()
    vm.didRotateFromInterfaceOrientation()
    XCTAssertTrue(vm.indicatorViewIsHidden)
    await Task.yield()
    XCTAssertFalse(vm.indicatorViewIsHidden)
    XCTAssertEqual(pinned.map(\.0), [1, 1])
    XCTAssertEqual(pinned.map(\.1), [true, false])
  }

  func testConfigurationAfterAppearanceInitializesButtons() {
    let vm = SortPagerViewModel()
    var created: [[DiscoveryParams.Sort]] = []
    vm.createSortButtons = { created.append($0) }
    vm.viewWillAppear()
    vm.configureWith(sorts: [.magic, .popular])
    XCTAssertEqual(created, [[.magic, .popular]])
  }
}
