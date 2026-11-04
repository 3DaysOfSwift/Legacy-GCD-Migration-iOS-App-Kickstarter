@testable import Kickstarter_iOS
@testable import KsApi
import Prelude
import XCTest

@MainActor
final class MessageThreadCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = MessageThreadCellViewModel()

  func testThreadPresentationAndReplyIndicator() {
    let thread = MessageThread.template
    let state = self.vm.configureWith(messageThread: thread)
    XCTAssertEqual(state.messageBody, thread.lastMessage.body.replacingOccurrences(of: "\n", with: " "))
    XCTAssertEqual(state.participantName, thread.participant.name)
    XCTAssertEqual(state.projectName, thread.project.name)
    XCTAssertTrue(state.replyIndicatorHidden)
    XCTAssertFalse(state.unreadIndicatorHidden)
    XCTAssertFalse(state.date.isEmpty)
    XCTAssertFalse(state.dateAccessibilityLabel.isEmpty)
    withEnvironment(currentUser: thread.lastMessage.sender) {
      XCTAssertFalse(self.vm.configureWith(messageThread: thread).replyIndicatorHidden)
    }
  }

  func testSelectingMarksOnlyCurrentThreadReadAndPersistsOnReuse() {
    let thread = .template |> MessageThread.lens.unreadMessagesCount .~ 1
    XCTAssertFalse(self.vm.configureWith(messageThread: thread).unreadIndicatorHidden)
    self.vm.setSelected(true)
    self.vm.setSelected(false)
    let another = .template |> MessageThread.lens.unreadMessagesCount .~ 3
      |> MessageThread.lens.id .~ (thread.id + 1)
    XCTAssertFalse(self.vm.configureWith(messageThread: another).unreadIndicatorHidden)
    XCTAssertTrue(self.vm.configureWith(messageThread: thread).unreadIndicatorHidden)
  }
}
