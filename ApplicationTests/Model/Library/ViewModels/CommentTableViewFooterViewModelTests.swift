@testable import Kickstarter_iOS
import KDS
import UIKit
import XCTest

@MainActor
final class CommentTableViewFooterViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testFooterStatesAndRetry() throws {
    let view = CommentTableViewFooterView(frame: .zero)
    let delegate = RetryDelegate()
    view.delegate = delegate
    let stack = try XCTUnwrap(view.subviews.compactMap { $0 as? UIStackView }.first)
    let indicator = try XCTUnwrap(stack.arrangedSubviews.compactMap { $0 as? UIActivityIndicatorView }.first)
    let button = try XCTUnwrap(stack.arrangedSubviews.compactMap { $0 as? UIButton }.first)
    view.configureWith(value: .activity)
    XCTAssertFalse(indicator.isHidden)
    XCTAssertTrue(button.isHidden)
    XCTAssertFalse(stack.isHidden)
    XCTAssertEqual(stack.layoutMargins.bottom, Styles.grid(2))
    view.configureWith(value: .error)
    XCTAssertTrue(indicator.isHidden)
    XCTAssertFalse(button.isHidden)
    XCTAssertEqual(stack.layoutMargins.bottom, Styles.grid(4))
    button.sendActions(for: .touchUpInside)
    XCTAssertEqual(delegate.count, 1)
    view.configureWith(value: .hidden)
    XCTAssertTrue(stack.isHidden)
    XCTAssertEqual(stack.layoutMargins.bottom, Styles.grid(2))
  }
}

@MainActor
private final class RetryDelegate: CommentTableViewFooterViewDelegate {
  var count = 0
  func commentTableViewFooterViewDidTapRetry(_ view: CommentTableViewFooterView) { self.count += 1 }
}
