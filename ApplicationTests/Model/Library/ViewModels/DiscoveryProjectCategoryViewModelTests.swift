@testable import Kickstarter_iOS
import XCTest

@MainActor
final class DiscoveryProjectCategoryViewModelTests: XCTestCase {
  func testCategoryViewAndReuse() {
    let vm = DiscoveryProjectCategoryViewModel()
    vm.configureWith(name: "Art", imageNameString: "icon--compass")
    XCTAssertEqual(vm.categoryNameText, "Art")
    XCTAssertEqual(vm.categoryImageName, "icon--compass")
    vm.configureWith(name: "Music", imageNameString: "icon--music")
    XCTAssertEqual(vm.categoryNameText, "Music")
    XCTAssertEqual(vm.categoryImageName, "icon--music")
  }
}
