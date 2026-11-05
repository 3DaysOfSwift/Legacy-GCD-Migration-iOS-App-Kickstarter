import Foundation
import KsApi
import StripePaymentSheet

@MainActor
final class PaymentMethodSettingsViewModel {
  enum Event {
    case cancelAddNewCardLoadingState, editButtonIsEnabled(Bool), editButtonTitle(String)
    case errorLoadingPaymentMethodsOrSetupIntent(String), goToPaymentSheet(PaymentSheetSetupData)
    case paymentMethods([UserCreditCards.CreditCard]), presentBanner(String), reloadData
    case setStripePublishableKey(String), showAlert(String), tableViewIsEditing(Bool)
  }
  var onEvent: ((Event) -> Void)?
  let stripeIntentService: StripeIntentServiceType
  private let sleep: @MainActor (TimeInterval) async throws -> Void
  private var loadTask: Task<Void, Never>?
  private var deleteTask: Task<Void, Never>?
  private var storeTask: Task<Void, Never>?
  private var setupTask: Task<Void, Never>?
  private var isEditing = false
  private var hasEditingState = false
  private var enabled: Bool?
  private var shouldCancel = false
  private var latestCards: [UserCreditCards.CreditCard]?

  init(stripeIntentService: StripeIntentServiceType,
       sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { seconds in
         if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
       }) {
    self.stripeIntentService = stripeIntentService
    self.sleep = sleep
  }
  deinit {
    self.loadTask?.cancel(); self.deleteTask?.cancel(); self.storeTask?.cancel(); self.setupTask?.cancel()
  }
  private struct PresentationSession {
    let userID: Int?
    let generation: Int
  }
  private var presentationSession: PresentationSession {
    let session = self.stripeIntentService.paymentsFeature.sessionFeature
    return PresentationSession(userID: session.currentUser?.id, generation: session.generation)
  }
  private func isCurrent(_ identity: PresentationSession) -> Bool {
    self.stripeIntentService.paymentsFeature.sessionFeature.isCurrent(
      userID: identity.userID, generation: identity.generation
    )
  }
  func viewDidLoad() {
    self.onEvent?(.reloadData)
    self.setEnabled(false)
    self.onEvent?(.setStripePublishableKey(AppEnvironment.current.environmentType.stripePublishableKey))
    self.loadCards()
  }
  func failedToAddNewCard() { self.loadCards() }
  private func loadCards() {
    self.loadTask?.cancel()
    let feature = self.stripeIntentService.paymentsFeature
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let sleep = self.sleep
    let identity = self.presentationSession
    self.loadTask = Task { [weak self] in
      guard self?.isCurrent(identity) == true else { return }
      do {
        let cards = try await feature.cards().me.storedCards.storedCards
        try await sleep(delay)
        try Task.checkCancellation()
        guard let self, self.isCurrent(identity) else { return }
        self.latestCards = cards
        self.onEvent?(.paymentMethods(cards))
        self.setEnabled(!cards.isEmpty)
      } catch {
        do { try await sleep(delay) } catch { return }
        guard !Task.isCancelled, !(error is CancellationError), let self, self.isCurrent(identity) else { return }
        self.reportError(error)
      }
    }
  }
  func didDelete(_ card: UserCreditCards.CreditCard, visibleCellCount: Int) {
    self.setEnabled(visibleCellCount > 0)
    self.deleteTask?.cancel()
    let feature = self.stripeIntentService.paymentsFeature
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let sleep = self.sleep
    let identity = self.presentationSession
    self.deleteTask = Task { [weak self] in
      guard self?.isCurrent(identity) == true else { return }
      do {
        let cards = try await feature.remove(id: card.id).storedCards
        try await sleep(delay)
        try Task.checkCancellation()
        guard let self, self.isCurrent(identity) else { return }
        self.latestCards = cards
        self.setEnabled(!cards.isEmpty)
      } catch {
        do { try await sleep(delay) } catch { return }
        guard !Task.isCancelled, !(error is CancellationError), let self, self.isCurrent(identity) else { return }
        self.onEvent?(.showAlert(Strings.Something_went_wrong_and_we_were_unable_to_remove_your_payment_method_please_try_again()))
        if let cards = self.latestCards { self.onEvent?(.paymentMethods(cards)); self.setEnabled(!cards.isEmpty) }
      }
    }
  }
  func editButtonTapped() {
    guard self.hasEditingState else { return }
    self.setEditing(!self.isEditing)
  }
  func paymentMethodsFooterViewDidTapAddNewCardButton() {
    self.shouldCancel = false
    self.setupTask?.cancel()
    let service = self.stripeIntentService
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let sleep = self.sleep
    let identity = self.presentationSession
    self.setupTask = Task { [weak self] in
      guard self?.isCurrent(identity) == true else { return }
      do {
        let envelope = try await service.setupIntent(for: nil, context: .profileSettings)
        try await sleep(1 + delay)
        try Task.checkCancellation()
        guard let self, self.isCurrent(identity), !self.shouldCancel else { return }
        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = Strings.general_accessibility_kickstarter()
        configuration.allowsDelayedPaymentMethods = true
        configuration.defaultBillingDetails.email = AppEnvironment.current.currentUserEmail
        self.onEvent?(.goToPaymentSheet(PaymentSheetSetupData(clientSecret: envelope.clientSecret, configuration: configuration)))
        self.setEditing(false)
      } catch {
        do { try await sleep(delay) } catch { return }
        guard !Task.isCancelled, !(error is CancellationError), let self, self.isCurrent(identity) else { return }
        self.reportError(error)
      }
    }
  }
  func paymentSheetDidAdd(setupIntent: String) {
    self.storeTask?.cancel()
    let feature = self.stripeIntentService.paymentsFeature
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let sleep = self.sleep
    let identity = self.presentationSession
    self.storeTask = Task { [weak self] in
      guard self?.isCurrent(identity) == true else { return }
      do {
        _ = try await feature.store(secret: setupIntent)
        try await sleep(delay)
        try Task.checkCancellation()
        guard let self, self.isCurrent(identity) else { return }
        self.addNewCardSucceeded(with: Strings.Got_it_your_changes_have_been_saved())
      } catch {
        do { try await sleep(delay) } catch { return }
        guard !Task.isCancelled, !(error is CancellationError), let self, self.isCurrent(identity) else { return }
        self.reportError(error)
      }
    }
  }
  func addNewCardSucceeded(with message: String) {
    self.onEvent?(.presentBanner(message))
    self.shouldCancelPaymentSheetAppearance(state: true)
    self.loadCards()
  }
  func shouldCancelPaymentSheetAppearance(state: Bool) {
    self.shouldCancel = state
    if state { self.onEvent?(.cancelAddNewCardLoadingState) }
  }
  private func reportError(_ error: Error) {
    let message = ((error as? ErrorEnvelope) ?? .couldNotParseJSON).localizedDescription
    self.onEvent?(.errorLoadingPaymentMethodsOrSetupIntent(message))
    self.shouldCancelPaymentSheetAppearance(state: true)
  }
  private func setEnabled(_ enabled: Bool) {
    guard self.enabled != enabled else { return }
    self.enabled = enabled
    self.onEvent?(.editButtonIsEnabled(enabled))
    if !enabled { self.setEditing(false) }
  }
  private func setEditing(_ editing: Bool) {
    self.hasEditingState = true
    self.isEditing = editing
    self.onEvent?(.tableViewIsEditing(editing))
    self.onEvent?(.editButtonTitle(editing ? Strings.Done() : Strings.discovery_favorite_categories_buttons_edit()))
  }
  func waitForPending() async {
    await self.setupTask?.value
    await self.deleteTask?.value
    await self.storeTask?.value
    await self.loadTask?.value
  }
}
