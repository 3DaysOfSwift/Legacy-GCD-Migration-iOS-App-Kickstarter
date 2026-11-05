@testable import Kickstarter_iOS
// swiftlint:disable file_length

@testable import KsApi


import Prelude
import UIKit
import XCTest

// swiftlint:disable:next type_body_length
@MainActor
final class ThanksViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let settingsFeature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var feature = RecommendationsFeature(settingsFeature: self.settingsFeature,
    makeProvider: { AsyncRecommendationsProvider(service: AppEnvironment.current.apiService) })
  private lazy var vm: ThanksViewModel = ThanksViewModel(recommendationsFeature: self.feature, sleep: { _ in try Task.checkCancellation() })
  private let categoryEnvelope = CategoryEnvelope(node: .template)

  private let backedProjectText = ThanksRecorder<String>()
  private let postBackedNotification = ThanksRecorder<Notification.Name>()
  private let goToDiscovery = ThanksRecorder<KsApi.Category>()
  private let goToProject = ThanksRecorder<Project>()
  private let goToProjects = ThanksRecorder<[Project]>()
  private let goToRefTag = ThanksRecorder<RefTag>()
  private let showRatingAlert = ThanksRecorder<()>()
  private let showGamesNewsletterAlert = ThanksRecorder<()>()
  private let showGamesNewsletterOptInAlert = ThanksRecorder<String>()
  private let showRecommendationsProjects = ThanksRecorder<[Project]>()
  private let postContextualNotification = ThanksRecorder<()>()
  private let postUserUpdatedNotification = ThanksRecorder<Notification.Name>()
  private let updateUserInEnvironment = ThanksRecorder<User>()
  private let facebookButtonIsHidden = ThanksRecorder<Bool>()
  private let twitterButtonIsHidden = ThanksRecorder<Bool>()

  override func setUp() async throws {
    try await super.setUp()
    MainActor.assumeIsolated { self.bindOutputs() }
  }

  override func tearDown() async throws {
    self.feature.reset()
    await self.feature.waitForOperations()
      await self.vm.waitForRecommendations()
    await self.settingsFeature.waitForOperations()
    try await super.tearDown()
  }

  private func bindOutputs() {
    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .backedProjectText(text): self.backedProjectText.record(text.string)
      case let .postProjectBackedNotification(notification): self.postBackedNotification.record(notification.name)
      case let .goToDiscovery(params): self.goToDiscovery.record(params.category ?? .filmAndVideo)
      case let .goToProject(project, projects, refTag):
        self.goToProject.record(project); self.goToProjects.record(projects); self.goToRefTag.record(refTag)
      case .postContextualNotification: self.postContextualNotification.record(())
      case let .postUserUpdatedNotification(notification): self.postUserUpdatedNotification.record(notification.name)
      case .showGamesNewsletterAlert: self.showGamesNewsletterAlert.record(())
      case let .showGamesNewsletterOptInAlert(title): self.showGamesNewsletterOptInAlert.record(title)
      case .showRatingAlert: self.showRatingAlert.record(())
      case let .showRecommendations(projects, _): self.showRecommendationsProjects.record(projects)
      case let .updateUserInEnvironment(user): self.updateUserInEnvironment.record(user)
      }
    }
  }

  private func thanksPageData(
    project: Project = Project.template,
    reward: Reward = Reward.template,
    checkoutData: KSRAnalytics.CheckoutPropertiesData? = nil,
    pledgeTotal: Double = 1
  ) -> ThanksPageData {
    return (project, reward, checkoutData, pledgeTotal)
  }

  func testNewsletterFailureDoesNotReportSavedUser() async {
    await withEnvironment(
      apiService: MockService(updateUserSelfError: .couldNotParseJSON), currentUser: .template
    ) {
      let original = AppEnvironment.current.currentUser?.newsletters.games
      self.vm.gamesNewsletterSignupButtonTapped()
      await self.vm.waitForNewsletter()
      await self.settingsFeature.waitForOperations()
      self.updateUserInEnvironment.assertDidNotEmitValue()
      self.postUserUpdatedNotification.assertDidNotEmitValue()
      XCTAssertEqual(AppEnvironment.current.currentUser?.newsletters.games, original)
      XCTAssertNotNil(self.settingsFeature.lastError)
    }
  }

  func testPostBackedNotification() {
    self.vm.configure(with: self.thanksPageData())
    self.vm.viewDidLoad()

    self.postBackedNotification.assertDidNotEmitValue()

    self.vm.closeButtonTapped()

    self.postBackedNotification.assertValue(Notification.Name.ksr_projectBacked)
  }

  // FIXME: MBL-2857
  func testGoToDiscovery() async {
    let projects = [
      .template |> Project.lens.id .~ 1,
      .template |> Project.lens.id .~ 2,
      .template |> Project.lens.id .~ 3
    ]

    let project = Project.template
    let response = .template |> DiscoveryEnvelope.lens.projects .~ projects

    await withEnvironment(apiService: MockService(
      fetchGraphCategoryResult: .success(self.categoryEnvelope),
      fetchDiscoveryResponse: response
    )) {
      self.vm.configure(with: self.thanksPageData(project: project))
      self.vm.viewDidLoad()

      await self.feature.waitForOperations()
      await self.vm.waitForRecommendations()

      self.showRecommendationsProjects.assertValueCount(1)

      self.vm.categoryCellTapped(.illustration)

      self.goToDiscovery.assertValues([.illustration])
      XCTAssertEqual(
        ["Page Viewed"],
        self.segmentTrackingClient.events
      )
      XCTAssertEqual(
        ["new_pledge"],
        self.segmentTrackingClient.properties(forKey: "context_type")
      )
    }
  }

  // FIXME: MBL-2857
  func testDisplayBackedProjectText() {
    let project = Project.template |> \.category .~ .games
    self.vm.configure(with: self.thanksPageData(project: project))
    self.vm.viewDidLoad()

    self.backedProjectText.assertValues(
      [
        "You have successfully backed The Project. " +
          "This project is now one step closer to a reality, thanks to you. Spread the word!"
      ], "Name of project emits"
    )
  }

  // FIXME: MBL-2857
  func testDisplayBackedProjectText_postCampaignBackings() {
    let mockConfigClient = MockRemoteConfigClient()

    var project = Project.template
    project.name = "Test Project"
    project.isInPostCampaignPledgingPhase = true
    project.country = Project.Country.jp
    project.stats.projectCurrency = Project.Country.jp.currencyCode

    withEnvironment(Environment(currentUserEmail: "test@user.com")) {
      self.vm.configure(with: self.thanksPageData(project: project, pledgeTotal: 127))
      self.vm.viewDidLoad()

      self.backedProjectText
        .assertValues(
          ["Your ¥127 pledge will help in bringing this project to life. Check your email for more details."]
        )
    }
  }

  // FIXME: MBL-2857
  func testRatingAlert_Initial() {
    withEnvironment(currentUser: .template) {
      self.showRatingAlert.assertValueCount(0, "Rating Alert does not emit")

      self.vm.configure(with: self.thanksPageData())
      self.vm.viewDidLoad()

      self.showRatingAlert.assertValueCount(1, "Rating Alert emits when view did load")
      self.showGamesNewsletterAlert.assertValueCount(0, "Games alert does not emit")

      XCTAssertEqual(
        ["Page Viewed"],
        self.segmentTrackingClient.events
      )
    }
  }

  // FIXME: MBL-2857
  func testGamesAlert_ShowsOnce() {
    withEnvironment(currentUser: .template) {
      XCTAssertEqual(
        false, AppEnvironment.current.userDefaults.hasSeenGamesNewsletterPrompt,
        "Newsletter pref is not set"
      )

      let project = Project.template |> Project.lens.category .~ .games
      self.vm.configure(with: self.thanksPageData(project: project))
      self.vm.viewDidLoad()

      self.showRatingAlert.assertValueCount(0, "Rating alert does not show on games project")
      self.showGamesNewsletterAlert.assertValueCount(1, "Games alert shows on games project")
      XCTAssertEqual(
        true, AppEnvironment.current.userDefaults.hasSeenGamesNewsletterPrompt,
        "Newsletter pref saved"
      )

      let secondVM = ThanksViewModel(recommendationsFeature: self.feature, sleep: { _ in try Task.checkCancellation() })
      let secondShowRatingAlert = ThanksRecorder<()>()
      let secondShowGamesNewsletterAlert = ThanksRecorder<()>()
      secondVM.onEvent = { event in
        switch event {
        case .showRatingAlert: secondShowRatingAlert.record(())
        case .showGamesNewsletterAlert: secondShowGamesNewsletterAlert.record(())
        default: break
        }
      }

      secondVM.configure(with: self.thanksPageData(project: project))
      secondVM.viewDidLoad()

      secondShowRatingAlert.assertValueCount(1, "Rating alert shows on games project")
      secondShowGamesNewsletterAlert.assertValueCount(0, "Games alert does not show again on games project")
    }
  }

  // FIXME: MBL-2857
  func testGamesNewsletterAlert_ShouldNotShow_WhenUserIsSubscribed() {
    let newsletters = User.NewsletterSubscriptions.template |> User.NewsletterSubscriptions.lens.games .~ true
    let user = User.template |> \.newsletters .~ newsletters
    let project = Project.template |> Project.lens.category .~ .games

    withEnvironment(currentUser: user) {
      self.vm.configure(with: self.thanksPageData(project: project))
      self.vm.viewDidLoad()

      self.showGamesNewsletterAlert.assertValueCount(0, "Games alert does not show on games project")
    }
  }

  // FIXME: MBL-2857
  func testGamesNewsletterSignup() async {
    let project = Project.template |> Project.lens.category .~ .games

    await withEnvironment(currentUser: .template) {
      self.vm.configure(with: self.thanksPageData(project: project))
      self.vm.viewDidLoad()

      self.showGamesNewsletterAlert.assertValueCount(1)

      self.vm.gamesNewsletterSignupButtonTapped()

      await self.vm.waitForNewsletter()
      await self.settingsFeature.waitForOperations()

      self.updateUserInEnvironment.assertValueCount(1)
      self.showGamesNewsletterOptInAlert.assertValueCount(0, "Opt-in alert does not emit")

      XCTAssertEqual(
        ["Page Viewed"],
        self.segmentTrackingClient.events
      )

      self.vm.userUpdated()

      self.postUserUpdatedNotification.assertValues(
        [Notification.Name.ksr_userUpdated],
        "User updated notification emits"
      )
    }
  }

  // FIXME: MBL-2857
  func testContextualNotificationEmitsWhen_userPledgedFirstProject() {
    let user = User.template |> \.stats.backedProjectsCount .~ 0

    withEnvironment(currentUser: user) {
      self.vm.viewDidLoad()
      self.postContextualNotification.assertDidEmitValue()
    }
  }

  // FIXME: MBL-2857
  func testContextualNotificationDoesNotEmitWhen_userPledgedMoreThanOneProject() {
    let user = User.template |> \.stats.backedProjectsCount .~ 2

    withEnvironment(currentUser: user) {
      self.vm.viewDidLoad()
      self.postContextualNotification.assertDidNotEmitValue()
    }
  }

  // FIXME: MBL-2857
  func testGamesNewsletterOptInAlert() async {
    let project = Project.template |> Project.lens.category .~ .games

    await withEnvironment(countryCode: "DE", currentUser: User.template) {
      self.vm.configure(with: self.thanksPageData(project: project))
      self.vm.viewDidLoad()

      self.showGamesNewsletterAlert.assertValueCount(1)

      self.vm.gamesNewsletterSignupButtonTapped()

      self.showGamesNewsletterOptInAlert.assertValues(
        ["Kickstarter Loves Games"],
        "Opt-in alert emits with title"
      )

      await self.vm.waitForNewsletter()
      await self.settingsFeature.waitForOperations()

      XCTAssertEqual(
        ["Page Viewed"],
        self.segmentTrackingClient.events
      )
    }
  }

  // FIXME: MBL-2857
  func testGoToProject() async {
    let projects = [
      .template |> Project.lens.id .~ 1,
      .template |> Project.lens.id .~ 2,
      .template |> Project.lens.id .~ 3
    ]

    let project = Project.template
    let response = .template |> DiscoveryEnvelope.lens.projects .~ projects

    await withEnvironment(
      apiService: MockService(
        fetchGraphCategoryResult: .success(self.categoryEnvelope),
        fetchDiscoveryResponse: response
      )
    ) {
      self.vm.configure(with: self.thanksPageData(project: project))
      self.vm.viewDidLoad()

      await self.feature.waitForOperations()
      await self.vm.waitForRecommendations()

      self.showRecommendationsProjects.assertValueCount(1)

      self.vm.projectTapped(project)

      self.goToProject.assertValues([project])
      self.goToProjects.assertValueCount(1)
      self.goToRefTag.assertValues([.thanks])

      XCTAssertEqual(
        [
          "Page Viewed",
          "CTA Clicked"
        ],
        self.segmentTrackingClient.events
      )
    }
  }

  // FIXME: MBL-2857
  func testRecommendationsWithProjects() async {
    let projects = [
      .template |> Project.lens.id .~ 1,
      .template |> Project.lens.id .~ 2,
      .template |> Project.lens.id .~ 1,
      .template |> Project.lens.id .~ 2,
      .template |> Project.lens.id .~ 5,
      .template |> Project.lens.id .~ 8
    ]

    let response = .template |> DiscoveryEnvelope.lens.projects .~ projects
    let project = Project.template |> Project.lens.id .~ 12

    await withEnvironment(apiService: MockService(
      fetchGraphCategoryResult: .success(self.categoryEnvelope),
      fetchDiscoveryResponse: response
    )) {
      self.vm.configure(with: self.thanksPageData(project: project))
      self.vm.viewDidLoad()

      await self.feature.waitForOperations()
      await self.vm.waitForRecommendations()

      self.showRecommendationsProjects.assertValueCount(1, "Recommended projects emit, shuffled.")
    }
  }

  // FIXME: MBL-2857
  func testRecommendationsWithoutProjects() async {
    let response = .template |> DiscoveryEnvelope.lens.projects .~ []
    let project = Project.template |> Project.lens.category .~ .games

    await withEnvironment(apiService: MockService(fetchDiscoveryResponse: response)) {
      self.vm.configure(with: self.thanksPageData(project: project))
      self.vm.viewDidLoad()

      await self.feature.waitForOperations()
      await self.vm.waitForRecommendations()

      self.showRecommendationsProjects.assertValueCount(0, "Recommended projects did not emit")
    }
  }

  // FIXME: MBL-2857
  func testThanksPageViewed_Properties_AdvertisingConsentNotAllowed_NoEventsTracked() {
    let checkoutData = KSRAnalytics.CheckoutPropertiesData(
      addOnsCountTotal: 2,
      addOnsCountUnique: 1,
      addOnsMinimumUsd: 8.00,
      bonusAmountInUsd: 10.00,
      checkoutId: "1",
      estimatedDelivery: 12_345_678,
      paymentType: "CREDIT_CARD",
      revenueInUsd: 20.00,
      rewardId: "2",
      rewardMinimumUsd: 5.00,
      rewardTitle: "SUPER reward",
      shippingEnabled: true,
      shippingAmountUsd: 10.00,
      userHasStoredApplePayCard: true
    )

    (self.appTrackingTransparency as? MockAppTrackingTransparency)?.shouldRequestAuthStatus = false
    self.vm.configure(with: self.thanksPageData(checkoutData: checkoutData))
    self.vm.viewDidLoad()

    XCTAssertNil(self.segmentTrackingClient.properties.last)
  }

  // FIXME: MBL-2857
  func testThanksPageViewed_Properties_AdvertisingConsentAllowed_EventsTracked() {
    let checkoutData = KSRAnalytics.CheckoutPropertiesData(
      addOnsCountTotal: 2,
      addOnsCountUnique: 1,
      addOnsMinimumUsd: 8.00,
      bonusAmountInUsd: 10.00,
      checkoutId: "1",
      estimatedDelivery: 12_345_678,
      paymentType: "CREDIT_CARD",
      revenueInUsd: 20.00,
      rewardId: "2",
      rewardMinimumUsd: 5.00,
      rewardTitle: "SUPER reward",
      shippingEnabled: true,
      shippingAmountUsd: 10.00,
      userHasStoredApplePayCard: true
    )

    self.vm.configure(with: self.thanksPageData(checkoutData: checkoutData))
    self.vm.viewDidLoad()

    let segmentClientProps = self.segmentTrackingClient.properties.last

    XCTAssertEqual(
      ["Page Viewed"],
      self.segmentTrackingClient.events
    )

    // Checkout properties

    XCTAssertEqual(2, segmentClientProps?["checkout_add_ons_count_total"] as? Int)
    XCTAssertEqual(1, segmentClientProps?["checkout_add_ons_count_unique"] as? Int)
    XCTAssertEqual(8.00, segmentClientProps?["checkout_add_ons_minimum_usd"] as? Decimal)
    XCTAssertEqual(10.00, segmentClientProps?["checkout_bonus_amount_usd"] as? Decimal)
    XCTAssertEqual("CREDIT_CARD", segmentClientProps?["checkout_payment_type"] as? String)
    XCTAssertEqual("SUPER reward", segmentClientProps?["checkout_reward_title"] as? String)
    XCTAssertEqual(5.00, segmentClientProps?["checkout_reward_minimum_usd"] as? Decimal)
    XCTAssertEqual("2", segmentClientProps?["checkout_reward_id"] as? String)
    XCTAssertEqual(20.00, segmentClientProps?["checkout_amount_total_usd"] as? Decimal)
    XCTAssertEqual(true, segmentClientProps?["checkout_reward_is_limited_quantity"] as? Bool)
    XCTAssertEqual(true, segmentClientProps?["checkout_reward_shipping_enabled"] as? Bool)
    XCTAssertEqual(true, segmentClientProps?["checkout_user_has_eligible_stored_apple_pay_card"] as? Bool)
    XCTAssertEqual(10.00, segmentClientProps?["checkout_shipping_amount_usd"] as? Decimal)
    XCTAssertEqual(
      "1970-05-23T21:21:18Z",
      segmentClientProps?["checkout_reward_estimated_delivery_on"] as? String
    )

    // Pledge properties

    XCTAssertEqual(true, segmentClientProps?["pledge_backer_reward_has_items"] as? Bool)
    XCTAssertEqual(1, segmentClientProps?["pledge_backer_reward_id"] as? Int)
    XCTAssertEqual(10.00, segmentClientProps?["pledge_backer_reward_minimum"] as? Double)

    // Project properties

    XCTAssertEqual("1", segmentClientProps?["project_pid"] as? String)
  }
}

private final class ThanksRecorder<Value> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    self.assertValueCount(0, message, file: file, line: line)
  }
  func assertDidEmitValue(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(self.values.isEmpty, file: file, line: line)
  }
}
private extension ThanksRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
  func assertValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    self.assertValues([expected], message, file: file, line: line)
  }
}
