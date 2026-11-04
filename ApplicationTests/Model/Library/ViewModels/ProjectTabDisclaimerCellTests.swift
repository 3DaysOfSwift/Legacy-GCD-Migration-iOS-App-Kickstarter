@testable import Kickstarter_iOS
import UIKit
import XCTest

@MainActor
final class ProjectTabDisclaimerCellTests: XCTestCase {
  func testLinkIsDeliveredToDelegate() {
    let cell = ProjectTabDisclaimerCell(style: .default, reuseIdentifier: nil)
    let delegate = DisclaimerDelegate()
    cell.delegate = delegate
    cell.configureWith(value: .aiDisclosure)
    let url = URL(string: "https://example.com")!
    XCTAssertFalse(cell.textView(UITextView(), shouldInteractWith: url, in: NSRange(location: 0, length: 0),
                                 interaction: .invokeDefaultAction))
    XCTAssertEqual(delegate.url, url)
  }
}

@MainActor
private final class DisclaimerDelegate: ProjectTabDisclaimerCellDelegate {
  var url: URL?
  func projectTabDisclaimerCell(_ cell: ProjectTabDisclaimerCell, didTapURL: URL) { self.url = didTapURL }
}
