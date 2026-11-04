@testable import Kickstarter_iOS
import XCTest

@MainActor
final class CategorySelectionHeaderViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testAllContextsAndOptionalLabelEvents() {
    let vm = CategorySelectionHeaderViewModel()
    var steps: [String] = []
    var subtitles: [String] = []
    var titles: [String] = []
    var hidden: [Bool] = []
    vm.onStepText = { steps.append($0) }
    vm.onSubtitle = { subtitles.append($0) }
    vm.onTitle = { titles.append($0) }
    vm.onStepHidden = { hidden.append($0) }

    vm.configure(with: .categorySelection)
    vm.configure(with: .curatedProjects(.discovery))
    vm.configure(with: .curatedProjects(.onboarding))

    XCTAssertEqual(steps, ["Step 1 of 2", "Step 2 of 2"])
    XCTAssertEqual(subtitles, ["Select up to five from the options below."])
    XCTAssertEqual(titles, ["Which categories interest you?", "Check out these handpicked projects just for you.", "Check out these handpicked projects just for you."])
    XCTAssertEqual(hidden, [false, true, false])
  }
}
