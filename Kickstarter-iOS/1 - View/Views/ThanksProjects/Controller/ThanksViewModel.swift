import KsApi
import Prelude
import UIKit

public typealias ThanksPageData = (
  project: Project, reward: Reward, checkoutData: KSRAnalytics.CheckoutPropertiesData?, pledgeTotal: Double
)

@MainActor
final class ThanksViewModel {
  enum Event {
    case backedProjectText(NSAttributedString), postProjectBackedNotification(Notification)
    case goToDiscovery(DiscoveryParams), goToProject(Project, [Project], RefTag)
    case postContextualNotification, postUserUpdatedNotification(Notification)
    case showGamesNewsletterAlert, showGamesNewsletterOptInAlert(String), showRatingAlert
    case showRecommendations([Project], KsApi.Category), updateUserInEnvironment(User)
  }
  var onEvent: ((Event) -> Void)?
  private let feature: RecommendationsFeature
  private let route = UUID()
  private let sleep: @MainActor (TimeInterval) async throws -> Void
  private var recommendationTask: Task<Void, Never>?
  private var recommendationRevision = UUID()
  private var newsletterTask: Task<Void, Never>?
  private var data: ThanksPageData?
  private var recommendedProjects: [Project]?

  init(recommendationsFeature: RecommendationsFeature? = nil,
       sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { seconds in
         if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
       }) {
    self.feature = recommendationsFeature ?? AppModel.shared.recommendationsFeature
    self.sleep = sleep
  }
  deinit {
    self.recommendationTask?.cancel()
    self.newsletterTask?.cancel()
    let feature = self.feature
    let route = self.route
    Task { @MainActor in feature.release(route: route) }
  }

  func configure(with data: ThanksPageData) {
    self.data = data
    self.trackBackingComplete(data)
    self.recommendationTask?.cancel()
    let revision = UUID()
    self.recommendationRevision = revision
    let feature = self.feature
    let route = self.route
    let session = feature.sessionFeature
    let userID = session.currentUser?.id
    let generation = session.generation
    let command = feature.request(.afterBacking(data.project), route: route)
    self.recommendationTask = Task { [weak self] in
      await command.value
      guard !Task.isCancelled, let self, self.recommendationRevision == revision,
            session.isCurrent(userID: userID, generation: generation),
            let selection = feature.selection(route: route), let category = selection.category else { return }
      self.recommendedProjects = selection.projects
      self.onEvent?(.showRecommendations(selection.projects, category))
    }
  }
  func waitForRecommendations() async { await self.recommendationTask?.value }
  func waitForNewsletter() async { await self.newsletterTask?.value }

  func viewDidLoad() {
    if let data = self.data {
      let project = data.project
      let total = Format.currency(data.pledgeTotal, currencyCode: project.statsCurrency)
      let text = project.isInPostCampaignPledgingPhase
        ? Strings.You_have_successfully_pledged_to_project_post_campaign_html_short(pledge_total: total)
        : Strings.You_have_successfully_backed_project_html(project_name: project.name)
      self.onEvent?(.backedProjectText(text.simpleHtmlAttributedString(font: UIFont.ksr_subhead(), bold: UIFont.ksr_subhead().bolded) ?? NSAttributedString(string: "")))
      let gamesAlert = project.category?.rootId == KsApi.Category.gamesId &&
        !(AppEnvironment.current.currentUser?.newsletters.games ?? false) &&
        !AppEnvironment.current.userDefaults.hasSeenGamesNewsletterPrompt
      if gamesAlert {
        AppEnvironment.current.userDefaults.hasSeenGamesNewsletterPrompt = true
        self.onEvent?(.showGamesNewsletterAlert)
      } else if !AppEnvironment.current.userDefaults.hasSeenAppRating &&
                  AppEnvironment.current.config?.iTunesLink != nil && !shouldShowPledgeDialog() {
        AppEnvironment.current.userDefaults.hasSeenAppRating = true
        self.onEvent?(.showRatingAlert)
      }
      AppEnvironment.current.ksrAnalytics.trackThanksPageViewed(project: project, reward: data.reward, checkoutData: data.checkoutData)
    }
    if shouldShowPledgeDialog() { self.onEvent?(.postContextualNotification) }
  }
  func closeButtonTapped() {
    self.recommendationRevision = UUID()
    self.recommendationTask?.cancel()
    self.feature.release(route: self.route)
    self.onEvent?(.postProjectBackedNotification(Notification(name: .ksr_projectBacked)))
  }
  func categoryCellTapped(_ category: KsApi.Category) {
    self.onEvent?(.goToDiscovery(DiscoveryParams.defaults |> DiscoveryParams.lens.category .~ category))
  }
  func projectTapped(_ project: Project) {
    if let projects = self.recommendedProjects { self.onEvent?(.goToProject(project, projects, .thanks)) }
    if let data = self.data {
      AppEnvironment.current.ksrAnalytics.trackProjectCardClicked(page: .thanks, project: project, checkoutData: data.checkoutData, typeContext: .recommended, location: .curated, params: RecommendationsFeature.recommendedParameters, reward: data.reward)
    }
  }
  func gamesNewsletterSignupButtonTapped() {
    if AppEnvironment.current.countryCode == "DE" {
      self.onEvent?(.showGamesNewsletterOptInAlert(Strings.profile_settings_newsletter_games()))
    }
    guard let user = AppEnvironment.current.currentUser else { return }
    self.newsletterTask?.cancel()
    let settings = self.feature.settingsFeature
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let sleep = self.sleep
    self.newsletterTask = Task { [weak self] in
      do {
        let updated = try await settings.save([.init(.newsletter(.games), true)], from: user)
        try await sleep(delay)
        try Task.checkCancellation()
        self?.onEvent?(.updateUserInEnvironment(updated))
      } catch { }
    }
  }
  func userUpdated() { self.onEvent?(.postUserUpdatedNotification(Notification(name: .ksr_userUpdated))) }

  private func trackBackingComplete(_ data: ThanksPageData) {
    var pledgeAmount: Double?
    var shipping: Double?
    var transactionId: String?
    if let checkout = data.checkoutData {
      transactionId = checkout.checkoutId
      shipping = checkout.shippingAmountUsd
      pledgeAmount = NSDecimalNumber(decimal: checkout.revenueInUsd).doubleValue
        + NSDecimalNumber(decimal: checkout.bonusAmountInUsd ?? 0).doubleValue + checkout.addOnsMinimumUsd
    }
    AppEnvironment.current.appTrackingTransparency.updateAdvertisingIdentifier()
    guard let externalId = AppEnvironment.current.appTrackingTransparency.advertisingIdentifier else { return }
    let userId = AppEnvironment.current.currentUser.map { "\($0.id)" } ?? ""
    var extInfo = Array(repeating: "", count: 16)
    extInfo[0] = "i2"
    extInfo[4] = AppEnvironment.current.mainBundle.platformVersion
    _ = AppEnvironment.current.apiService.triggerThirdPartyEventInput(input: .init(
      deviceId: externalId, eventName: ThirdPartyEventInputName.BackingComplete.rawValue,
      projectId: "\(data.project.id)", pledgeAmount: pledgeAmount, shipping: shipping,
      transactionId: transactionId, userId: userId,
      appData: .init(advertiserTrackingEnabled: true, applicationTrackingEnabled: true, extinfo: extInfo),
      clientMutationId: ""
    ))
  }
}

@MainActor
private func shouldShowPledgeDialog() -> Bool {
  return PushNotificationDialog.canShowDialog(for: .pledge) &&
    AppEnvironment.current.currentUser?.stats.backedProjectsCount == 0
}
