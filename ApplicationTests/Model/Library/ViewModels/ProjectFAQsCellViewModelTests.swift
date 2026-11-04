@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class ProjectFAQsCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  func testFAQAndExpansion() {
    let vm = ProjectFAQsCellViewModel()
    let faq = ProjectFAQ(answer: "answer 1", question: "question 1", id: 0, createdAt: 1_475_361_315)
    vm.configureWith(value: (faq, false))
    XCTAssertEqual(vm.answer, "answer 1")
    XCTAssertEqual(vm.question, "question 1")
    XCTAssertFalse(vm.isExpanded)
    XCTAssertEqual(vm.updatedText, "Updated Oct 1, 2016")
    vm.configureWith(value: (faq, true))
    XCTAssertTrue(vm.isExpanded)
  }
}
