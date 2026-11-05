import KDS
import KsApi

import Prelude
import UIKit

final class PledgeSummaryViewController: UIViewController {
  // MARK: - Properties

  private lazy var titleAndTotalStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var amountLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var confirmationLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var rootStackView: UIStackView = {
    UIStackView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var titleLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var totalConversionLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var totalStackView: UIStackView = { UIStackView(frame: .zero) }()
  private let viewModel = PledgeSummaryViewModel()

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()

    self.configureSubviews()

    self.viewModel.viewDidLoad()
  }

  // MARK: - Styles

  override func bindStyles() {
    super.bindStyles()

    _ = self.view
      |> checkoutBackgroundStyle

    _ = self.rootStackView
      |> rootStackViewStyle

    _ = self.confirmationLabel
      |> \.numberOfLines .~ 0
      |> checkoutBackgroundStyle

    _ = self.titleAndTotalStackView
      |> adaptableStackViewStyle(
        self.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
      )
      |> titleAndTotalStackViewStyle

    _ = self.totalStackView
      |> totalStackViewStyle(self.traitCollection.preferredContentSizeCategory.isAccessibilityCategory)

    _ = self.titleLabel
      |> titleLabelStyle

    _ = self.amountLabel
      |> amountLabelStyle

    _ = self.totalConversionLabel
      |> totalConversionLabelStyle
  }

  private func configureSubviews() {
    _ = (self.rootStackView, self.view)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToEdgesInParent()

    _ = ([self.titleAndTotalStackView, self.confirmationLabel], self.rootStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = ([self.titleLabel, self.totalStackView], self.titleAndTotalStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = ([self.amountLabel, self.totalConversionLabel], self.totalStackView)
      |> ksr_addArrangedSubviewsToStackView()
  }

  // MARK: - View model

  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onConfirmationHidden = { [weak self] in self?.confirmationLabel.isHidden = $0 }
    self.viewModel.onConfirmation = { [weak self] in self?.confirmationLabel.attributedText = $0 }
    self.viewModel.onHelp = { [weak self] in self?.presentHelpWebViewController(with: $0, presentationStyle: .formSheet) }
    self.viewModel.onAmount = { [weak self] in self?.amountLabel.attributedText = $0 }
    self.viewModel.onConversion = { [weak self] in self?.totalConversionLabel.text = $0 }
  }

  // MARK: - Configuration

  internal func configure(with data: PledgeSummaryViewData) {
    self.viewModel.configure(with: data)
    self.viewModel.configureWith(pledgeOverTimeData: nil)
  }
}

extension PledgeSummaryViewController: UITextViewDelegate {
  func textView(
    _: UITextView, shouldInteractWith _: NSTextAttachment,
    in _: NSRange, interaction _: UITextItemInteraction
  ) -> Bool {
    return false
  }

  func textView(
    _: UITextView, shouldInteractWith url: URL, in _: NSRange,
    interaction _: UITextItemInteraction
  ) -> Bool {
    self.viewModel.tapped(url)
    return false
  }
}

// MARK: - Styles

private let amountLabelStyle: LabelStyle = { (label: UILabel) in
  _ = label
    |> \.adjustsFontForContentSizeCategory .~ true
    |> \.textAlignment .~ NSTextAlignment.right
    |> \.adjustsFontSizeToFitWidth .~ true
    |> \.isAccessibilityElement .~ true
    |> \.minimumScaleFactor .~ 0.75

  _ = label
    |> checkoutBackgroundStyle

  return label
}

private let titleAndTotalStackViewStyle: StackViewStyle = { (stackView: UIStackView) in
  stackView
    |> \.alignment .~ UIStackView.Alignment.top
}

private let rootStackViewStyle: StackViewStyle = { (stackView: UIStackView) in
  stackView
    |> verticalStackViewStyle
    |> \.spacing .~ Styles.grid(3)
}

private let titleLabelStyle: LabelStyle = { (label: UILabel) -> UILabel in
  _ = label
    |> checkoutTitleLabelStyle
    |> \.text %~ { _ in Strings.Total() }

  _ = label
    |> checkoutBackgroundStyle

  return label
}

private let totalConversionLabelStyle: LabelStyle = { label in
  _ = label
    |> \.font .~ .ksr_footnote()
    |> \.textColor .~ LegacyColors.ksr_support_400.uiColor()

  _ = label |> checkoutBackgroundStyle

  return label
}

private func totalStackViewStyle(_ isAccessibilityCategory: Bool) -> StackViewStyle {
  return { stackView in
    stackView
      |> verticalStackViewStyle
      |> \.spacing .~ Styles.grid(1)
      |> \.alignment .~
      (isAccessibilityCategory ? UIStackView.Alignment.leading : UIStackView.Alignment.trailing)
  }
}
