import KsApi
import Prelude
import ReactiveExtensions
import ReactiveSwift
import UIKit

public typealias ThanksPageData = (
  project: Project,
  reward: Reward,
  checkoutData: KSRAnalytics.CheckoutPropertiesData?,
  pledgeTotal: Double
)

@MainActor
public protocol ThanksViewModelInputs {
  /// Call to configure the VM
  func configure(with data: ThanksPageData)

  /// Call when close button is tapped
  func closeButtonTapped()

  /// Call when category cell is tapped
  func categoryCellTapped(_ category: KsApi.Category)

  /// Call when project cell is tapped
  func projectTapped(_ project: Project)

  /// Call when signup button is tapped on games newsletter alert
  func gamesNewsletterSignupButtonTapped()

  /// Call when the current user has been updated in the environment
  func userUpdated()

  /// Call when the view controller view did load
  func viewDidLoad()
}

@MainActor
public protocol ThanksViewModelOutputs {
  /// Emits backed project subheader text to display
  var backedProjectText: Signal<NSAttributedString, Never> { get }

  /// Emits when view controller should dismiss
  var postProjectBackedNotification: Signal<Notification, Never> { get }

  /// Emits DiscoveryParams when should go to Discovery
  var goToDiscovery: Signal<DiscoveryParams, Never> { get }

  /// Emits project when should go to Project page
  var goToProject: Signal<(Project, [Project], RefTag), Never> { get }

  /// Emits when a user pledges a project for the first time.
  var postContextualNotification: Signal<(), Never> { get }

  /// Emits when a user updated notification should be posted
  var postUserUpdatedNotification: Signal<Notification, Never> { get }

  /// Emits when should show games newsletter alert
  var showGamesNewsletterAlert: Signal<(), Never> { get }

  /// Emits newsletter title when should show games newsletter opt-in alert
  var showGamesNewsletterOptInAlert: Signal<String, Never> { get }

  /// Emits when should show rating alert
  var showRatingAlert: Signal<(), Never> { get }

  /// Emits array of projects and a category when should show recommendations
  var showRecommendations: Signal<([Project], KsApi.Category), Never> { get }

  /// Emits a User that can be used to replace the current user in the environment
  var updateUserInEnvironment: Signal<User, Never> { get }
}

@MainActor
public protocol ThanksViewModelType {
  var inputs: ThanksViewModelInputs { get }
  var outputs: ThanksViewModelOutputs { get }
}

@MainActor
public final class ThanksViewModel: ThanksViewModelType, ThanksViewModelInputs, ThanksViewModelOutputs {
  private let feature: RecommendationsFeature
  private let route = UUID()
  public init(recommendationsFeature: RecommendationsFeature? = nil) {
    let feature = recommendationsFeature ?? AppModel.shared.recommendationsFeature
    self.feature = feature
    let settingsFeature = feature.settingsFeature
    let route = self.route
    let project = self.configureWithDataProperty.signal
      .skipNil()
      .map { $0.project }

    let rewardAndCheckoutData = self.configureWithDataProperty.signal
      .skipNil()
      .map { ($0.reward, $0.checkoutData) }

    self.backedProjectText = self.configureWithDataProperty.signal
      .skipNil()
      .map { project, _, _, pledgeTotal in

        let string: String

        let totalString = Format.currency(pledgeTotal, currencyCode: project.statsCurrency)

        string = project.isInPostCampaignPledgingPhase
          ? Strings
          .You_have_successfully_pledged_to_project_post_campaign_html_short(pledge_total: totalString)
          : Strings.You_have_successfully_backed_project_html(project_name: project.name)

        return string
          .simpleHtmlAttributedString(font: UIFont.ksr_subhead(), bold: UIFont.ksr_subhead().bolded)
          ?? NSAttributedString(string: "")
      }
      .takeWhen(self.viewDidLoadProperty.signal)

    let shouldShowGamesAlert = project
      .map { project in
        project.category?.rootId == KsApi.Category.gamesId &&
          !(AppEnvironment.current.currentUser?.newsletters.games ?? false) &&
          !AppEnvironment.current.userDefaults.hasSeenGamesNewsletterPrompt
      }

    self.showGamesNewsletterAlert = shouldShowGamesAlert
      .filter(isTrue)
      .takeWhen(self.viewDidLoadProperty.signal)
      .ignoreValues()

    self.showGamesNewsletterOptInAlert = self.gamesNewsletterSignupButtonTappedProperty.signal
      .filter { AppEnvironment.current.countryCode == "DE" }
      .map(Strings.profile_settings_newsletter_games)

    self.showRatingAlert = shouldShowGamesAlert
      .filter {
        $0 == false &&
          !AppEnvironment.current.userDefaults.hasSeenAppRating &&
          AppEnvironment.current.config?.iTunesLink != nil && shouldShowPledgeDialog() == false
      }
      .takeWhen(self.viewDidLoadProperty.signal)
      .ignoreValues()
      .on(value: { AppEnvironment.current.userDefaults.hasSeenAppRating = true })

    self.postProjectBackedNotification = self.closeButtonTappedProperty.signal
      .mapConst(Notification(name: .ksr_projectBacked))

    self.goToDiscovery = self.categoryCellTappedProperty.signal.skipNil()
      .map {
        DiscoveryParams.defaults |> DiscoveryParams.lens.category .~ $0
      }

    self.showRecommendations = feature.selections
      .filter { $0.0 == route }
      .compactMap { _, selection in
        selection.category.map { (selection.projects, $0) }
      }
    project.observeValues { feature.request(.afterBacking($0), route: route) }

    self.goToProject = self.showRecommendations
      .map(first)
      .takePairWhen(self.projectTappedProperty.signal.skipNil())
      .map { projects, project in (project, projects, RefTag.thanks) }

    self.updateUserInEnvironment = self.gamesNewsletterSignupButtonTappedProperty.signal
      .map { AppEnvironment.current.currentUser ?? nil }
      .skipNil()
      .switchMap { user in
        settingsFeature.saveResult([.init(.newsletter(.games), true)], from: user)
          .ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
          .demoteErrors()
      }

    self.postContextualNotification = self.viewDidLoadProperty.signal
      .filter { shouldShowPledgeDialog() }

    self.postUserUpdatedNotification = self.userUpdatedProperty.signal
      .mapConst(Notification(name: .ksr_userUpdated))

    self.showGamesNewsletterAlert
      .observeValues { AppEnvironment.current.userDefaults.hasSeenGamesNewsletterPrompt = true }

    self.projectTappedProperty.signal.skipNil()
      .map { project in (project, RecommendationsFeature.recommendedParameters) }
      .combineLatest(with: rewardAndCheckoutData)
      .observeValues { projectAndParams, rewardAndCheckoutData in
        let (project, params) = projectAndParams
        let (reward, checkoutData) = rewardAndCheckoutData

        AppEnvironment.current.ksrAnalytics.trackProjectCardClicked(
          page: .thanks,
          project: project,
          checkoutData: checkoutData,
          typeContext: .recommended,
          location: .curated,
          params: params,
          reward: reward
        )
      }

    Signal.combineLatest(
      self.configureWithDataProperty.signal.skipNil(),
      self.viewDidLoadProperty.signal.ignoreValues()
    )
    .map(first)
    .observeValues { AppEnvironment.current.ksrAnalytics.trackThanksPageViewed(
      project: $0.project,
      reward: $0.reward,
      checkoutData: $0.checkoutData
    ) }

    // Facebook CAPI + Google Analytics
    _ = Signal.combineLatest(
      project,
      self.configureWithDataProperty.signal.skipNil()
    )
    .observeValues { project, configData in
      var pledgeAmount: Double?
      var shipping: Double?
      var transactionId: String?

      if let checkoutDataValues = configData.checkoutData {
        transactionId = checkoutDataValues.checkoutId
        shipping = checkoutDataValues.shippingAmountUsd
        pledgeAmount = NSDecimalNumber(decimal: checkoutDataValues.revenueInUsd).doubleValue
          + NSDecimalNumber(decimal: checkoutDataValues.bonusAmountInUsd ?? 0).doubleValue
          + checkoutDataValues.addOnsMinimumUsd
      }

      AppEnvironment.current.appTrackingTransparency.updateAdvertisingIdentifier()

      guard let externalId = AppEnvironment.current.appTrackingTransparency.advertisingIdentifier
      else { return }

      var userId = ""

      if let userValue = AppEnvironment.current.currentUser {
        userId = "\(userValue.id)"
      }

      let projectId = "\(project.id)"

      var extInfo = Array(repeating: "", count: 16)
      extInfo[0] = "i2"
      extInfo[4] = AppEnvironment.current.mainBundle.platformVersion

      _ = AppEnvironment.current.apiService
        .triggerThirdPartyEventInput(input: .init(
          deviceId: externalId,
          eventName: ThirdPartyEventInputName.BackingComplete.rawValue,
          projectId: projectId,
          pledgeAmount: pledgeAmount,
          shipping: shipping,
          transactionId: transactionId,
          userId: userId,
          appData: .init(
            advertiserTrackingEnabled: true,
            applicationTrackingEnabled: true,
            extinfo: extInfo
          ),
          clientMutationId: ""
        ))
    }
  }

  deinit {
    let feature = self.feature
    let route = self.route
    Task { @MainActor in feature.release(route: route) }
  }

  // MARK: - ThanksViewModelType

  public var inputs: ThanksViewModelInputs { return self }
  public var outputs: ThanksViewModelOutputs { return self }

  // MARK: - ThanksViewModelInputs

  fileprivate let configureWithDataProperty = MutableProperty<ThanksPageData?>(nil)
  public func configure(with data: ThanksPageData) {
    self.configureWithDataProperty.value = data
  }

  fileprivate let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
  }

  fileprivate let closeButtonTappedProperty = MutableProperty(())
  public func closeButtonTapped() {
    self.feature.release(route: self.route)
    self.closeButtonTappedProperty.value = ()
  }

  fileprivate let categoryCellTappedProperty = MutableProperty<KsApi.Category?>(nil)
  public func categoryCellTapped(_ category: KsApi.Category) {
    self.categoryCellTappedProperty.value = category
  }

  fileprivate let projectTappedProperty = MutableProperty<Project?>(nil)
  public func projectTapped(_ project: Project) {
    self.projectTappedProperty.value = project
  }

  fileprivate let gamesNewsletterSignupButtonTappedProperty = MutableProperty(())
  public func gamesNewsletterSignupButtonTapped() {
    self.gamesNewsletterSignupButtonTappedProperty.value = ()
  }

  fileprivate let userUpdatedProperty = MutableProperty(())
  public func userUpdated() {
    self.userUpdatedProperty.value = ()
  }

  // MARK: - ThanksViewModelOutputs

  public let postProjectBackedNotification: Signal<Notification, Never>
  public let goToDiscovery: Signal<DiscoveryParams, Never>
  public let backedProjectText: Signal<NSAttributedString, Never>
  public let goToProject: Signal<(Project, [Project], RefTag), Never>
  public let postContextualNotification: Signal<(), Never>
  public let postUserUpdatedNotification: Signal<Notification, Never>
  public let showRatingAlert: Signal<(), Never>
  public let showGamesNewsletterAlert: Signal<(), Never>
  public let showGamesNewsletterOptInAlert: Signal<String, Never>
  public let showRecommendations: Signal<([Project], KsApi.Category), Never>
  public let updateUserInEnvironment: Signal<User, Never>
}

private func shouldShowPledgeDialog() -> Bool {
  return PushNotificationDialog.canShowDialog(for: .pledge) &&
    AppEnvironment.current.currentUser?.stats.backedProjectsCount == 0
}
