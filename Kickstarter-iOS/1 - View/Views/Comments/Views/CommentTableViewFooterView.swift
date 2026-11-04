import KDS

import Prelude
import UIKit

@MainActor
protocol CommentTableViewFooterViewDelegate: AnyObject {
  func commentTableViewFooterViewDidTapRetry(_ view: CommentTableViewFooterView)
}

final class CommentTableViewFooterView: UIView {
  // MARK: - Properties

  private lazy var activityIndicatorView: UIActivityIndicatorView = {
    let indicator = UIActivityIndicatorView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
    return indicator
  }()

  weak var delegate: CommentTableViewFooterViewDelegate?

  private lazy var retryButton = { UIButton(type: .custom) }()

  private lazy var rootStackView = {
    UIStackView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  // MARK: - Lifecycle

  override init(frame: CGRect) {
    super.init(frame: frame)

    self.configureViews()

    self.retryButton.addTarget(self, action: #selector(self.retryButtonTapped), for: .touchUpInside)

    self.activityIndicatorView.startAnimating()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Actions

  @objc func retryButtonTapped() {
    self.delegate?.commentTableViewFooterViewDidTapRetry(self)
  }

  // MARK: - Configuration

  func configureWith(value: CommentTableViewFooterViewState) {
    self.activityIndicatorView.isHidden = value != .activity
    self.retryButton.isHidden = value != .error
    self.rootStackView.isHidden = value == .hidden
    self.rootStackView.layoutMargins = .init(
      top: Styles.grid(2), left: Styles.grid(3),
      bottom: Styles.grid(value == .error ? 4 : 2), right: Styles.grid(3)
    )
  }

  private func configureViews() {
    _ = self
      |> \.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = (self.rootStackView, self)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToMarginsInParent()

    _ = ([self.activityIndicatorView, self.retryButton], self.rootStackView)
      |> ksr_addArrangedSubviewsToStackView()
  }

  // MARK: - Styles

  override func bindStyles() {
    super.bindStyles()

    _ = self.rootStackView
      |> rootStackViewStyle

    _ = self.retryButton
      |> retryButtonStyle
  }
}

// MARK: - Styles

private let retryButtonStyle: ButtonStyle = { button in
  button
    |> UIButton.lens.title(for: .normal) %~ { _ in
      Strings.Couldnt_load_more_comments_Tap_to_retry()
    }
    |> UIButton.lens.titleLabel.lineBreakMode .~ .byWordWrapping
    |> UIButton.lens.titleLabel.font .~ UIFont.ksr_subhead()
    |> UIButton.lens.image(for: .normal) .~ Kickstarter_iOS.image(named: "circle-back")?
    .withRenderingMode(.alwaysTemplate)
    |> UIButton.lens.titleColor(for: .normal) .~ LegacyColors.ksr_celebrate_700.uiColor()
    |> UIButton.lens.tintColor .~ LegacyColors.ksr_celebrate_700.uiColor()
    |> UIButton.lens.titleEdgeInsets .~ UIEdgeInsets(left: Styles.grid(1))
    |> UIButton.lens.contentVerticalAlignment .~ .top
    |> UIButton.lens.contentHorizontalAlignment .~ .left
}

private let rootStackViewStyle: StackViewStyle = { stackView in
  stackView
    |> \.isLayoutMarginsRelativeArrangement .~ true
}
