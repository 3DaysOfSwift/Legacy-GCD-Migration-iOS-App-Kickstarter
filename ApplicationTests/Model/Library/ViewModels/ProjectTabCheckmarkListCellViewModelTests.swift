@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class ProjectTabCheckmarkListCellViewModelTests: XCTestCase {
  func testOptionsAndOrder() {
    let vm = ProjectTabCheckmarkListCellViewModel()
    vm.configureWith(value: .init(fundingForAiAttribution: true, fundingForAiConsent: true, fundingForAiOption: true))
    XCTAssertEqual(vm.categoryLabelText, "My project seeks funding for AI technology.")
    XCTAssertEqual(vm.descriptionOptionsText, [Strings.For_the_database_or_source_I_will_use(),
                                                Strings.The_owners_of_those_works(),
                                                Strings.There_is_or_will_be_an_opt()])
    vm.configureWith(value: .init(fundingForAiAttribution: false, fundingForAiConsent: false, fundingForAiOption: false))
    XCTAssertTrue(vm.descriptionOptionsText.isEmpty)
  }
}
