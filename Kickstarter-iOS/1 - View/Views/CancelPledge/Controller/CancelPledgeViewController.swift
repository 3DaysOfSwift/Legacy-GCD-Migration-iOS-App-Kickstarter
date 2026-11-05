import Foundation
import KDS
import KsApi

import Prelude
import UIKit

@MainActor
protocol CancelPledgeViewControllerDelegate: AnyObject {
  func cancelPledgeViewController(
    _ viewController: CancelPledgeViewController,
    didCancelPledgeWithMessage message: String
  )
}

final class CancelPledgeViewController: UIViewController, MessageBannerViewControllerPresenting {
  private var keyboardObservation: Keyboard.Observation?
  weak var delegate: CancelPledgeViewControllerDelegate?
  private let viewModel = CancelPledgeViewModel()

  // MARK: - Properties

  private lazy var cancelPledgeButton: LoadingButton = {
    LoadingButton(type: .custom)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var cancellationDetailsTextLabel = { UILabel(frame: .zero) }()
  private lazy var cancellationReasonDisclaimerLabel = { UILabel(frame: .zero) }()
  private lazy var cancellationReasonTextField = {
    UITextField(frame: .zero)
      |> \.delegate .~ self
  }()

  private lazy var goBackButton = { UIButton(type: .custom)
    |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  internal var messageBannerViewController: MessageBannerViewController?
  private lazy var rootStackView = { UIStackView(frame: .zero) }()
  private lazy var scrollView = { UIScrollView(frame: .zero) }()

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()

    _ = self
      |> \.title %~ { _ in Strings.Cancel_pledge() }

    _ = (self.scrollView, self.view)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToEdgesInParent()

    _ = (self.rootStackView, self.scrollView)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToEdgesInParent()

    _ = ([
      self.cancellationDetailsTextLabel,
      self.cancellationReasonTextField,
      self.cancellationReasonDisclaimerLabel,
      self.cancelPledgeButton,
      self.goBackButton
    ], self.rootStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = (self.cancellationReasonDisclaimerLabel, self.rootStackView)
      |> ksr_setCustomSpacing(Styles.grid(10))

    _ = (self.cancellationDetailsTextLabel, self.rootStackView)
      |> ksr_setCustomSpacing(Styles.grid(6))

    _ = (self.cancellationReasonTextField, self.rootStackView)
      |> ksr_setCustomSpacing(Styles.grid(1))

    self.setupConstraints()

    self.view.addGestureRecognizer(
      UITapGestureRecognizer(target: self, action: #selector(CancelPledgeViewController.viewTapped))
    )

    self.goBackButton.addTarget(
      self, action: #selector(CancelPledgeViewController.goBackButtonTapped),
      for: .touchUpInside
    )

    self.cancelPledgeButton.addTarget(
      self, action: #selector(CancelPledgeViewController.cancelPledgeButtonTapped),
      for: .touchUpInside
    )

    self.messageBannerViewController = self.configureMessageBannerViewController(on: self)

    self.viewModel.viewDidLoad()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)

    self.viewModel.traitCollectionDidChange()
  }

  // MARK: - Configuration

  internal func configure(with data: CancelPledgeViewData) {
    self.viewModel.configure(with: data)
  }

  override func bindStyles() {
    super.bindStyles()

    _ = self.view
      |> checkoutBackgroundStyle

    _ = self.scrollView
      |> \.alwaysBounceVertical .~ true
      |> \.showsVerticalScrollIndicator .~ false
      |> \.contentInset %~ { _ -> UIEdgeInsets in
        self.contentInsetsFor(traitCollection: self.traitCollection)
      }

    _ = self.rootStackView
      |> checkoutRootStackViewStyle
      |> \.spacing .~ Styles.grid(2)

    _ = self.cancellationDetailsTextLabel
      |> cancellationDetailsTextLabelStyle

    _ = self.cancellationReasonTextField
      |> cancellationReasonTextFieldStyle
      |> \.accessibilityLabel %~ { _ in Strings.Cancellation_reason() }
      |> \.placeholder %~ { _ in Strings.Tell_us_why_optional() }

    _ = self.cancellationReasonDisclaimerLabel
      |> cancellationDisclaimerLabelStyle
      |> \.text %~ { _ in Strings.We_wont_share_this_with_the_creator() }

    self.cancelPledgeButton.applyStyleConfiguration(KSRButtonStyle.filledDestructive)

    _ = self.cancelPledgeButton
      |> UIButton.lens.title(for: .normal) %~ { _ in Strings.Yes_cancel_it() }

    self.goBackButton.applyStyleConfiguration(KSRButtonLegacyStyle.grey)
    _ = self.goBackButton
      |> UIButton.lens.title(for: .normal) %~ { _ in Strings.No_go_back() }
  }

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .details(text): self.cancellationDetailsTextLabel.attributedText = text
      case let .buttonEnabled(enabled): self.cancelPledgeButton.isEnabled = enabled
      case let .error(message): self.messageBannerViewController?.showBanner(with: .error, message: message)
      case let .loading(loading): self.cancelPledgeButton.isLoading = loading
      case let .success(message): self.delegate?.cancelPledgeViewController(self, didCancelPledgeWithMessage: message)
      }
    }

    self.keyboardObservation = Keyboard.observe { [weak self] change in
        guard let self = self else { return }

        self.scrollView
          .handleKeyboardVisibilityDidChange(change, insets: .init(top: self.scrollView.contentInset.top))
      }
  }

  // MARK: - Functions

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      self.rootStackView.widthAnchor.constraint(equalTo: self.view.widthAnchor),
      self.cancelPledgeButton.heightAnchor.constraint(equalToConstant: Styles.minTouchSize.height),
      self.goBackButton.heightAnchor.constraint(equalToConstant: Styles.minTouchSize.height),
      self.cancellationReasonTextField.heightAnchor
        .constraint(greaterThanOrEqualTo: self.cancelPledgeButton.heightAnchor)
    ])
  }

  private func contentInsetsFor(traitCollection: UITraitCollection) -> UIEdgeInsets {
    return traitCollection.preferredContentSizeCategory.isAccessibilityCategory
      ? .zero : .init(top: self.view.frame.height / 4)
  }

  // MARK: - Accessors

  @objc private func viewTapped() {
    self.view.endEditing(true)
  }

  @objc private func goBackButtonTapped() {
    self.navigationController?.popViewController(animated: true)
  }

  @objc private func cancelPledgeButtonTapped() {
    self.viewModel.cancelPledgeButtonTapped()
  }
}

extension CancelPledgeViewController: UITextFieldDelegate {
  func textFieldDidEndEditing(_ textField: UITextField) {
    self.viewModel.textFieldDidEndEditing(with: textField.text)
  }

  func textFieldShouldReturn(_: UITextField) -> Bool {
    self.view.endEditing(true)

    return true
  }
}

// MARK: - Styles

private let cancellationDisclaimerLabelStyle: LabelStyle = { label in
  label
    |> \.font .~ .ksr_caption1()
    |> \.textColor .~ LegacyColors.ksr_support_400.uiColor()
    |> \.textAlignment .~ NSTextAlignment.center
    |> \.numberOfLines .~ 0
}

private let cancellationReasonTextFieldStyle: TextFieldStyle = { textField in
  textField
    |> formFieldStyle
    |> \.backgroundColor .~ LegacyColors.ksr_white.uiColor()
    |> \.borderStyle .~ UITextField.BorderStyle.roundedRect
}

private let cancellationDetailsTextLabelStyle: LabelStyle = { label in
  label
    |> \.textAlignment .~ NSTextAlignment.center
    |> \.numberOfLines .~ 0
}
