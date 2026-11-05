import KDS
import KsApi

import Prelude
import StripePaymentSheet
import UIKit

@MainActor
protocol PaymentMethodSettingsViewControllerDelegate: AnyObject {
  func cancelLoadingPaymentMethodsViewController(
    _ viewController: PaymentMethodSettingsViewController
  )
}

internal final class PaymentMethodSettingsViewController: UIViewController,
  MessageBannerViewControllerPresenting {
  private let dataSource = PaymentMethodsDataSource()
  private let viewModel = PaymentMethodSettingsViewModel(stripeIntentService: StripeIntentService())
  private let paymentSheet = PaymentSheetOperation()
  private weak var cancellationDelegate: PaymentMethodSettingsViewControllerDelegate?
  @IBOutlet private var tableView: UITableView!

  fileprivate lazy var editButton: UIBarButtonItem = {
    UIBarButtonItem(
      title: Strings.discovery_favorite_categories_buttons_edit(),
      style: .plain,
      target: self,
      action: #selector(self.edit)
    )
  }()

  internal var messageBannerViewController: MessageBannerViewController?

  public static func instantiate() -> PaymentMethodSettingsViewController {
    return Storyboard.Settings.instantiate(PaymentMethodSettingsViewController.self)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.messageBannerViewController = self.configureMessageBannerViewController(on: self)

    self.tableView.register(nib: .CreditCardCell)

    self.tableView.dataSource = self.dataSource
    self.tableView.delegate = self

    self.configureHeaderFooterViews()

    self.navigationItem.rightBarButtonItem = self.editButton
    self.editButton.possibleTitles = [
      Strings.discovery_favorite_categories_buttons_edit(),
      Strings.Done()
    ]

    self.dataSource.deletionHandler = { [weak self] creditCard in
      self?.paymentSheet.cancelBeforePresentation()
      self?.viewModel.shouldCancelPaymentSheetAppearance(state: true)
      self?.viewModel.didDelete(creditCard, visibleCellCount: self?.tableView.visibleCells.count ?? 0)
    }

    self.viewModel.viewDidLoad()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if self.isMovingFromParent || self.isBeingDismissed || self.navigationController?.isBeingDismissed == true {
      self.paymentSheet.cancelObservation()
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    self.tableView.ksr_sizeHeaderFooterViewsToFit()
  }

  override func bindStyles() {
    super.bindStyles()

    _ = self
      |> settingsViewControllerStyle
      |> UIViewController.lens.title %~ { _ in
        Strings.Payment_methods()
      }

    _ = self.tableView
      |> tableViewStyle
      |> tableViewSeparatorStyle
  }

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .editButtonIsEnabled(enabled): self.editButton.isEnabled = enabled
      case .cancelAddNewCardLoadingState: self.cancellationDelegate?.cancelLoadingPaymentMethodsViewController(self)
      case let .paymentMethods(cards): self.dataSource.load(creditCards: cards); self.tableView.reloadData()
      case .reloadData: self.tableView.reloadData()
      case let .goToPaymentSheet(data): self.goToPaymentSheet(data: data)
      case let .errorLoadingPaymentMethodsOrSetupIntent(message): self.messageBannerViewController?.showBanner(with: .error, message: message)
      case let .presentBanner(message): self.messageBannerViewController?.showBanner(with: .success, message: message)
      case let .tableViewIsEditing(editing): self.tableView.setEditing(editing, animated: true)
      case let .showAlert(message): self.present(UIAlertController.genericError(message), animated: true)
      case let .editButtonTitle(title): self.editButton.title = title
      case let .setStripePublishableKey(key): STPAPIClient.shared.publishableKey = key
      }
    }
  }

  // MARK: - Actions

  @objc private func edit() {
    self.paymentSheet.cancelBeforePresentation()
    self.viewModel.editButtonTapped()
    self.viewModel.shouldCancelPaymentSheetAppearance(state: true)
  }

  // MARK: - Private Helpers

  private func goToPaymentSheet(data: PaymentSheetSetupData) {
    let session = AppModel.shared.sessionFeature
    let generation = session.generation
    self.paymentSheet.start(
      clientSecret: data.clientSecret, client: StripePaymentSheetClient(data: data),
      presenter: self, retrievePaymentMethod: false,
      isCurrent: { [weak self] in
        session.generation == generation && self?.navigationController?.topViewController === self
      },
      completed: { [weak self] result in
        guard let self else { return }
        self.viewModel.shouldCancelPaymentSheetAppearance(state: true)
        switch result {
        case .completed: self.viewModel.paymentSheetDidAdd(setupIntent: data.clientSecret)
        case .noSelection: break
        case .canceled: self.viewModel.failedToAddNewCard()
        case let .loadFailed(error):
          self.messageBannerViewController?.showBanner(with: .error, message: error.localizedDescription)
        case let .failed(error):
          self.viewModel.failedToAddNewCard()
          self.messageBannerViewController?.showBanner(with: .error, message: error.localizedDescription)
        }
      }
    )
  }

  private func configureHeaderFooterViews() {
    if let header = SettingsTableViewHeader.fromNib(nib: Nib.SettingsTableViewHeader) {
      header.configure(with: Strings.Any_payment_methods_you_saved_to_Kickstarter())

      let headerContainer = UIView(frame: .zero)
      _ = (header, headerContainer) |> ksr_addSubviewToParent()

      self.tableView.tableHeaderView = headerContainer

      _ = (header, headerContainer) |> ksr_constrainViewToEdgesInParent()

      _ = header.widthAnchor.constraint(equalTo: self.tableView.widthAnchor)
        |> \.priority .~ .defaultHigh
        |> \.isActive .~ true
    }

    if let footer = PaymentMethodsFooterView.fromNib(nib: Nib.PaymentMethodsFooterView) {
      footer.delegate = self
      self.cancellationDelegate = footer

      let footerContainer = UIView(frame: .zero)
      _ = (footer, footerContainer) |> ksr_addSubviewToParent()

      self.tableView.tableFooterView = footerContainer

      _ = (footer, footerContainer) |> ksr_constrainViewToEdgesInParent()

      _ = footer.widthAnchor.constraint(equalTo: self.tableView.widthAnchor)
        |> \.priority .~ .defaultHigh
        |> \.isActive .~ true
    }
  }
}

extension PaymentMethodSettingsViewController: UITableViewDelegate {
  func tableView(_: UITableView, heightForFooterInSection _: Int) -> CGFloat {
    return 0.1
  }

  func tableView(_: UITableView, heightForHeaderInSection _: Int) -> CGFloat {
    return 0.1
  }
}

extension PaymentMethodSettingsViewController: PaymentMethodsFooterViewDelegate {
  internal func paymentMethodsFooterViewDidTapAddNewCardButton(_: PaymentMethodsFooterView) {
    self.viewModel.paymentMethodsFooterViewDidTapAddNewCardButton()
  }
}

// MARK: - Styles

private let tableViewStyle: TableViewStyle = { (tableView: UITableView) in
  tableView
    |> \.backgroundColor .~ UIColor.clear
    |> \.rowHeight .~ Styles.grid(11)
    |> \.allowsSelection .~ false
}

private let tableViewSeparatorStyle: TableViewStyle = { tableView in
  tableView
    |> \.separatorStyle .~ .singleLine
    |> \.separatorColor .~ LegacyColors.ksr_support_300.uiColor()
    |> \.separatorInset .~ .init(left: Styles.grid(2))
}
