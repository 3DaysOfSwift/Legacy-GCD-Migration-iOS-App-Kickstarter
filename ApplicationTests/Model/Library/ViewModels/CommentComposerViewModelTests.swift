@testable import Kickstarter_iOS
import Foundation
import XCTest

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

  func testCharacterLimitAndInvalidUnicodeRanges() {
    let full = String(repeating: "a", count: CommentComposerConstant.characterLimit)
    XCTAssertFalse(self.vm.textViewShouldChange(text: full, in: NSRange(location: full.utf16.count, length: 0), replacementText: "x"))
    XCTAssertTrue(self.vm.textViewShouldChange(text: full, in: NSRange(location: 0, length: 1), replacementText: "b"))
    XCTAssertFalse(self.vm.textViewShouldChange(text: "😀", in: NSRange(location: 3, length: 1), replacementText: "x"))
  }
}
