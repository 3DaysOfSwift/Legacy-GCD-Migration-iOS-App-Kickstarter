import KsApi

import PassKit
import Prelude
import StripePaymentSheet
import UIKit

@MainActor
protocol PledgePaymentMethodsViewControllerDelegate: AnyObject {
  func pledgePaymentMethodsViewController(
    _ viewController: PledgePaymentMethodsViewController,
    didSelectCreditCard paymentSource: PaymentSourceSelected
  )
}

final class PledgePaymentMethodsViewController: UIViewController {
  // MARK: - Properties

  private let dataSource = PledgePaymentMethodsDataSource()

  private lazy var tableView: UITableView = {
    ContentSizeTableView(frame: .zero, style: .plain)
      |> \.separatorInset .~ .zero
      |> \.contentInsetAdjustmentBehavior .~ .never
      |> \.isScrollEnabled .~ false
      |> \.dataSource .~ self.dataSource
      |> \.delegate .~ self
      |> \.rowHeight .~ UITableView.automaticDimension
  }()

  internal weak var delegate: PledgePaymentMethodsViewControllerDelegate?
  internal weak var messageDisplayingDelegate: PledgeViewControllerMessageDisplaying?
  private let viewModel = PledgePaymentMethodsViewModel(stripeIntentService: StripeIntentService())
  private let paymentSheet = PaymentSheetOperation()

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()

    self.configureSubviews()
    self.setupConstraints()

    self.viewModel.viewDidLoad()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if self.isMovingFromParent || self.isBeingDismissed || self.parent?.isMovingFromParent == true ||
      self.parent?.isBeingDismissed == true || self.navigationController?.isBeingDismissed == true {
      self.paymentSheet.cancelObservation()
    }
  }

  private func configureSubviews() {
    _ = (self.tableView, self.view)
      |> ksr_addSubviewToParent()

    self.tableView.registerCellClass(PledgePaymentMethodCell.self)
    self.tableView.registerCellClass(PledgePaymentMethodAddCell.self)
    self.tableView.registerCellClass(PledgePaymentMethodLoadingCell.self)
  }

  private func setupConstraints() {
    _ = (self.tableView, self.view)
      |> ksr_constrainViewToEdgesInParent()
  }

  // MARK: - Bind Styles

  override func bindStyles() {
    super.bindStyles()
    _ = self.view
      |> checkoutBackgroundStyle

    _ = self.tableView
      |> checkoutWhiteBackgroundStyle
  }

  // MARK: - View model

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .reloadPaymentMethods(data):
        self.dataSource.load(data.existingPaymentMethods, paymentSheetCards: data.newPaymentMethods, isLoading: data.isLoading)
        if data.shouldReload {
          self.tableView.reloadData()
        } else if case let .savedCreditCard(selectedCardId, _) = data.selectedPaymentMethod {
          self.tableView.visibleCells.compactMap { $0 as? PledgePaymentMethodCell }
            .forEach { $0.setSelectedCardId(selectedCardId) }
        }
      case let .notifyDelegateLoadPaymentMethodsError(message):
        self.messageDisplayingDelegate?.pledgeViewController(self, didErrorWith: message, error: nil)
      case let .notifyDelegateCreditCardSelected(payment):
        self.delegate?.pledgePaymentMethodsViewController(self, didSelectCreditCard: payment)
      case let .goToAddCardViaStripeScreen(data): self.goToPaymentSheet(data: data)
      case let .updateAddNewCardLoading(loading): self.updateAddNewPaymentMethodButtonLoading(state: loading)
      }
    }
  }

  // MARK: - Configuration

  func configure(with value: PledgePaymentMethodsValue) {
    self.viewModel.configure(with: value)
  }

  // MARK: - Functions

  private func goToPaymentSheet(data: PaymentSheetSetupData) {
    let session = AppModel.shared.sessionFeature
    let generation = session.generation
    self.paymentSheet.start(
      clientSecret: data.clientSecret, client: StripePaymentSheetClient(data: data),
      presenter: self, retrievePaymentMethod: true,
      isCurrent: { [weak self] in
        guard let self, session.generation == generation,
          let top = self.navigationController?.topViewController else { return false }
        return self.parent === top && (top is PledgeViewController || top is PostCampaignCheckoutViewController)
      },
      didPresent: { [weak self] in self?.viewModel.stripePaymentSheetDidAppear() },
      completed: { [weak self] result in
        guard let self else { return }
        self.viewModel.shouldCancelPaymentSheetAppearance(state: true)
        switch result {
        case let .completed(method):
          self.viewModel.paymentSheetDidAdd(clientSecret: data.clientSecret, paymentMethod: method)
        case .noSelection, .canceled: break
        case let .failed(error), let .loadFailed(error):
          self.messageDisplayingDelegate?
            .pledgeViewController(self, didErrorWith: error.localizedDescription, error: error)
        }
      }
    )
  }

  private func updateAddNewPaymentMethodButtonLoading(state: Bool) {
    self.dataSource.updateAddNewPaymentCardLoad(state: state)

    if self.dataSource.numberOfItems(in: PaymentMethodsTableViewSection.addNewCard.rawValue) > 0 {
      self.tableView.reloadSections([PaymentMethodsTableViewSection.addNewCard.rawValue], with: .none)
    }
  }

  // MARK: - Public functions

  func cancelModalPresentation(_ hidden: Bool) {
    if hidden { self.paymentSheet.cancelBeforePresentation() }
    self.viewModel.shouldCancelPaymentSheetAppearance(state: hidden)
  }
}

// MARK: - UITableViewDelegate

extension PledgePaymentMethodsViewController: UITableViewDelegate {
  func tableView(_: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
    guard !self.dataSource.isLoadingStateCell(indexPath: indexPath) else {
      return nil
    }
    return self.viewModel.willSelectRowAtIndexPath(indexPath)
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)

    self.viewModel.didSelectRowAtIndexPath(indexPath)
  }
}
