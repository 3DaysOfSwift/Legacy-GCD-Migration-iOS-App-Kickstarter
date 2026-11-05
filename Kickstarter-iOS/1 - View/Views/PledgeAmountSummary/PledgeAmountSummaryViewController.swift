import KDS
import KsApi

import Prelude
import Prelude_UIKit
import UIKit

final class PledgeAmountSummaryViewController: UIViewController {
  // MARK: Properties

  private lazy var bonusAmountLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var bonusAmountStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var bonusLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var pledgeAmountLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var pledgeAmountStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var pledgeLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var rootStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var shippingAmountLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var shippingLocationLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var shippingLocationStackView: UIStackView = { UIStackView(frame: .zero) }()

  private let viewModel = PledgeAmountSummaryViewModel()

  // MARK: Life cycle

  public func configureWith(_ data: PledgeAmountSummaryViewData) {
    self.viewModel.configureWith(data)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.configureSubviews()

    self.viewModel.viewDidLoad()
  }

  // MARK: Styles

  override func bindStyles() {
    super.bindStyles()

    let isAccessibilityCategory = self.traitCollection.preferredContentSizeCategory.isAccessibilityCategory

    _ = self.rootStackView
      |> rootStackViewStyle

    _ = self.bonusAmountStackView
      |> adaptableStackViewStyle(isAccessibilityCategory)

    _ = self.pledgeAmountStackView
      |> adaptableStackViewStyle(isAccessibilityCategory)

    _ = self.shippingLocationStackView
      |> adaptableStackViewStyle(isAccessibilityCategory)

    _ = self.bonusLabel
      |> titleLabelStyle
      |> \.text %~ { _ in Strings.Bonus() }

    _ = self.pledgeLabel
      |> titleLabelStyle
      |> \.text %~ { _ in Strings.Pledge_label() }

    _ = self.pledgeAmountLabel
      |> amountLabelStyle

    _ = self.shippingLocationLabel
      |> titleLabelStyle

    _ = self.shippingAmountLabel
      |> amountLabelStyle
  }

  // MARK: View model

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onDisplay = { [weak self] display in
      guard let self else { return }
      if let bonus = display.bonus { self.bonusAmountLabel.attributedText = bonus }
      self.bonusAmountStackView.isHidden = display.bonusHidden
      if let pledge = display.pledge { self.pledgeAmountLabel.attributedText = pledge }
      if let shipping = display.shipping { self.shippingAmountLabel.attributedText = shipping }
      if let location = display.location { self.shippingLocationLabel.text = location }
      self.shippingLocationStackView.isHidden = display.shippingHidden
    }
  }

  // MARK: Functions

  private func configureSubviews() {
    _ = (self.rootStackView, self.view)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToEdgesInParent()

    _ = ([self.pledgeLabel, self.pledgeAmountLabel], self.pledgeAmountStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = ([self.bonusLabel, self.bonusAmountLabel], self.bonusAmountStackView)
      |> ksr_addArrangedSubviewsToStackView()

    self.bonusAmountLabel.setContentHuggingPriority(.required, for: .horizontal)
    self.pledgeAmountLabel.setContentHuggingPriority(.required, for: .horizontal)
    self.shippingAmountLabel.setContentHuggingPriority(.required, for: .horizontal)

    _ = ([self.shippingLocationLabel, self.shippingAmountLabel], self.shippingLocationStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = ([
      self.pledgeAmountStackView,
      self.shippingLocationStackView,
      self.bonusAmountStackView
    ], self.rootStackView)
      |> ksr_addArrangedSubviewsToStackView()
  }
}

// MARK: Styles

private let amountLabelStyle: LabelStyle = { label in
  label
    |> \.adjustsFontForContentSizeCategory .~ true
    |> \.textAlignment .~ NSTextAlignment.right
    |> \.isAccessibilityElement .~ true
    |> \.minimumScaleFactor .~ 0.75
}

private let titleLabelStyle: LabelStyle = { label in
  label
    |> \.textColor .~ LegacyColors.ksr_support_400.uiColor()
    |> \.font .~ UIFont.ksr_subhead().bolded
    |> \.adjustsFontForContentSizeCategory .~ true
    |> \.numberOfLines .~ 0
}

private let rootStackViewStyle: StackViewStyle = { stackView in
  stackView
    |> checkoutStackViewStyle
    |> \.spacing .~ Styles.grid(3)
}
