@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
internal final class MessageCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testDisplayAndHeaderTapUseConfiguredMessage() {
    let vm = MessageCellViewModel()
    var displays: [MessageCellViewModel.Display] = []
    var senders: [User] = []
    vm.onDisplay = { displays.append($0) }
    vm.onSender = { senders.append($0) }
    vm.cellHeaderTapped()
    XCTAssertTrue(senders.isEmpty)

    let message = Message.template
    vm.configureWith(message: message)
    vm.cellHeaderTapped()

    XCTAssertEqual(displays.count, 1)
    XCTAssertEqual(displays.first?.avatarURL, URL(string: message.sender.avatar.large ?? message.sender.avatar.medium))
    XCTAssertEqual(displays.first?.name, message.sender.name)
    XCTAssertEqual(displays.first?.body, message.body)
    XCTAssertEqual(displays.first?.timestamp, Format.date(secondsInUTC: message.createdAt, dateStyle: .short, timeStyle: .short))
    XCTAssertEqual(displays.first?.timestampAccessibilityLabel, Format.date(secondsInUTC: message.createdAt, dateStyle: .long, timeStyle: .short))
    XCTAssertEqual(senders, [message.sender])
  }
}
