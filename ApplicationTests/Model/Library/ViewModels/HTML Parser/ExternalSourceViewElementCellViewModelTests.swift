@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class ExternalElementSourceViewElementCellViewModelTests: XCTestCase {
  func testSourceAndHeightOnlyForNonemptyURL() {
    let vm = ExternalSourceViewElementCellViewModel()
    vm.configureWith(element: .init(embeddedURLString: "https://source.com", embeddedURLContentHeight: 32))
    XCTAssertEqual(vm.htmlText, "https://source.com")
    XCTAssertEqual(vm.contentHeight, 32)
    vm.configureWith(element: .init(embeddedURLString: "", embeddedURLContentHeight: 50))
    XCTAssertNil(vm.htmlText)
    XCTAssertNil(vm.contentHeight)
  }
}
