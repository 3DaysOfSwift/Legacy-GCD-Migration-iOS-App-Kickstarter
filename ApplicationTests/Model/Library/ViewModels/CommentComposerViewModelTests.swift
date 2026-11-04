@testable import Kickstarter_iOS
import Foundation
import UIKit
import XCTest

@MainActor
final class CommentComposerViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = CommentComposerViewModel()

  func testInputVisibilityAndTrimmedSubmission() {
    XCTAssertFalse(self.vm.placeholderHidden)
    XCTAssertTrue(self.vm.postButtonHidden)
    XCTAssertNil(self.vm.textToSubmit())
    self.vm.bodyTextDidChange("   ")
    XCTAssertTrue(self.vm.placeholderHidden)
    XCTAssertTrue(self.vm.postButtonHidden)
    self.vm.bodyTextDidChange("  hello world  ")
    XCTAssertFalse(self.vm.postButtonHidden)
    XCTAssertEqual(self.vm.textToSubmit(), "hello world")
    self.vm.resetInput()
    XCTAssertNil(self.vm.bodyText)
    XCTAssertFalse(self.vm.placeholderHidden)
    XCTAssertTrue(self.vm.postButtonHidden)
  }

  func testComposerSubmitsTrimmedTextAndResetsInput() throws {
    let view = CommentComposerView(frame: .zero)
    let delegate = ComposerDelegate()
    view.delegate = delegate
    view.configure(with: (avatarURL: nil, canPostComment: true, hidden: false, becomeFirstResponder: false))
    let container = try XCTUnwrap(self.descendants(view).compactMap { $0 as? CommentInputContainerView }.first)
    XCTAssertTrue(container.postButton.isHidden)
    XCTAssertFalse(container.placeholderLabel.isHidden)
    container.inputTextView.text = "  a comment  "
    view.textViewDidChange(container.inputTextView)
    XCTAssertFalse(container.postButton.isHidden)
    XCTAssertTrue(container.placeholderLabel.isHidden)
    container.postButton.sendActions(for: .touchUpInside)
    XCTAssertEqual(delegate.submitted, ["a comment"])
    view.resetInput()
    XCTAssertTrue(container.inputTextView.text.isEmpty)
    XCTAssertTrue(container.postButton.isHidden)
    XCTAssertFalse(container.placeholderLabel.isHidden)
  }

  private func descendants(_ view: UIView) -> [UIView] {
    view.subviews.flatMap { [$0] + self.descendants($0) }
  }

  func testCharacterLimitAndInvalidUnicodeRanges() {
    let full = String(repeating: "a", count: CommentComposerConstant.characterLimit)
    XCTAssertFalse(self.vm.textViewShouldChange(text: full, in: NSRange(location: full.utf16.count, length: 0), replacementText: "x"))
    XCTAssertTrue(self.vm.textViewShouldChange(text: full, in: NSRange(location: 0, length: 1), replacementText: "b"))
    XCTAssertFalse(self.vm.textViewShouldChange(text: "😀", in: NSRange(location: 3, length: 1), replacementText: "x"))
  }
}

@MainActor
private final class ComposerDelegate: CommentComposerViewDelegate {
  var submitted: [String] = []
  func commentComposerView(_ view: CommentComposerView, didSubmitText text: String) {
    self.submitted.append(text)
  }
}
