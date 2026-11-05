@testable import Kickstarter_iOS
import UIKit
import XCTest

@MainActor
final class CategoryCollectionViewSectionHeaderViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testConfiguringUpdatesHeaderText() {
    let header = CategoryCollectionViewSectionHeaderView(frame: .zero)
    header.configure(with: "Ceramics")
    let label = header.subviews.compactMap { $0 as? UILabel }.first
    XCTAssertEqual(label?.text, "Ceramics")
    header.configure(with: "Painting")
    XCTAssertEqual(label?.text, "Painting")
  }
}
