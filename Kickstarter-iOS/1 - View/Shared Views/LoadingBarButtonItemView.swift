import KDS

import Prelude
import UIKit

final class LoadingBarButtonItemView: UIView {
  private lazy var activityIndicator: UIActivityIndicatorView = { UIActivityIndicatorView() }()
  private lazy var titleButton: UIButton = { UIButton() }()

  private let viewModel = LoadingBarButtonItemViewModel()

  // Helper function for creating a UIBarButtonItem for the LoadingBarButtonItemView with liquid
  // glass animation off. The liquid glass animation is added directly to the UIButton instead,
  // which is necessary in order for it to respect the UIButton state.
  public static func uiBarButtonItem(for loadingBarButtonItemView: LoadingBarButtonItemView)
    -> UIBarButtonItem {
    let barButtonItem = UIBarButtonItem(customView: loadingBarButtonItemView)
    if #available(iOS 26.0, *) {
      barButtonItem.hidesSharedBackground = true
    }
    return barButtonItem
  }

  public static func instantiate() -> LoadingBarButtonItemView {
    let saveButtonView = LoadingBarButtonItemView.init()
    saveButtonView.translatesAutoresizingMaskIntoConstraints = false
    return saveButtonView
  }

  required init() {
    super.init(frame: .zero)

    self.setupView()
    self.bindViewModel()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    self.titleButton.translatesAutoresizingMaskIntoConstraints = false
    self.titleButton.isEnabled = false
    self.addSubview(self.titleButton)

    if #available(iOS 26.0, *) {
      self.titleButton.configuration = .glass()
    } else {
      self.titleButton.setTitleColor(LegacyColors.ksr_create_700.uiColor(), for: .normal)
      self.titleButton.setTitleColor(LegacyColors.ksr_support_300.uiColor(), for: .disabled)
    }
    self.titleButton.titleLabel?.font = UIFont.ksr_body()

    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = false
    self.addSubview(self.activityIndicator)

    NSLayoutConstraint.activate([
      self.titleButton.leadingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.leadingAnchor),
      self.titleButton.topAnchor.constraint(equalTo: self.safeAreaLayoutGuide.topAnchor),
      self.titleButton.trailingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.trailingAnchor),
      self.titleButton.bottomAnchor.constraint(equalTo: self.safeAreaLayoutGuide.bottomAnchor),

      self.activityIndicator.trailingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.trailingAnchor),
      self.activityIndicator.centerYAnchor.constraint(equalTo: self.titleButton.centerYAnchor),
      self.heightAnchor.constraint(greaterThanOrEqualTo: self.activityIndicator.heightAnchor, multiplier: 1)
    ])
  }

  override func bindStyles() {
    super.bindStyles()

    _ = self.activityIndicator
      |> baseActivityIndicatorStyle
  }

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onEnabledChanged = { [weak self] in self?.titleButton.isEnabled = $0 }
    self.viewModel.onTitleChanged = { [weak self] in self?.titleButton.setTitle($0, for: .normal) }
    self.viewModel.onAnimatingChanged = { [weak self] isAnimating in
      self?.titleButton.isHidden = isAnimating
      self?.animateActivityIndicator(isAnimating)
    }
  }

  // MARK: - Public Functions

  func setIsEnabled(isEnabled: Bool) {
    self.viewModel.setIsEnabled(isEnabled: isEnabled)
  }

  func setTitle(title: String) {
    self.viewModel.setTitle(title: title)
  }

  func startAnimating() {
    self.viewModel.setAnimating(isAnimating: true)
  }

  func stopAnimating() {
    self.viewModel.setAnimating(isAnimating: false)
  }

  func addTarget(_ target: Any?, action: Selector) {
    self.titleButton.addTarget(target, action: action, for: .touchUpInside)
  }

  // MARK: - Functions

  private func animateActivityIndicator(_ isAnimating: Bool) {
    if isAnimating {
      bringSubviewToFront(self.activityIndicator)

      self.activityIndicator.startAnimating()
    } else {
      self.activityIndicator.stopAnimating()

      bringSubviewToFront(self.titleButton)
    }
  }
}
