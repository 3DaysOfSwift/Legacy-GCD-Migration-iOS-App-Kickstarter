import KDS
import KsApi

import Prelude
import UIKit

final class CommentPostFailedCell: UITableViewCell, ValueCell {
  // MARK: - Properties

  private let viewModel = CommentCellViewModel()

  private lazy var bodyTextView: UITextView = { UITextView(frame: .zero) }()
  private lazy var commentCellHeaderStackView: CommentCellHeaderStackView = {
    CommentCellHeaderStackView(frame: .zero)
  }()

  private lazy var rootStackView = {
    UIStackView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var retryButton = { UIButton(frame: .zero)
    |> \.isUserInteractionEnabled .~ false
  }()

  // MARK: - Lifecycle

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)

    self.setupConstraints()
    self.bindStyles()
    self.configureViews()
    self.bindViewModel()
  }

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
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
      |> \.textColor .~ LegacyColors.ksr_support_400.uiColor()

    self.viewModel.bindStyles()
  }

  // MARK: - Configuration

  internal func configureWith(value: Comment) {
    self.commentCellHeaderStackView
      .configureWith(comment: value)
    self.viewModel.configureWith(comment: value, project: nil)
  }

  private func configureViews() {
    _ = ([self.commentCellHeaderStackView, self.bodyTextView, self.retryButton], self.rootStackView)
      |> ksr_addArrangedSubviewsToStackView()
  }

  private func setupConstraints() {
    _ = (self.rootStackView, self.contentView)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToMarginsInParent()
  }

  // MARK: - View model

  internal override func bindViewModel() {
    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .body(text): self.bodyTextView.text = text
      case let .commentStatus(status):
        _ = self.retryButton |> status == .retrying ? postingButtonStyle : retryButtonStyle
      case let .shouldIndentContent(shouldIndent):
        if shouldIndent { _ = self.rootStackView |> commentCellIndentedRootStackViewStyle }
      default: break
      }
    }
  }
}

// MARK: Styles

private let retryButtonStyle: ButtonStyle = { button in
  button
    |> UIButton.lens
    .title(for: .normal) %~
    { _ in Strings.Couldnt_post() }
    |> UIButton.lens.titleLabel.font .~ UIFont.ksr_subhead()
    |> UIButton.lens.image(for: .normal) .~ Kickstarter_iOS.image(named: "circle-back")
    |> UIButton.lens.titleColor(for: .normal) .~ LegacyColors.ksr_celebrate_700.uiColor()
    |> UIButton.lens.tintColor .~ LegacyColors.ksr_celebrate_700.uiColor()
    |> UIButton.lens.titleEdgeInsets .~ UIEdgeInsets(left: Styles.grid(1))
    |> UIButton.lens.contentHorizontalAlignment .~ .left
    |> UIButton.lens.titleLabel.numberOfLines .~ 0
}

private let postingButtonStyle: ButtonStyle = { button in
  button
    |> UIButton.lens.title(for: .normal) %~ { _ in Strings.Posting() }
    |> UIButton.lens.titleLabel.font .~ UIFont.ksr_subhead()
    |> UIButton.lens.image(for: .normal) .~ Kickstarter_iOS.image(named: "circle-back")?
    .withRenderingMode(.alwaysTemplate)
    |> UIButton.lens.titleColor(for: .normal) .~ LegacyColors.ksr_support_400.uiColor()
    |> UIButton.lens.tintColor .~ LegacyColors.ksr_support_400.uiColor()
    |> UIButton.lens.titleEdgeInsets .~ UIEdgeInsets(left: Styles.grid(1))
    |> UIButton.lens.contentHorizontalAlignment .~ .left
}
