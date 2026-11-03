import UIKit
@testable import Kickstarter_iOS
import KDS

@testable import KsApi


import Prelude
import ReactiveExtensions_TestHelpers
import SnapshotTesting
import XCTest

internal final class CommentCellHeaderStackViewTests: TestCase {
  private let commentCellHeaderStackView =
    CommentCellHeaderStackView(frame: CGRect(
      x: 0,
      y: 0,
      width: 375,
      height: Styles.grid(9)
    ))

  override func setUp() async throws {
    try await super.setUp()
    self.commentCellHeaderStackView.layer.backgroundColor = LegacyColors.ksr_white.uiColor().cgColor
    UIView.setAnimationsEnabled(false)
  }

  override func tearDown() async throws {
    UIView.setAnimationsEnabled(true)
    try await super.tearDown()
  }

  func testAuthorBadge_Backer() {
    self.commentCellHeaderStackView
      .configureWith(comment: Comment.backerTemplate)

    assertSnapshot(
      matching: self.commentCellHeaderStackView,
      as: .image(perceptualPrecision: 0.99),
      named: "state_AuthorBadge_Is_Backer"
    )
  }

  func testAuthorBadge_Collaborator() {
    self.commentCellHeaderStackView
      .configureWith(comment: Comment.collaboratorTemplate)

    assertSnapshot(
      matching: self.commentCellHeaderStackView,
      as: .image(perceptualPrecision: 0.99),
      named: "state_AuthorBadge_Is_Colaborator"
    )
  }

  func testAuthorBadge_Creator() {
    self.commentCellHeaderStackView
      .configureWith(comment: Comment.template)

    assertSnapshot(
      matching: self.commentCellHeaderStackView,
      as: .image(perceptualPrecision: 0.99),
      named: "state_AuthorBadge_Is_Creator"
    )
  }

  func testAuthorBadge_SuperBacker() {
    self.commentCellHeaderStackView
      .configureWith(comment: Comment.superbackerTemplate)

    assertSnapshot(
      matching: self.commentCellHeaderStackView,
      as: .image(perceptualPrecision: 0.99),
      named: "state_AuthorBadge_Is_Superbacker"
    )
  }

  func testAuthorBadge_You() {
    self.commentCellHeaderStackView
      .configureWith(comment: Comment.failedTemplate)

    assertSnapshot(
      matching: self.commentCellHeaderStackView,
      as: .image(perceptualPrecision: 0.99),
      named: "state_AuthorBadge_Is_You"
    )
  }
}
