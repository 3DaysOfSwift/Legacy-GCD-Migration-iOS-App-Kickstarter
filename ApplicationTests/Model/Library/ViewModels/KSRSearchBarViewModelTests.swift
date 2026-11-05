@testable import Kickstarter_iOS
import XCTest

@MainActor
final class KSRSearchBarViewModelTests: XCTestCase {
  func testFocusAndReturn() {
    let model = KSRSearchBarViewModel()
    var focus: [Bool] = []
    var resignCount = 0
    model.onFocusChanged = { focus.append($0) }
    model.onResign = { resignCount += 1 }
    model.searchFieldDidBeginEditing()
    model.searchTextEditingDidEnd()
    XCTAssertEqual(focus, [true, false])
    XCTAssertEqual(resignCount, 1)
  }

  func testClearAndCancel() {
    let model = KSRSearchBarViewModel()
    var texts: [String] = []
    var resignCount = 0
    model.onTextChanged = { texts.append($0) }
    model.onResign = { resignCount += 1 }
    model.searchTextChanged("hello world")
    model.clearSearchText()
    XCTAssertEqual(texts, ["hello world", ""])
    XCTAssertEqual(resignCount, 0)
    model.searchTextChanged("again")
    model.cancelButtonPressed()
    XCTAssertEqual(texts, ["hello world", "", "again", ""])
    XCTAssertEqual(resignCount, 1)
  }
}
