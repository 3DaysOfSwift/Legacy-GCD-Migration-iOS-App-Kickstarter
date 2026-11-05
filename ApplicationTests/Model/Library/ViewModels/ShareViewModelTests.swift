@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest
import UIKit
@MainActor
final class ShareViewModelOwnershipTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testShareRequiresConfigurationAndPreservesSourceView() {
    let model = ShareViewModel()
    var sheets: [(UIActivityViewController, UIView?)] = []
    model.onShareSheet = { sheets.append(($0, $1)) }
    model.shareButtonTapped()
    XCTAssertTrue(sheets.isEmpty)
    let source = UIView()
    model.configureWith(shareContext: .project(.template), shareContextView: source)
    XCTAssertTrue(sheets.isEmpty)
    model.shareButtonTapped()
    XCTAssertEqual(sheets.count, 1)
    XCTAssertTrue(sheets.first?.1 === source)
  }

  func testRepeatedShareUsesLatestSourceView() {
    let model = ShareViewModel()
    var sources: [UIView?] = []
    model.onShareSheet = { _, source in sources.append(source) }
    let first = UIView()
    let second = UIView()
    model.configureWith(shareContext: .discovery(.template), shareContextView: first)
    model.shareButtonTapped()
    model.configureWith(shareContext: .project(.template), shareContextView: second)
    model.shareButtonTapped()
    XCTAssertEqual(sources.count, 2)
    XCTAssertTrue(sources.first! === first)
    XCTAssertTrue(sources.last! === second)
  }
}
