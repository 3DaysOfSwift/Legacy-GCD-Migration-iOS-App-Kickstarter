@testable import Kickstarter_iOS
import Foundation
import XCTest

@MainActor
final class PledgeDisclaimerViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testLinkTapForwardsTheURL() {
    let viewModel = PledgeDisclaimerViewModel()
    var received: [URL] = []
    viewModel.onLinkTapped = { received.append($0) }
    let url = URL(string: "http://www.kickstarter.com")!
    viewModel.linkTapped(url: url)
    XCTAssertEqual(received, [url])
  }
}
