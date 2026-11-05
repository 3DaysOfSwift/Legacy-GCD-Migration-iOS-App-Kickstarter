import KDS
import KsApi

import Prelude
import Prelude_UIKit
import UIKit

@MainActor
internal protocol DiscoveryNavigationHeaderViewDelegate: AnyObject {
  /// Call to update params when filter selected.
  func discoveryNavigationHeaderFilterSelectedParams(_ params: DiscoveryParams)
}

internal final class DiscoveryNavigationHeaderViewController: UIViewController {
  fileprivate let viewModel = DiscoveryNavigationHeaderViewModel()

  @IBOutlet fileprivate var arrowImageView: UIImageView!
  @IBOutlet fileprivate var betaToolsButton: UIButton!
  @IBOutlet fileprivate var bgView: UIView!
  @IBOutlet fileprivate var bookmarkImageView: UIImageView!
  @IBOutlet fileprivate var bookmarkOutlineImageView: UIImageView!
  @IBOutlet fileprivate var debugContainerView: UIView!
  @IBOutlet fileprivate var debugImageView: UIImageView!
  @IBOutlet fileprivate var dividerLabel: UILabel!
  @IBOutlet fileprivate var exploreLabel: UILabel!
  @IBOutlet fileprivate var favoriteButton: UIButton!
  @IBOutlet fileprivate var favoriteContainerView: UIView!
  @IBOutlet fileprivate var primaryLabel: UILabel!
  @IBOutlet fileprivate var secondaryLabel: UILabel!
  @IBOutlet fileprivate var titleButton: UIButton!
  @IBOutlet fileprivate var containerStackView: UIStackView!
  @IBOutlet fileprivate var outerStackViewTopConstraint: NSLayoutConstraint!
  @IBOutlet fileprivate var titleStackView: UIStackView! {
    didSet {
      self.titleStackView.pinBackground()
    }
  }

  internal weak var delegate: DiscoveryNavigationHeaderViewDelegate?

  internal static func instantiate() -> DiscoveryNavigationHeaderViewController {
    return Storyboard.Discovery.instantiate(DiscoveryNavigationHeaderViewController.self)
  }

  internal func configureWith(params: DiscoveryParams) {
    self.viewModel.configureWith(params: params)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.betaToolsButton.addTarget(
      self,
      action: #selector(DiscoveryNavigationHeaderViewController.betaToolsButtonTapped),
      for: .touchUpInside
    )

    self.favoriteButton.addTarget(
      self,
      action: #selector(DiscoveryNavigationHeaderViewController.favoriteButtonTapped),
      for: .touchUpInside
    )

    self.titleButton.addTarget(
      self,
      action: #selector(DiscoveryNavigationHeaderViewController.titleButtonTapped),
      for: .touchUpInside
    )

    self.viewModel.viewDidLoad()

    // Initial style
    self.primaryLabel.font = self.traitCollection.isRegularRegular
      ? UIFont.ksr_body(size: 18)
      : UIFont.ksr_body(size: 17)
  }

  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .debugContainerViewIsHidden(hidden): self.debugContainerView.isHidden = hidden
      case let .exploreLabelIsHidden(hidden): self.exploreLabel.isHidden = hidden
      case let .favoriteViewIsHidden(hidden): self.favoriteContainerView.isHidden = hidden
      case let .favoriteButtonAccessibilityLabel(label): self.favoriteButton.accessibilityLabel = label
      case let .primaryLabelText(text): self.primaryLabel.text = text
      case let .secondaryLabelText(text): self.secondaryLabel.text = text
      case let .secondaryLabelIsHidden(hidden): self.secondaryLabel.isHidden = hidden
      case let .dividerIsHidden(hidden): self.dividerLabel.isHidden = hidden
      case let .titleButtonAccessibilityLabel(label): self.titleButton.accessibilityLabel = label
      case let .titleButtonAccessibilityHint(hint): self.titleButton.accessibilityHint = hint
      case let .primaryLabelOpacityAnimated(alpha, animated):
        UIView.animate(withDuration: animated ? 0.2 : 0, delay: 0, options: .curveEaseOut) {
          self.primaryLabel.alpha = alpha
        }
      case let .arrowOpacityAnimated(alpha, animated):
        UIView.animate(withDuration: animated ? 0.2 : 0, delay: 0, options: .curveEaseOut) {
          self.arrowImageView.alpha = alpha
        }
      case let .primaryLabelFont(isBold):
        let label = self.primaryLabel!
        let font: UIFont = label.traitCollection.isRegularRegular ? .ksr_body(size: 18) : .ksr_callout()
        label.font = isBold ? font.bolded : font
      case let .animateArrowToDown(down): self.animateArrow(toDown: down)
      case let .updateFavoriteButton(selected, animated): self.updateFavoriteButton(selected: selected, animated: animated)
      case let .notifyDelegateFilterSelectedParams(params): self.delegate?.discoveryNavigationHeaderFilterSelectedParams(params)
      case let .showDiscoveryFilters(row): self.showDiscoveryFilters(selectedRow: row)
      case .dismissDiscoveryFilters: self.dismiss(animated: false, completion: nil)
      case let .showFavoriteOnboardingAlert(name): self.showFavoriteCategoriesAlert(categoryName: name)
      case let .favoriteViewIsDimmed(dimmed):
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
          self.favoriteContainerView.alpha = dimmed ? 0.4 : 1
        }
      case let .debugImageViewIsDimmed(dimmed): self.debugImageView.tintAdjustmentMode = dimmed ? .dimmed : .normal
      }
    }
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self.arrowImageView
      |> UIView.lens.tintColor .~ discoveryPrimaryColor()

    _ = self.bgView
      |> UIView.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.dividerLabel
      |> discoveryNavDividerLabelStyle
      |> UILabel.lens.isAccessibilityElement .~ false
      |> UILabel.lens.textColor .~ discoveryPrimaryColor()

    _ = self.exploreLabel
      |> UILabel.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()
      |> UILabel.lens.font %~~ { _, label in
        label.traitCollection.isRegularRegular
          ? .ksr_body(size: 18)
          : .ksr_body(size: 17)
      }
      |> UILabel.lens.text %~ { _ in Strings.Explore() }

    _ = self.favoriteContainerView
      |> UIView.lens.layoutMargins .~ .init(left: Styles.grid(2))

    _ = self.bookmarkImageView
      |> UIView.lens.tintColor .~ discoveryPrimaryColor()

    _ = self.bookmarkOutlineImageView
      |> UIView.lens.tintColor .~ discoveryPrimaryColor()

    _ = self.debugImageView
      |> UIImageView.lens.image .~ image(named: "icon--debug")

    _ = self.primaryLabel
      |> UILabel.lens.backgroundColor .~ LegacyColors.ksr_support_100.uiColor()
      |> UILabel.lens.isAccessibilityElement .~ false
      |> UILabel.lens.textColor .~ discoveryPrimaryColor()

    _ = self.secondaryLabel
      |> UILabel.lens.font %~~ { _, label in
        label.traitCollection.isRegularRegular
          ? UIFont.ksr_body(size: 18).bolded
          : UIFont.ksr_callout().bolded
      }
      |> UILabel.lens.isAccessibilityElement .~ false
      |> UILabel.lens.textColor .~ discoveryPrimaryColor()

    _ = self.containerStackView
      |> discoveryNavTitleStackViewStyle

    if self.view.traitCollection.isRegularRegular {
      self.outerStackViewTopConstraint.constant = -6.0
    }
  }

  fileprivate func showDiscoveryFilters(selectedRow: SelectableRow) {
    let vc = DiscoveryFiltersViewController.configuredWith(selectedRow: selectedRow)
    vc.delegate = self
    vc.modalPresentationStyle = .overFullScreen
    self.present(vc, animated: false, completion: nil)
  }

  fileprivate func showFavoriteCategoriesAlert(categoryName: String) {
    let alertController = UIAlertController(
      title: categoryName,
      message: Strings.To_access_all_your_favorite_categories_tap_the_explore_dropdown(),
      preferredStyle: .alert
    )
    alertController.addAction(
      UIAlertAction(
        title: Strings.discovery_favorite_categories_alert_buttons_got_it(),
        style: .cancel,
        handler: nil
      )
    )

    self.present(alertController, animated: true, completion: nil)
  }

  fileprivate func animateArrow(toDown: Bool) {
    let scale: CGFloat = toDown ? 1.0 : -1.0

    UIView.animate(
      withDuration: 0.2, delay: 0.0, options: .curveEaseOut, animations: {
        self.arrowImageView.transform = CGAffineTransform(scaleX: 1.0, y: scale)
      },
      completion: nil
    )
  }

  fileprivate func updateFavoriteButton(selected: Bool, animated: Bool) {
    let duration = animated ? 0.4 : 0.0

    if selected {
      self.bookmarkImageView.transform = CGAffineTransform(scaleX: 0.0, y: 0.0)

      UIView.animate(
        withDuration: duration,
        delay: 0.0,
        usingSpringWithDamping: 0.6,
        initialSpringVelocity: 0.8,
        options: .curveEaseOut,
        animations: {
          self.bookmarkImageView.alpha = 1.0
          self.bookmarkImageView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
          self.bookmarkOutlineImageView.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
        },
        completion: nil
      )

      UIView.animate(
        withDuration: duration,
        delay: animated ? 0.1 : 0.0,
        usingSpringWithDamping: 0.6,
        initialSpringVelocity: 0.8,
        options: .curveEaseOut,
        animations: {
          self.bookmarkOutlineImageView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
          self.bookmarkOutlineImageView.alpha = 0.0
        },
        completion: nil
      )
    } else {
      UIView.animate(
        withDuration: duration,
        delay: 0.0,
        usingSpringWithDamping: 0.6,
        initialSpringVelocity: 0.8,
        options: .curveEaseOut,
        animations: {
          self.bookmarkImageView.transform = CGAffineTransform(scaleX: 0.0, y: 0.0)
          self.bookmarkOutlineImageView.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
          self.bookmarkOutlineImageView.alpha = 1.0
        },
        completion: nil
      )

      UIView.animate(
        withDuration: duration,
        delay: animated ? 0.1 : 0.0,
        usingSpringWithDamping: 0.6,
        initialSpringVelocity: 0.8,
        options: .curveEaseOut,
        animations: {
          self.bookmarkOutlineImageView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
        },
        completion: { _ in
          self.bookmarkImageView.alpha = 0.0
        }
      )
    }
  }

  @objc fileprivate func betaToolsButtonTapped() {
    let betaToolsViewController = BetaToolsViewController.instantiate()
    let navigationController = UINavigationController(rootViewController: betaToolsViewController)
    navigationController.modalPresentationStyle = .formSheet

    self.present(navigationController, animated: true)
  }

  @objc fileprivate func titleButtonTapped() {
    self.viewModel.titleButtonTapped()
  }

  @objc fileprivate func favoriteButtonTapped() {
    self.viewModel.favoriteButtonTapped()
  }
}

extension DiscoveryNavigationHeaderViewController: DiscoveryFiltersViewControllerDelegate {
  internal func discoveryFiltersDidClose(_: DiscoveryFiltersViewController) {
    self.viewModel.titleButtonTapped()
  }

  internal func discoveryFilters(
    _: DiscoveryFiltersViewController,
    selectedRow: SelectableRow
  ) {
    self.viewModel.filtersSelected(row: selectedRow)
  }
}
