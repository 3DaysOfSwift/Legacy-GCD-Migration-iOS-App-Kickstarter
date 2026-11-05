import KDS
import KsApi

import Prelude
import UIKit

@MainActor
protocol PledgeShippingLocationViewControllerDelegate: AnyObject {
  func pledgeShippingLocationViewController(
    _ viewController: PledgeShippingLocationViewController,
    didSelect location: Location?
  )
  func pledgeShippingLocationViewControllerFailedToLoad(
    _ viewController: PledgeShippingLocationViewController
  )
}

final class PledgeShippingLocationViewController: UIViewController {
  // MARK: - Properties

  public weak var delegate: PledgeShippingLocationViewControllerDelegate?
  private let viewModel = PledgeShippingLocationViewModel()

  private lazy var adaptableStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var shippingLocationButton: UIButton = { UIButton(frame: .zero) }()
  private lazy var titleLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var rootStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var shimmerLoadingView: PledgeShippingLocationShimmerLoadingView = {
    PledgeShippingLocationShimmerLoadingView(frame: .zero)
  }()

  private lazy var spacer: UIView = {
    UIView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()

    _ = self
      |> \.accessibilityElements .~ [self.titleLabel, self.shippingLocationButton]

    _ = (self.rootStackView, self.view)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToEdgesInParent()

    _ = ([self.titleLabel, self.adaptableStackView, self.shimmerLoadingView], self.rootStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = ([self.shippingLocationButton, self.spacer], self.adaptableStackView)
      |> ksr_addArrangedSubviewsToStackView()

    self.shippingLocationButton.addTarget(
      self,
      action: #selector(PledgeShippingLocationViewController.shippingLocationButtonTapped(_:)),
      for: .touchUpInside
    )

    self.spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: Styles.grid(3)).isActive = true

    self.viewModel.viewDidLoad()
  }

  // MARK: - Styles

  override func bindStyles() {
    super.bindStyles()

    _ = self.view
      |> checkoutBackgroundStyle

    _ = self.adaptableStackView
      |> adaptableStackViewStyle(
        self.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
      )

    _ = self.shippingLocationButton
      |> countryButtonStyle
      |> checkoutWhiteBackgroundStyle
      |> checkoutRoundedCornersStyle

    _ = self.shippingLocationButton.titleLabel
      ?|> countryButtonTitleLabelStyle

    _ = self.titleLabel
      |> checkoutBackgroundStyle
    _ = self.titleLabel
      |> checkoutTitleLabelStyle
      |> \.text %~ { _ in Strings.Your_shipping_location() }

    _ = self.rootStackView
      |> checkoutStackViewStyle
  }

  // MARK: - View model

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .visibility(hidden): self.view.isHidden = hidden
      case let .loading(loading):
        self.adaptableStackView.isHidden = loading
        self.shimmerLoadingView.isHidden = !loading
      case let .selected(location):
        if let location { self.shippingLocationButton.setTitle(location.localizedName, for: .normal) }
        self.delegate?.pledgeShippingLocationViewController(self, didSelect: location)
      case let .present(locations, location):
        self.presentShippingLocations(locations: locations, selectedLocation: location)
      case .dismiss: self.dismiss(animated: true)
      case .error: self.delegate?.pledgeShippingLocationViewControllerFailedToLoad(self)
      }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    self.shimmerLoadingView.layoutSubviews()
  }

  // MARK: - Configuration

  func configureWith(value: PledgeShippingLocationViewData) {
    self.viewModel.configureWith(data: value)
  }

  // MARK: - Actions

  @objc private func shippingLocationButtonTapped(_: UIButton) {
    self.viewModel.shippingLocationButtonTapped()
  }

  // MARK: - Functions

  private func presentShippingLocations(
    locations: [Location],
    selectedLocation: Location
  ) {
    let viewController = ShippingLocations.viewController(
      withLocations: locations,
      selectedLocation: selectedLocation,
      onSelectedLocation: { self.viewModel.shippingLocationUpdated(to: $0) },
      onCancelled: { self.viewModel.shippingLocationCancelButtonTapped() }
    )
    self.presentViewControllerWithSheetOverlay(viewController, offset: CheckoutSheetLayout.Sheet.offset)
  }
}

// MARK: - Styles

private let amountLabelStyle: LabelStyle = { (label: UILabel) in
  label
    |> \.adjustsFontForContentSizeCategory .~ true
}

private let countryButtonStyle: ButtonStyle = { (button: UIButton) in
  button
    |> UIButton.lens.contentEdgeInsets .~ UIEdgeInsets(
      top: Styles.gridHalf(3), left: Styles.grid(2), bottom: Styles.gridHalf(3), right: Styles.grid(5)
    )
    |> UIButton.lens.titleLabel.font .~ UIFont.ksr_body().bolded
    |> UIButton.lens.titleColor(for: .normal) .~ LegacyColors.ksr_create_700.uiColor()
    |> UIButton.lens.titleColor(for: .highlighted) .~ LegacyColors.ksr_create_700.uiColor()
    |> UIButton.lens.image(for: .normal) .~ Kickstarter_iOS.image(named: "icon-dropdown-small")
    |> UIButton.lens.semanticContentAttribute .~ .forceRightToLeft
    |> UIButton.lens.imageEdgeInsets .~ UIEdgeInsets(top: 0, left: Styles.grid(6), bottom: 0, right: 0)
}

private let countryButtonTitleLabelStyle: LabelStyle = { (label: UILabel) in
  label
    |> \.lineBreakMode .~ .byTruncatingTail
}
