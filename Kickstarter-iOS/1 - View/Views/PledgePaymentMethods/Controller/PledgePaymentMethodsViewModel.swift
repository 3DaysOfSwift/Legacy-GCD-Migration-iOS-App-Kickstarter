import GraphAPI
import KsApi
import PassKit
import Prelude
import StripePaymentSheet
import UIKit

public enum PaymentMethodsTableViewSection: Int {
  case paymentMethods
  case addNewCard
  case loading
}

public typealias PledgePaymentMethodsValue = (
  user: User,
  project: Project,
  checkoutId: String, /// Used for creating Payment Intents in the Late Pledge flow.
  reward: Reward,
  context: PledgeViewContext,
  refTag: RefTag?
)

public typealias PaymentSheetSetupData = (
  clientSecret: String,
  configuration: PaymentSheet.Configuration
)

@MainActor
final class PledgePaymentMethodsViewModel {
  enum Event {
    case goToAddCardViaStripeScreen(PaymentSheetSetupData)
    case notifyDelegateCreditCardSelected(PaymentSourceSelected)
    case notifyDelegateLoadPaymentMethodsError(String)
    case reloadPaymentMethods(PledgePaymentMethodsAndSelectionData)
    case updateAddNewCardLoading(Bool)
  }
  var onEvent: ((Event) -> Void)?
  let stripeIntentService: StripeIntentServiceType
  private let sleep: @MainActor (TimeInterval) async throws -> Void
  private var configuration: PledgePaymentMethodsValue?
  private var loaded = false
  private var cardsTask: Task<Void, Never>?
  private var setupTask: Task<Void, Never>?
  private var storeTask: Task<Void, Never>?
  private var shouldCancel = true
  private var cancellationKnown = false
  private var initialCards: PledgePaymentMethodsAndSelectionData?
  private var currentCards: PledgePaymentMethodsAndSelectionData?
  private var newCards: [UserCreditCards.CreditCard] = []
  private var lastSelection: PaymentSourceSelected?

  init(stripeIntentService: StripeIntentServiceType,
       sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { seconds in
         if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
       }) {
    self.stripeIntentService = stripeIntentService
    self.sleep = sleep
  }
  deinit { self.cardsTask?.cancel(); self.setupTask?.cancel(); self.storeTask?.cancel() }
  private struct SessionIdentity { let userID: Int?; let generation: Int }
  private var sessionIdentity: SessionIdentity {
    let session = self.stripeIntentService.paymentsFeature.sessionFeature
    return SessionIdentity(userID: session.currentUser?.id, generation: session.generation)
  }
  private func isCurrent(_ identity: SessionIdentity) -> Bool {
    self.stripeIntentService.paymentsFeature.sessionFeature.isCurrent(userID: identity.userID, generation: identity.generation)
  }
  func configure(with value: PledgePaymentMethodsValue) {
    self.configuration = value
    if self.loaded { self.loadCards() }
    if self.loaded, self.cancellationKnown { self.onEvent?(.updateAddNewCardLoading(!self.shouldCancel)) }
  }
  func viewDidLoad() {
    self.loaded = true
    if self.configuration != nil {
      self.loadCards()
      if self.cancellationKnown { self.onEvent?(.updateAddNewCardLoading(!self.shouldCancel)) }
    }
  }
  private func loadCards() {
    guard let config = self.configuration else { return }
    self.cardsTask?.cancel()
    let identity = self.sessionIdentity
    self.publish(PledgePaymentMethodsAndSelectionData(existingPaymentMethods: [], newPaymentMethods: [], selectedPaymentMethod: nil, isLoading: true, shouldReload: true))
    let feature = self.stripeIntentService.paymentsFeature
    let sleep = self.sleep
    self.cardsTask = Task { [weak self] in
      guard self?.isCurrent(identity) == true else { return }
      do {
        let result = try await feature.cards()
        try await sleep(1)
        try Task.checkCancellation()
        guard let self, self.isCurrent(identity), let types = config.project.availableCardTypes else { return }
        let ordered = cards(result.me.storedCards.storedCards, orderedBy: config.project.personalization.backing)
        let (data, selected) = pledgePaymentMethodCellDataAndSelectedCard(with: ordered, availableCardTypes: types, project: config.project, newCardAdded: false)
        let selectedPayment = selected.map(createSelectedPaymentMethod(from:))
        let configured = PledgePaymentMethodsAndSelectionData(existingPaymentMethods: data, newPaymentMethods: [], selectedPaymentMethod: selectedPayment, isLoading: false, shouldReload: true)
        self.initialCards = configured
        self.publish(configured)
      } catch {
        guard !Task.isCancelled, !(error is CancellationError), let self, self.isCurrent(identity) else { return }
        self.publishError(error)
      }
    }
  }
  func paymentSheetDidAdd(clientSecret: String, paymentMethod: String?) {
    self.storeTask?.cancel()
    let identity = self.sessionIdentity
    let feature = self.stripeIntentService.paymentsFeature
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let sleep = self.sleep
    self.storeTask = Task { [weak self] in
      guard self?.isCurrent(identity) == true else { return }
      do {
        let envelope = try await feature.store(secret: clientSecret)
        try await sleep(delay)
        try Task.checkCancellation()
        guard let self, self.isCurrent(identity), envelope.createPaymentSource.isSuccessful,
              let config = self.configuration, let types = config.project.availableCardTypes else { return }
        var card = envelope.createPaymentSource.paymentSource
        if card.stripeCardId == nil { card.stripeCardId = paymentMethod }
        self.newCards.insert(card, at: 0)
        let (newData, selected) = pledgePaymentMethodCellDataAndSelectedCard(with: self.newCards, availableCardTypes: types, project: config.project, newCardAdded: true)
        guard var updated = self.initialCards else { return }
        updated.newPaymentMethods = newData
        if let selected { updated.selectedPaymentMethod = createSelectedPaymentMethod(from: selected) }
        self.publish(pledgePaymentSheetMethodCellDataAndSelectedCardSetupIntent(with: updated))
      } catch {
        do { try await sleep(delay) } catch { return }
        guard !Task.isCancelled, !(error is CancellationError), let self, self.isCurrent(identity) else { return }
        self.publishError(error)
      }
    }
  }
  func shouldCancelPaymentSheetAppearance(state: Bool) {
    self.shouldCancel = state
    self.cancellationKnown = true
    if self.configuration != nil, self.loaded { self.onEvent?(.updateAddNewCardLoading(!state)) }
  }
  func willSelectRowAtIndexPath(_ indexPath: IndexPath) -> IndexPath? {
    guard let data = self.currentCards, indexPath.row >= 0 else { return nil }
    if indexPath.section == PaymentMethodsTableViewSection.addNewCard.rawValue { return indexPath }
    guard indexPath.section == PaymentMethodsTableViewSection.paymentMethods.rawValue else { return nil }
    let enabled = data.newPaymentMethods.map(\.isEnabled) + data.existingPaymentMethods.map(\.isEnabled)
    return indexPath.row < enabled.count && enabled[indexPath.row] ? indexPath : nil
  }
  func didSelectRowAtIndexPath(_ indexPath: IndexPath) {
    if indexPath.section == PaymentMethodsTableViewSection.addNewCard.rawValue {
      self.startSetup()
      return
    }
    guard indexPath.section == PaymentMethodsTableViewSection.paymentMethods.rawValue,
          indexPath.row >= 0, var data = self.currentCards else { return }
    let newCount = data.newPaymentMethods.count
    let card: UserCreditCards.CreditCard
    if indexPath.row < newCount {
      card = data.newPaymentMethods[indexPath.row].card
      data.newPaymentMethods = cellData(data.newPaymentMethods, selecting: card)
      data.existingPaymentMethods = cellData(data.existingPaymentMethods, selecting: nil)
    } else {
      let row = indexPath.row - newCount
      guard row < data.existingPaymentMethods.count else { return }
      card = data.existingPaymentMethods[row].card
      data.existingPaymentMethods = cellData(data.existingPaymentMethods, selecting: card)
      data.newPaymentMethods = cellData(data.newPaymentMethods, selecting: nil)
    }
    data.selectedPaymentMethod = createSelectedPaymentMethod(from: card)
    data.isLoading = false
    data.shouldReload = true
    self.shouldCancelPaymentSheetAppearance(state: true)
    self.publish(data)
  }
  private func startSetup() {
    guard self.loaded, let config = self.configuration else { return }
    self.shouldCancelPaymentSheetAppearance(state: false)
    self.setupTask?.cancel()
    let identity = self.sessionIdentity
    let service = self.stripeIntentService
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let sleep = self.sleep
    self.setupTask = Task { [weak self] in
      guard self?.isCurrent(identity) == true else { return }
      do {
        let context: GraphAPI.StripeIntentContextTypes = config.context == .latePledge ? .postCampaignCheckout : .crowdfundingCheckout
        let envelope = try await service.setupIntent(for: config.project.graphID, context: context)
        try await sleep(1 + delay)
        try Task.checkCancellation()
        guard let self, self.isCurrent(identity), !self.shouldCancel else { return }
        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = Strings.general_accessibility_kickstarter()
        configuration.allowsDelayedPaymentMethods = true
        configuration.defaultBillingDetails.email = AppEnvironment.current.currentUserEmail
        self.onEvent?(.goToAddCardViaStripeScreen((envelope.clientSecret, configuration)))
      } catch {
        do { try await sleep(delay) } catch { return }
        guard !Task.isCancelled, !(error is CancellationError), let self, self.isCurrent(identity) else { return }
        self.publishError(error)
        self.onEvent?(.updateAddNewCardLoading(false))
      }
    }
  }
  private func publish(_ data: PledgePaymentMethodsAndSelectionData) {
    self.currentCards = data
    self.onEvent?(.reloadPaymentMethods(data))
    if let selected = data.selectedPaymentMethod, self.lastSelection != selected {
      self.lastSelection = selected
      self.onEvent?(.notifyDelegateCreditCardSelected(selected))
    }
  }
  private func publishError(_ error: Error) {
    self.onEvent?(.notifyDelegateLoadPaymentMethodsError(((error as? ErrorEnvelope) ?? .couldNotParseJSON).localizedDescription))
  }
  func stripePaymentSheetDidAppear() {
    guard self.loaded, let config = self.configuration else { return }
    AppEnvironment.current.appTrackingTransparency.updateAdvertisingIdentifier()
    guard let externalId = AppEnvironment.current.appTrackingTransparency.advertisingIdentifier else { return }
    let userId = AppEnvironment.current.currentUser.map { "\($0.id)" } ?? ""
    var extInfo = Array(repeating: "", count: 16)
    extInfo[0] = "i2"
    extInfo[4] = AppEnvironment.current.mainBundle.platformVersion
    _ = AppEnvironment.current.apiService.triggerThirdPartyEventInput(input: .init(deviceId: externalId, eventName: ThirdPartyEventInputName.AddNewPaymentMethod.rawValue, projectId: "\(config.project.id)", pledgeAmount: nil, shipping: nil, transactionId: nil, userId: userId, appData: .init(advertiserTrackingEnabled: true, applicationTrackingEnabled: true, extinfo: extInfo), clientMutationId: ""))
  }
  func waitForPending() async {
    await self.cardsTask?.value
    await self.setupTask?.value
    await self.storeTask?.value
  }
}

private func pledgePaymentSheetMethodCellDataAndSelectedCardSetupIntent(
  with paymentMethodData: PledgePaymentMethodsAndSelectionData
) -> PledgePaymentMethodsAndSelectionData {
  // We know we have a new payment sheet card, so de-select all existing non-payment sheet cards.
  let preexistingCardDataUnselected: [PledgePaymentMethodCellData] = {
    paymentMethodData.existingPaymentMethods
      .compactMap { data -> PledgePaymentMethodCellData? in

        (
          card: data.card,
          isEnabled: data.isEnabled,
          isSelected: false,
          projectCountry: data.projectCountry,
          isErroredPaymentMethod: data.isErroredPaymentMethod
        )
      }
  }()

  // First ensure all existing payment sheet payment methods are not selected.
  let newCardDataUnselected: [PledgePaymentMethodCellData] = {
    var updatedNewPaymentMethodData = paymentMethodData.newPaymentMethods

    updatedNewPaymentMethodData = updatedNewPaymentMethodData.map { data in
      (
        card: data.card,
        isEnabled: data.isEnabled,
        isSelected: false,
        projectCountry: data.projectCountry,
        isErroredPaymentMethod: data.isErroredPaymentMethod
      )
    }

    return updatedNewPaymentMethodData
  }()

  let updatedDataWithSelection: PledgePaymentMethodsAndSelectionData = {
    guard let newestPaymentSheetPaymentMethod = paymentMethodData.newPaymentMethods.first,
          // If the new payment method is disabled, exit and keep the previous selection. (MBL-1550)
          newestPaymentSheetPaymentMethod.isEnabled == true
    else {
      return paymentMethodData
    }

    // We know the first new payment sheet card added is the newest one, so by default select it.
    var data = newCardDataUnselected

    var updatedSelectedPaymentSheetPaymentMethod = data[0]

    if updatedSelectedPaymentSheetPaymentMethod.isEnabled {
      updatedSelectedPaymentSheetPaymentMethod.isSelected = true
    }

    data[0] = updatedSelectedPaymentSheetPaymentMethod

    var updatePaymentMethodData = paymentMethodData
    updatePaymentMethodData.existingPaymentMethods = preexistingCardDataUnselected
    updatePaymentMethodData.newPaymentMethods = data

    if newestPaymentSheetPaymentMethod.isEnabled {
      updatePaymentMethodData
        .selectedPaymentMethod = createSelectedPaymentMethod(from: newestPaymentSheetPaymentMethod.card)
    }

    return updatePaymentMethodData
  }()

  return updatedDataWithSelection

  /**
   Unlike the existing logic inside `pledgePaymentMethodCellDataAndSelectedCard`, we don't know the card id after its' been added, because new payment sheet cards only contain an image and a redacted card number. If we did we can ensure that an errored backing does not highlight the new card if it matches the payment source id on the backing. Right now this flow only handles the latest cards from the payment sheet, so we can simply select the first one added. If this code path is taken the method above is not called again for the same instance of this view controller, the flag is lazy initialized and doesn't change while this page is displayed.
   */
}

private func pledgePaymentMethodCellDataAndSelectedCard(
  with cards: [UserCreditCards.CreditCard],
  availableCardTypes: [String],
  project: Project,
  newCardAdded: Bool
) -> ([PledgePaymentMethodCellData], UserCreditCards.CreditCard?) {
  let data = cards.compactMap { card -> PledgePaymentMethodCellData? in
    guard let cardBrand = card.type?.rawValue else { return nil }

    let backing = project.personalization.backing
    let isAvailableCardType = availableCardTypes.contains(cardBrand)

    let isErroredPaymentMethod = card.id == backing?.paymentSource?.id && backing?.status == .errored

    return (
      card: card,
      isEnabled: isAvailableCardType,
      isSelected: false,
      projectCountry: project.location?.displayableName ?? "",
      isErroredPaymentMethod: isErroredPaymentMethod
    )
  }
  // Position unavailable cards last
  .sorted { data1, data2 -> Bool in data1.isEnabled && !data2.isEnabled }

  let orderedCards = data.map { $0.card }

  // If there is no backing, simply select the first card in the list when it is an available card type.
  guard let backing = project.personalization.backing else {
    guard let cardData = data.first, cardData.isEnabled else {
      return (data, nil)
    }

    let selected = orderedCards.first

    return (cellData(data, selecting: selected), selected)
  }

  // If we're working with a backing, but we have a newly added card, select the newly added card.
  if newCardAdded {
    let selected = orderedCards.first

    return (cellData(data, selecting: selected), selected)
  }

  if cards.first(where: { $0.id == backing.paymentSource?.id }) != nil, backing.status == .errored {
    return (data, nil)
  }

  /*
   If we're working with a backing, and a new card hasn't been added,
   select the card that the backing is associated with.
   */
  let backedCard = orderedCards.first(where: { $0.id == backing.paymentSource?.id })

  return (cellData(data, selecting: backedCard), backedCard)
}

private func cellData(
  _ data: [PledgePaymentMethodCellData],
  selecting card: UserCreditCards.CreditCard?
) -> [PledgePaymentMethodCellData] {
  return data.map { value in
    (
      value.card,
      value.isEnabled,
      value.card == card,
      value.projectCountry,
      value.isErroredPaymentMethod
    )
  }
}

private func isCreatingPledge(_ project: Project) -> Bool {
  guard let isBacking = project.personalization.isBacking else { return true }

  return !isBacking
}

private func cards(
  _ cards: [UserCreditCards.CreditCard],
  orderedBy backing: Backing?
) -> [UserCreditCards.CreditCard] {
  return cards.sorted { card1, _ in card1.id == backing?.paymentSource?.id }
}

private func createSelectedPaymentMethod(from card: UserCreditCards.CreditCard) -> PaymentSourceSelected {
  guard let stripeCardId = card.stripeCardId, !stripeCardId.isEmpty else {
    assert(false, "Expected stripeCardId to be set. Late pledges may fail if this value is missing.")
    return .savedCreditCard(card.id, nil)
  }

  return .savedCreditCard(card.id, stripeCardId)
}
