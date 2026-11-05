import KsApi
import Observation

@MainActor
@Observable
public final class PaymentMethodsUseCase {
  public private(set) var selectedPaymentSource: PaymentSourceSelected?
  public private(set) var paymentMethodsViewHidden = true
  public private(set) var paymentMethodChangedAndValid = false
  var onHidden: ((Bool) -> Void)?
  var onConfiguration: ((PledgePaymentMethodsValue) -> Void)?
  var onSelected: ((PaymentSourceSelected?) -> Void)?
  var onValidity: ((Bool) -> Void)?
  private var data: PledgeViewData?
  private var lastLogin: Bool?
  private var lastSelectedCard: PaymentSourceSelected?

  public init() {}

  public func configure(_ data: PledgeViewData) {
    self.data = data
    self.lastLogin = AppEnvironment.current.currentUser != nil
    self.sendConfigurationIfAvailable()
    self.publishHidden()
    self.selectedPaymentSource = nil
    self.onSelected?(nil)
    let context = data.context
    self.publishValidity(context.isUpdating && (context == .updateReward || context == .editPledgeOverTime))
    if let source = self.lastSelectedCard, let reward = data.rewards.first {
      self.publishValidity(paymentMethodValid(project: data.project, reward: reward, paymentSource: source, context: context))
    }
  }

  public func loginChanged(_ loggedIn: Bool) {
    guard self.lastLogin != loggedIn else { return }
    self.lastLogin = loggedIn
    if loggedIn { self.sendConfigurationIfAvailable() }
    self.publishHidden()
  }

  public func creditCardSelected(with source: PaymentSourceSelected) {
    self.lastSelectedCard = source
    self.selectedPaymentSource = source
    self.onSelected?(source)
    guard let data = self.data, let reward = data.rewards.first else { return }
    self.publishValidity(paymentMethodValid(project: data.project, reward: reward, paymentSource: source, context: data.context))
  }

  private func sendConfigurationIfAvailable() {
    guard let data = self.data, !data.context.paymentMethodsViewHidden,
          let reward = data.rewards.first, let user = AppEnvironment.current.currentUser else { return }
    self.onConfiguration?((user, data.project, "", reward, data.context, data.refTag))
  }

  private func publishHidden() {
    guard let data = self.data, let loggedIn = self.lastLogin else { return }
    let hidden = !loggedIn || data.context.paymentMethodsViewHidden
    self.paymentMethodsViewHidden = hidden
    self.onHidden?(hidden)
  }

  private func publishValidity(_ valid: Bool) {
    self.paymentMethodChangedAndValid = valid
    self.onValidity?(valid)
  }
}

private func paymentMethodValid(
  project: Project,
  reward: Reward,
  paymentSource: PaymentSourceSelected,
  context: PledgeViewContext
) -> Bool {
  guard
    let backedPaymentSourceId = project.personalization.backing?.paymentSource?.id,
    context.isUpdating,
    userIsBacking(reward: reward, inProject: project)
  else {
    return true
  }

  if project.personalization.backing?.status == .errored {
    return true
  } else if backedPaymentSourceId != paymentSource.savedCreditCardId {
    return true
  }

  return false
}
