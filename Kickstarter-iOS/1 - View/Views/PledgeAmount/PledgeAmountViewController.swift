import KDS
import KsApi

import Prelude
import Prelude_UIKit
import UIKit

@MainActor
protocol PledgeAmountViewControllerDelegate: AnyObject {
  func pledgeAmountViewController(
    _ viewController: PledgeAmountViewController,
    didUpdateWith data: PledgeAmountData
  )
}

final class PledgeAmountViewController: UIViewController {
  // MARK: - Properties

  public weak var delegate: PledgeAmountViewControllerDelegate?
  private let viewModel = PledgeAmountViewModel()

  private lazy var adaptableStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var amountInputView: AmountInputView = { AmountInputView(frame: .zero) }()
  private lazy var amountInputStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var maxPledgeAmountErrorLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var plusSignLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var titleLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var titlesStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var subtitleLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var rootStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var horizontalSpacer: UIView = { UIView(frame: .zero) }()
  private lazy var stepper: UIStepper = { UIStepper(frame: .zero) }()
  private lazy var verticalSpacer: UIView = { UIView(frame: .zero) }()

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()

    _ = self
      |> \.accessibilityElements .~ [
        self.titleLabel,
        self.subtitleLabel,
        self.stepper,
        self.amountInputView
      ]

    _ = (self.rootStackView, self.view)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToEdgesInParent()

    _ = ([self.titleLabel, self.subtitleLabel], self.titlesStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = ([
      self.titlesStackView,
      self.adaptableStackView,
      self.maxPledgeAmountErrorLabel,
      self.verticalSpacer
    ], self.rootStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = ([self.plusSignLabel, self.amountInputView], self.amountInputStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = ([
      self.stepper,
      self.horizontalSpacer,
      self.amountInputStackView
    ], self.adaptableStackView)
      |> ksr_addArrangedSubviewsToStackView()
    self.amountInputView.textField.delegate = self

    self.amountInputView.doneButton.addTarget(
      self,
      action: #selector(PledgeAmountViewController.doneButtonTapped(_:)),
      for: .touchUpInside
    )

    self.amountInputView.textField.addTarget(
      self,
      action: #selector(PledgeAmountViewController.textFieldDidChange(_:)),
      for: .editingChanged
    )

    self.stepper.addTarget(
      self,
      action: #selector(PledgeAmountViewController.stepperValueChanged(_:)),
      for: .valueChanged
    )
  }

  // MARK: - Styles

  override func bindStyles() {
    super.bindStyles()

    let isAccessibilityCategory = self.traitCollection.preferredContentSizeCategory.isAccessibilityCategory

    _ = self.view
      |> checkoutBackgroundStyle

    _ = self.adaptableStackView
      |> adaptableStackViewStyle(isAccessibilityCategory)
      |> \.spacing .~ Styles.grid(3)

    _ = self.titlesStackView
      |> \.axis .~ .vertical
      |> \.spacing .~ Styles.grid(1)

    let amountInputAxis: NSLayoutConstraint.Axis = isAccessibilityCategory ? .vertical : .horizontal
    let amountInputAlignment: UIStackView.Alignment = isAccessibilityCategory ? .leading : .center

    _ = self.amountInputStackView
      |> \.axis .~ amountInputAxis
      |> \.alignment .~ amountInputAlignment
      |> \.spacing .~ Styles.grid(1)
    _ = self.horizontalSpacer
      |> \.isHidden .~ isAccessibilityCategory

    _ = self.titleLabel
      |> checkoutTitleLabelStyle
      |> checkoutBackgroundStyle

    _ = self.plusSignLabel
      |> \.text .~ "+"
      |> \.textColor .~ LegacyColors.ksr_support_400.uiColor()

    _ = self.subtitleLabel
      |> subtitleLabelStyle

    _ = self.rootStackView
      |> checkoutStackViewStyle

    _ = self.stepper
      |> checkoutStepperStyle

    _ = self.maxPledgeAmountErrorLabel
      |> maxPledgeAmountErrorLabelStyle

    self.plusSignLabel.setContentHuggingPriority(.required, for: .horizontal)
    self.amountInputView.setContentCompressionResistancePriority(.required, for: .horizontal)
    self.amountInputView.setContentHuggingPriority(.required, for: .horizontal)
  }

  // MARK: - View model

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .currency(value): self.amountInputView.label.text = value
      case let .valid(value): self.amountInputView.doneButton.isEnabled = value
      case .selectionFeedback: generateSelectionFeedback()
      case .warningFeedback: generateNotificationWarningFeedback()
      case let .color(value):
        self.amountInputView.label.textColor = value
        self.amountInputView.textField.textColor = value
      case let .maxErrorHidden(value): self.maxPledgeAmountErrorLabel.isHidden = value
      case let .maxErrorText(value): self.maxPledgeAmountErrorLabel.text = value
      case let .amount(value): self.delegate?.pledgeAmountViewController(self, didUpdateWith: value)
      case let .noReward(value):
        self.plusSignLabel.isHidden = value
        self.subtitleLabel.isHidden = value
      case let .stepperMax(value): self.stepper.maximumValue = value
      case let .stepperMin(value): self.stepper.minimumValue = value
      case let .stepperValue(value): self.stepper.value = value
      case .endEditing: self.amountInputView.textField.resignFirstResponder()
      case let .text(value): self.amountInputView.textField.text = value
      case let .title(value): self.titleLabel.text = value
      }
    }
  }

  override func didMove(toParent _: UIViewController?) {
    self.verticalSpacer.isHidden = true
  }

  // MARK: - Configuration

  func configureWith(value: PledgeAmountViewConfigData) {
    self.viewModel.configureWith(data: value)
  }

  // MARK: - Actions

  @objc func doneButtonTapped(_: UIButton) {
    self.viewModel.doneButtonTapped()
  }

  @objc func stepperValueChanged(_ stepper: UIStepper) {
    self.viewModel.stepperValueChanged(stepper.value)
  }

  @objc func textFieldDidChange(_ textField: UITextField) {
    self.viewModel.textFieldValueChanged(textField.text)
  }

  // MARK: - Accessors

  func unavailableAmountChanged(to amount: Double) {
    self.viewModel.unavailableAmountChanged(to: amount)
  }
}

extension PledgeAmountViewController: UITextFieldDelegate {
  func textField(
    _ textField: UITextField, shouldChangeCharactersIn _: NSRange, replacementString string: String
  ) -> Bool {
    let decimalSeparatorCharacters = CharacterSet.ksr_decimalSeparators()
    let existingCharacters = CharacterSet(charactersIn: textField.text.coalesceWith(""))
    let inputCharacters = CharacterSet(charactersIn: string)
    let numericCharacters = CharacterSet.ksr_numericCharacters()

    if numericCharacters.isSuperset(of: inputCharacters) {
      return true
    } else if decimalSeparatorCharacters.isSuperset(of: inputCharacters) {
      return !decimalSeparatorCharacters.isSubset(of: existingCharacters)
    } else {
      return false
    }
  }

  func textFieldDidEndEditing(_ textField: UITextField, reason _: UITextField.DidEndEditingReason) {
    self.viewModel.textFieldDidEndEditing(textField.text)
  }
}

// MARK: - Styles

private let subtitleLabelStyle: LabelStyle = { label in
  label
    |> \.font .~ UIFont.ksr_footnote()
    |> \.numberOfLines .~ 0
    |> \.textColor .~ LegacyColors.ksr_support_400.uiColor()
    |> \.text .~ Strings.A_little_extra_to_help()
}

private let maxPledgeAmountErrorLabelStyle: LabelStyle = { label in
  label
    |> \.font .~ UIFont.ksr_caption1()
    |> \.numberOfLines .~ 0
    |> \.textColor .~ LegacyColors.ksr_alert.uiColor()
    |> \.textAlignment .~ .right
}
