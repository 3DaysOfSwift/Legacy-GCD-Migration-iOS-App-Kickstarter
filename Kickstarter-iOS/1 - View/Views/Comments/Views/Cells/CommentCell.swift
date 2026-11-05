import KDS
import KsApi

import Prelude
import UIKit

@MainActor
protocol CommentCellDelegate: AnyObject {
  func commentCellDidTapHeader(_ cell: CommentCell, _ author: Comment.Author)
  func commentCellDidTapReply(_ cell: CommentCell, comment: Comment)
  func commentCellDidTapViewReplies(_ cell: CommentCell, comment: Comment)
}

final class CommentCell: UITableViewCell, ValueCell {
  // MARK: - Properties

  private lazy var bodyTextView: UITextView = { UITextView(frame: .zero) }()
  private lazy var bottomRowStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var commentCellHeaderStackView: CommentCellHeaderStackView = {
    CommentCellHeaderStackView(frame: .zero)
  }()

  weak var delegate: CommentCellDelegate?

  private lazy var flagButton = { UIButton(frame: .zero) }()
  private lazy var postedButton = { UIButton(frame: .zero) }()
  private lazy var replyButton = { UIButton(frame: .zero) }()
  private lazy var viewRepliesView: ViewRepliesView = {
    ViewRepliesView(frame: .zero)
      |> \.isUserInteractionEnabled .~ true
  }()

  private let viewModel = CommentCellViewModel()

  private lazy var rootStackView = {
    UIStackView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  // MARK: - Lifecycle

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)

    self.bindStyles()
    self.configureViews()
    self.bindViewModel()

    self.replyButton.addTarget(self, action: #selector(self.replyButtonTapped), for: .touchUpInside)
    self.commentCellHeaderStackView.addGestureRecognizer(UITapGestureRecognizer(
      target: self,
      action: #selector(self.commentCellHeaderTapped)
    ))

    self.configureAccessibilityElements()
  }

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
  }

  // MARK: - Actions

  @objc func replyButtonTapped() {
    self.viewModel.replyButtonTapped()
  }

  @objc func viewRepliesTapped() {
    self.viewModel.viewRepliesButtonTapped()
  }

  @objc private func commentCellHeaderTapped() {
    self.viewModel.cellHeaderTapped()
  }

  // MARK: - Styles

  override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseTableViewCellStyle()

    _ = self.rootStackView
      |> commentCellRootStackViewStyle

    _ = self.bodyTextView
      |> commentBodyTextViewStyle

    _ = self.postedButton
      |> postedButtonStyle

    _ = self.replyButton
      |> replyButtonStyle

    _ = self.flagButton
      |> UIButton.lens.image(for: .normal) %~ { _ in Kickstarter_iOS.image(named: "flag") }

    self.viewModel.bindStyles()
  }

  // MARK: - Configuration

  internal func configureWith(value: (comment: Comment, project: Project)) {
    self.commentCellHeaderStackView
      .configureWith(comment: value.comment)
    self.viewModel.configureWith(comment: value.comment, project: value.project)
  }

  private func configureViews() {
    let rootViews = [
      self.commentCellHeaderStackView,
      self.bodyTextView,
      self.postedButton,
      self.viewRepliesView,
      self.bottomRowStackView
    ]

    _ = (self.rootStackView, self.contentView)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToMarginsInParent()

    _ = (rootViews, self.rootStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = ([self.replyButton, UIView(), self.flagButton], self.bottomRowStackView)
      |> ksr_addArrangedSubviewsToStackView()

    let viewRepliesGesture = UITapGestureRecognizer(target: self, action: #selector(self.viewRepliesTapped))
    self.viewRepliesView.addGestureRecognizer(viewRepliesGesture)
  }

  private func configureAccessibilityElements() {
    self.isAccessibilityElement = false
    self.accessibilityContainerType = .semanticGroup
    self.accessibilityElements = [
      self.commentCellHeaderStackView,
      self.commentCellHeaderStackView.postTimeLabel,
      self.bodyTextView,
      self.viewRepliesView,
      self.replyButton
    ]
    self.viewRepliesView.isAccessibilityElement = true
    self.viewRepliesView.accessibilityTraits.insert(.button)
    self.commentCellHeaderStackView.isAccessibilityElement = true
    self.commentCellHeaderStackView.accessibilityTraits.insert(.button)
    self.commentCellHeaderStackView.postTimeLabel.isAccessibilityElement = true
    self.bodyTextView.isAccessibilityElement = true
  }

  // MARK: - View model

  internal override func bindViewModel() {
    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .body(text): self.bodyTextView.text = text
      case let .bottomRowStackViewIsHidden(hidden): self.bottomRowStackView.isHidden = hidden
      case let .flagButtonIsHidden(hidden): self.flagButton.isHidden = hidden
      case let .replyButtonIsHidden(hidden): self.replyButton.isHidden = hidden
      case let .viewRepliesViewHidden(hidden): self.viewRepliesView.isHidden = hidden
      case let .postedButtonIsHidden(hidden): self.postedButton.isHidden = hidden
      case let .cellAuthor(author): self.delegate?.commentCellDidTapHeader(self, author)
      case let .replyCommentTapped(comment): self.delegate?.commentCellDidTapReply(self, comment: comment)
      case let .viewCommentReplies(comment): self.delegate?.commentCellDidTapViewReplies(self, comment: comment)
      case let .shouldIndentContent(shouldIndent):
        _ = self.rootStackView
          |> \.axis .~ .vertical
          |> \.layoutMargins .~ .init(top: Styles.grid(1), left: Styles.grid(shouldIndent ? CommentCellStyles.Content.leftIndentWidth : 1), bottom: Styles.grid(3), right: Styles.grid(1))
          |> \.isLayoutMarginsRelativeArrangement .~ true
          |> \.spacing .~ Styles.grid(3)
      default: break
      }
    }
  }
}

// MARK: Styles

private let replyButtonStyle: ButtonStyle = { button in
  button
    |> UIButton.lens
    .title(for: .normal) %~ { _ in Strings.general_navigation_buttons_reply() }
    |> UIButton.lens.titleLabel.font .~ UIFont.ksr_subhead()
    |> UIButton.lens.image(for: .normal) .~ Kickstarter_iOS.image(named: "reply")
    |> UIButton.lens.titleColor(for: .normal) .~ LegacyColors.ksr_support_400.uiColor()
    |> UIButton.lens.tintColor .~ LegacyColors.ksr_support_400.uiColor()
    |> UIButton.lens.imageEdgeInsets .~ UIEdgeInsets(left: Styles.grid(-1))
    |> UIButton.lens.contentEdgeInsets .~ UIEdgeInsets(leftRight: Styles.grid(1))
    |> UIButton.lens.contentHorizontalAlignment .~ .left
}

private let postedButtonStyle: ButtonStyle = { button in
  button
    |> \.isUserInteractionEnabled .~ false
    |> UIButton.lens.title(for: .normal) %~ { _ in Strings.Posted() }
    |> UIButton.lens.titleLabel.font .~ UIFont.ksr_subhead()
    |> UIButton.lens.image(for: .normal) .~ Kickstarter_iOS.image(named: "posted")
    |> UIButton.lens.titleColor(for: .normal) .~ LegacyColors.ksr_create_700.uiColor()
    |> UIButton.lens.tintColor .~ LegacyColors.ksr_create_700.uiColor()
    |> UIButton.lens.titleEdgeInsets .~ UIEdgeInsets(left: Styles.grid(1))
    |> UIButton.lens.contentHorizontalAlignment .~ .left
}
