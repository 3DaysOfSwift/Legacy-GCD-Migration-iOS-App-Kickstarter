import GraphAPI
@testable import Kickstarter_Framework
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import UserNotifications
import XCTest

@MainActor
final class AppDelegateViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let settingsFeature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private let messagingFeature = MessagingFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncMessagingProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var lifecycleFeature = AppLifecycleFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    settingsFeature: self.settingsFeature, messagingFeature: self.messagingFeature,
    makeProvider: { AsyncAppLifecycleProvider(service: AppEnvironment.current.apiService) },
    sleep: { _ in try Task.checkCancellation() }
  )
  var vm: AppDelegateViewModelType!

  private let applicationIconBadgeNumber = TestObserver<Int, Never>()
  private let configureFirebase = TestObserver<(), Never>()
  private let configureSegmentWithBraze = TestObserver<String, Never>()
  private let didAcceptReceivingRemoteNotifications = TestObserver<(), Never>()
  private let emailVerificationCompletedMessage = TestObserver<String, Never>()
  private let emailVerificationCompletedSuccess = TestObserver<Bool, Never>()
  private let findRedirectUrl = TestObserver<URL, Never>()
  private let forceLogout = TestObserver<(), Never>()
  private let goToActivity = TestObserver<(), Never>()
  private let goToDiscovery = TestObserver<DiscoveryParams?, Never>()
  private let goToLoginWithIntent = TestObserver<LoginIntent, Never>()
  private let goToProfile = TestObserver<(), Never>()
  private let goToMobileSafari = TestObserver<URL, Never>()
  private let goToSearch = TestObserver<(), Never>()
  private let postNotificationName = TestObserver<Notification.Name, Never>()
  private let presentViewController = TestObserver<Int, Never>()
  private let pushRegistrationStarted = TestObserver<(), Never>()
  private let pushTokenSuccessfullyRegistered = TestObserver<String, Never>()
  private let registerPushTokenInBraze = TestObserver<Data, Never>()
  private let requestATTrackingAuthorizationStatus = TestObserver<Void, Never>()
  private let setApplicationShortcutItems = TestObserver<[ShortcutItem], Never>()
  private let segmentIsEnabled = TestObserver<Bool, Never>()
  private let showAlert = TestObserver<Notification, Never>()
  private let trackingAuthorizationStatus = TestObserver<AppTrackingAuthorization, Never>()
  private let triggerOnboardingFlow = TestObserver<(), Never>()
  private let unregisterForRemoteNotifications = TestObserver<(), Never>()
  private let updateCurrentUserInEnvironment = TestObserver<User, Never>()
  private let notificationSettingsUpdated = TestObserver<Void, Never>()
  private let updateConfigInEnvironment = TestObserver<Config, Never>()
  private var disposables: [any Disposable] = []

  private var defaultRootCategoriesTemplate: RootCategoriesEnvelope {
    RootCategoriesEnvelope.template
      |> RootCategoriesEnvelope.lens.categories .~ [
        .art,
        .filmAndVideo,
        .illustration,
        .documentary
      ]
  }

  override func setUp() {
    super.setUp()
    MainActor.assumeIsolated { self.bindOutputs() }
  }

  override func tearDown() async throws {
    self.lifecycleFeature.reset()
    await self.lifecycleFeature.waitForOperations()
    await self.settingsFeature.waitForOperations()
    self.messagingFeature.reset()
    await self.messagingFeature.waitForOperations()
    try await super.tearDown()
  }

  func testMessageDeepLinkLoadsThroughSharedFeature() async throws {
    var threads: [MessageThread] = []
    let observation = self.vm.outputs.goToMessageThread.observeValues { threads.append($0) }
    defer { observation?.dispose() }
    self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: [:])
    let accepted = self.vm.inputs.applicationOpenUrl(
      application: UIApplication.shared,
      url: try XCTUnwrap(URL(string: "https://www.kickstarter.com/messages/42")), options: [:]
    )
    XCTAssertTrue(accepted)
    await self.scheduler.advance()
    await self.lifecycleFeature.waitForOperations()
    await self.messagingFeature.waitForOperations()
    XCTAssertEqual(threads.count, 1)
    XCTAssertEqual(threads.first?.id, MessageThread.template.id)
    await self.settingsFeature.waitForOperations()
  }

  private func bindOutputs() {
    self.vm = AppDelegateViewModel(lifecycleFeature: self.lifecycleFeature)
    self.vm.outputs.notificationSettingsUpdated.observe(self.notificationSettingsUpdated.observer)

    self.vm.outputs.applicationIconBadgeNumber.observe(self.applicationIconBadgeNumber.observer)
    self.vm.outputs.configureFirebase.observe(self.configureFirebase.observer)
    self.vm.outputs.configureSegmentWithBraze.observe(self.configureSegmentWithBraze.observer)
    self.vm.outputs.emailVerificationCompleted.map(first)
      .observe(self.emailVerificationCompletedMessage.observer)
    self.vm.outputs.emailVerificationCompleted.map(second)
      .observe(self.emailVerificationCompletedSuccess.observer)
    self.vm.outputs.findRedirectUrl.observe(self.findRedirectUrl.observer)
    self.vm.outputs.forceLogout.observe(self.forceLogout.observer)
    self.vm.outputs.goToActivity.observe(self.goToActivity.observer)
    self.vm.outputs.goToDiscovery.observe(self.goToDiscovery.observer)
    self.vm.outputs.goToLoginWithIntent.observe(self.goToLoginWithIntent.observer)
    self.vm.outputs.goToProfile.observe(self.goToProfile.observer)
    self.vm.outputs.goToMobileSafari.observe(self.goToMobileSafari.observer)
    self.vm.outputs.goToSearch.observe(self.goToSearch.observer)
    self.vm.outputs.postNotification.map { $0.name }.observe(self.postNotificationName.observer)
    self.vm.outputs.presentViewController.map { ($0 as! UINavigationController).viewControllers.count }
      .observe(self.presentViewController.observer)
    self.vm.outputs.pushTokenRegistrationStarted.observe(self.pushRegistrationStarted.observer)
    self.vm.outputs.pushTokenSuccessfullyRegistered.observe(self.pushTokenSuccessfullyRegistered.observer)
    self.vm.outputs.registerPushTokenInBraze.observe(self.registerPushTokenInBraze.observer)
    self.vm.outputs.requestATTrackingAuthorizationStatus
      .observe(self.requestATTrackingAuthorizationStatus.observer)
    self.vm.outputs.setApplicationShortcutItems.observe(self.setApplicationShortcutItems.observer)
    self.vm.outputs.showAlert.observe(self.showAlert.observer)
    self.vm.outputs.segmentIsEnabled.observe(self.segmentIsEnabled.observer)
    self.disposables
      .append(self.vm.outputs.trackingAuthorizationStatus.start(self.trackingAuthorizationStatus.observer))
    self.vm.outputs.triggerOnboardingFlow.observe(self.triggerOnboardingFlow.observer)
    self.vm.outputs.unregisterForRemoteNotifications.observe(self.unregisterForRemoteNotifications.observer)
    self.vm.outputs.updateCurrentUserInEnvironment.observe(self.updateCurrentUserInEnvironment.observer)
    self.vm.outputs.updateConfigInEnvironment.observe(self.updateConfigInEnvironment.observer)
  }

  func testResetApplicationIconBadgeNumber_registeredForPushNotifications_WillEnterForeground() async {
    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: true)

    await withEnvironment(pushRegistrationType: MockPushRegistration.self) {
      self.applicationIconBadgeNumber.assertValues([])

      self.vm.inputs.applicationWillEnterForeground()

      self.applicationIconBadgeNumber.assertValues([0])
    }
  }

  func testResetApplicationIconBadgeNumber_notRegisteredForPushNotifications_WillEnterForeground() async {
    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: false)

    await withEnvironment(pushRegistrationType: MockPushRegistration.self) {
      self.applicationIconBadgeNumber.assertValues([])

      self.vm.inputs.applicationWillEnterForeground()

      self.applicationIconBadgeNumber.assertValues([])
    }
  }

  func testResetApplicationIconBadgeNumber_registeredForPushNotifications_AppLaunch() async {
    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: true)

    await withEnvironment(pushRegistrationType: MockPushRegistration.self) {
      self.applicationIconBadgeNumber.assertValues([])

      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)

      self.applicationIconBadgeNumber.assertValues([0])
    }
  }

  func testResetApplicationIconBadgeNumber_notRegisteredForPushNotifications_AppLaunch() async {
    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: false)

    await withEnvironment(pushRegistrationType: MockPushRegistration.self) {
      self.applicationIconBadgeNumber.assertValues([])

      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)

      self.applicationIconBadgeNumber.assertValues([])
    }
  }

  func testConfigureFirebase() async {
    self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)

    self.configureFirebase.assertValueCount(1)
  }

  func testCurrentUserUpdating_NothingHappensWhenLoggedOut() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )
    self.vm.inputs.applicationWillEnterForeground()
    self.vm.inputs.applicationDidEnterBackground()

    self.updateCurrentUserInEnvironment.assertDidNotEmitValue()
  }

  func testCurrentUserUpdating_WhenLoggedIn() async {
    let env = AccessTokenEnvelope(accessToken: "deadbeef", user: User.template)
    AppEnvironment.login(env)

    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    await self.scheduler.advance(by: .seconds(5))
    await self.settingsFeature.waitForOperations()

    self.updateCurrentUserInEnvironment.assertValues([env.user])
    self.postNotificationName.assertDidNotEmitValue()

    self.vm.inputs.currentUserUpdatedInEnvironment()

    self.updateCurrentUserInEnvironment.assertValues([env.user])
    self.postNotificationName.assertValues([.ksr_userUpdated])

    self.vm.inputs.applicationWillEnterForeground()
    await self.scheduler.advance(by: .seconds(5))
    await self.settingsFeature.waitForOperations()

    self.updateCurrentUserInEnvironment.assertValues([env.user, env.user])
    self.postNotificationName.assertValues([.ksr_userUpdated])

    self.vm.inputs.currentUserUpdatedInEnvironment()

    self.updateCurrentUserInEnvironment.assertValues([env.user, env.user])
    self.postNotificationName.assertValues(
      [.ksr_userUpdated, .ksr_userUpdated]
    )
  }

  func testAppStateEnteringBackground_SendNotification_Success() async {
    let env = AccessTokenEnvelope(accessToken: "deadbeef", user: User.template)
    AppEnvironment.login(env)

    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    await self.scheduler.advance(by: .seconds(5))
    await self.settingsFeature.waitForOperations()

    self.postNotificationName.assertDidNotEmitValue()

    self.vm.inputs.applicationDidEnterBackground()
    await self.scheduler.advance(by: .seconds(5))
    await self.settingsFeature.waitForOperations()

    self.postNotificationName.assertValues(
      [.ksr_applicationDidEnterBackground]
    )
  }

  func testCurrentUserUpdating_WithLegacyUserDefaultsUser() async {
    // No current user in the environment, but the api has an oauth token. This can happen when an oauth
    // token is resurrected from the legacy user defaults.
    await withEnvironment(apiService: MockService(oauthToken: OauthToken(token: "deadbeef"))) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      self.updateCurrentUserInEnvironment.assertValues([.template])
      self.postNotificationName.assertDidNotEmitValue()

      self.vm.inputs.currentUserUpdatedInEnvironment()

      self.updateCurrentUserInEnvironment.assertValues([.template])
      self.postNotificationName.assertValues([.ksr_userUpdated])
    }
  }

  func testInvalidAccessToken() async {
    let error = ErrorEnvelope(
      errorMessages: ["invalid deadbeef"],
      ksrCode: .AccessTokenInvalid,
      httpCode: 401,
      exception: nil
    )

    await withEnvironment(apiService: MockService(fetchUserSelfError: error), currentUser: .template) {
      self.forceLogout.assertValueCount(0)

      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )
      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      self.updateCurrentUserInEnvironment.assertDidNotEmitValue()
      self.forceLogout.assertValueCount(1)
    }
  }

  func testConfig() async {
    let config1 = Config.template |> Config.lens.countryCode .~ "US"
    await withEnvironment(apiService: MockService(fetchConfigResponse: config1)) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )
      await self.lifecycleFeature.waitForOperations()
      self.updateConfigInEnvironment.assertValues([config1])

      self.vm.inputs.didUpdateConfig(config1)
      self.postNotificationName.assertValues([.ksr_configUpdated])
    }

    let config2 = Config.template |> Config.lens.countryCode .~ "GB"
    await withEnvironment(apiService: MockService(fetchConfigResponse: config2)) {
      self.vm.inputs.applicationWillEnterForeground()
      await self.lifecycleFeature.waitForOperations()
      self.updateConfigInEnvironment.assertValues([config1, config2])

      self.vm.inputs.didUpdateConfig(config2)
      self.postNotificationName.assertValues([.ksr_configUpdated, .ksr_configUpdated])
    }

    let config3 = Config.template |> Config.lens.countryCode .~ "CZ"
    await withEnvironment(apiService: MockService(fetchConfigResponse: config3)) {
      self.vm.inputs.userSessionEnded()
      await self.lifecycleFeature.waitForOperations()
      self.updateConfigInEnvironment.assertValues([config1, config2, config3])

      self.vm.inputs.didUpdateConfig(config3)
      self.postNotificationName.assertValues([.ksr_configUpdated, .ksr_configUpdated, .ksr_configUpdated])
    }

    let config4 = Config.template |> Config.lens.countryCode .~ "CA"
    await withEnvironment(apiService: MockService(fetchConfigResponse: config4)) {
      self.vm.inputs.userSessionStarted()
      await self.lifecycleFeature.waitForOperations()
      self.updateConfigInEnvironment.assertValues([config1, config2, config3, config4])

      self.vm.inputs.didUpdateConfig(config4)
      self.postNotificationName.assertValues([
        .ksr_configUpdated,
        .ksr_configUpdated,
        .ksr_configUpdated,
        .ksr_configUpdated
      ])
    }
  }

  func testPresentViewController() async {
    let apiService = MockService(
      fetchProjectResult: .success(.template),
      fetchUpdateResponse: .template
    )
    await withEnvironment(apiService: apiService) {
      let rootUrl = "https://www.kickstarter.com/"

      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.presentViewController.assertValues([])

      let projectUrl = rootUrl + "projects/tequila/help-me-transform-this-pile-of-wood"
      var result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: projectUrl)!,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([1])

      let commentsUrl = projectUrl + "/comments"
      result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: commentsUrl)!,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([1, 2])

      let updatesUrl = projectUrl + "/posts"
      result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: updatesUrl)!,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([1, 2, 2])

      let updateUrl = projectUrl + "/posts/1399396"
      result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: updateUrl)!,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([1, 2, 2, 2])

      let updateCommentsUrl = updateUrl + "/comments"
      result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: updateCommentsUrl)!,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([1, 2, 2, 2, 3])

      let faqUrl = projectUrl + "/faqs"
      result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: faqUrl)!,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([1, 2, 2, 2, 3, 1])
    }
  }

  func testPresentViewController_ProjectPreviewLink_DisplayPrelaunch_True() async {
    let project = Project.template
      |> Project.lens.displayPrelaunch .~ true

    let apiService = MockService(fetchProjectResult: .success(project))
    await withEnvironment(apiService: apiService) {
      let rootUrl = "https://www.kickstarter.com/"

      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.presentViewController.assertValues([])

      let projectUrl = rootUrl + "projects/tequila/help-me-transform-this-pile-of-wood"
      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: projectUrl)!,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([1])
      self.goToMobileSafari.assertValues([])
    }
  }

  func testPresentViewController_ProjectPreviewLink_DisplayPrelaunch_False() async {
    let project = Project.template
      |> Project.lens.displayPrelaunch .~ false

    let apiService = MockService(fetchProjectResult: .success(project))
    await withEnvironment(apiService: apiService) {
      let rootUrl = "https://www.kickstarter.com/"

      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.presentViewController.assertValues([])

      let projectUrl = rootUrl + "projects/tequila/help-me-transform-this-pile-of-wood"
      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: projectUrl)!,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([1])
      self.goToMobileSafari.assertValues([])
    }
  }

  func testPresentViewController_ProjectPreviewLink_DisplayPrelaunch_Nil() async {
    let project = Project.template
      |> Project.lens.displayPrelaunch .~ nil

    let apiService = MockService(fetchProjectResult: .success(project))
    await withEnvironment(apiService: apiService) {
      let rootUrl = "https://www.kickstarter.com/"

      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.presentViewController.assertValues([])

      let projectUrl = rootUrl + "projects/tequila/help-me-transform-this-pile-of-wood"
      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: projectUrl)!,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([1])
      self.goToMobileSafari.assertValues([])
    }
  }

  func testPresentViewController_ProjectCommentThread_Success() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    await withEnvironment(apiService: MockService(fetchCommentRepliesEnvelopeResult: .success(
      CommentRepliesEnvelope
        .successfulRepliesTemplate
    ), fetchProjectResult: .success(.template))) {
      let url =
        "https://\(AppEnvironment.current.apiService.serverConfig.webBaseUrl.host ?? "")/projects/fjorden/fjorden-iphone-photography-reinvented/comments?comment=Q29tbWVudC0zMzY0OTg0MQ%3D%3D"

      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: url)!,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([3])
    }
  }

  func testPresentViewController_ProjectCommentThread_Reply_Success() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    await withEnvironment(apiService: MockService(fetchCommentRepliesEnvelopeResult: .success(
      CommentRepliesEnvelope
        .successfulRepliesTemplate
    ), fetchProjectResult: .success(.template))) {
      let url =
        "https://\(AppEnvironment.current.apiService.serverConfig.webBaseUrl.host ?? "")/projects/fjorden/fjorden-iphone-photography-reinvented/comments?comment=Q29tbWVudC0zMzY0OTg0MQ%3D%3D&reply=deadbeef"

      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: url)!,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([3])
    }
  }

  func testPresentViewController_UpdateCommentThread_Success() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    await withEnvironment(apiService: MockService(fetchCommentRepliesEnvelopeResult: .success(
      CommentRepliesEnvelope
        .successfulRepliesTemplate
    ), fetchProjectResult: .success(.template))) {
      let url =
        "https://\(AppEnvironment.current.apiService.serverConfig.webBaseUrl.host ?? "")/projects/fjorden/fjorden-iphone-photography-reinvented/posts/3254626/comments?comment=Q29tbWVudC0zMzY0OTg0MQ%3D%3D"

      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: url)!,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([4])
    }
  }

  func testPresentViewController_UpdateCommentThread_Reply_Success() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    await withEnvironment(apiService: MockService(fetchCommentRepliesEnvelopeResult: .success(
      CommentRepliesEnvelope
        .successfulRepliesTemplate
    ), fetchProjectResult: .success(.template))) {
      let url =
        "https://\(AppEnvironment.current.apiService.serverConfig.webBaseUrl.host ?? "")/projects/fjorden/fjorden-iphone-photography-reinvented/posts/3254626/comments?comment=Q29tbWVudC0zMzY0OTg0MQ%3D%3D&reply=deadbeef"

      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: url)!,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([4])
    }
  }

  func testGoToActivity() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    self.goToActivity.assertValueCount(0)

    let result = self.vm.inputs.applicationOpenUrl(
      application: UIApplication.shared,
      url: URL(string: "https://www.kickstarter.com/activity")!,
      options: [:]
    )
    XCTAssertTrue(result)

    self.goToActivity.assertValueCount(1)
  }

  func testGoToDiscovery() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    self.goToDiscovery.assertValues([])

    let result = self.vm.inputs.applicationOpenUrl(
      application: UIApplication.shared,
      url: URL(string: "https://www.kickstarter.com/discover?sort=newest")!,
      options: [:]
    )
    XCTAssertTrue(result)

    let params = .defaults
      |> DiscoveryParams.lens.sort .~ .newest
    await self.lifecycleFeature.waitForOperations()
    self.goToDiscovery.assertValues([params])
  }

  func testGoToDiscovery_NoParams() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    self.goToDiscovery.assertValues([])

    let result = self.vm.inputs.applicationOpenUrl(
      application: UIApplication.shared,
      url: URL(string: "https://www.kickstarter.com/discover")!,
      options: [:]
    )
    XCTAssertTrue(result)

    await self.lifecycleFeature.waitForOperations()
    self.goToDiscovery.assertValues([nil])
  }

  func testGoToDiscoveryWithCategoryName_ValidCategoryName_RoutesToCategory() async {
    let mockService = MockService(fetchGraphCategoriesResult: .success(defaultRootCategoriesTemplate))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.goToDiscovery.assertValues([])

      let url = URL(string: "https://www.kickstarter.com/discover/categories/art")!
      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: url,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.scheduler.advance()
      await self.settingsFeature.waitForOperations()

      let params = .defaults |> DiscoveryParams.lens.category .~ .art
      await self.lifecycleFeature.waitForOperations()
      self.goToDiscovery.assertValues([params])
    }
  }

  func testGoToDiscoveryWithCategoryName_InvalidCategoryName_DoesNotRouteToAnyCategory() async {
    let mockService = MockService(fetchGraphCategoriesResult: .success(defaultRootCategoriesTemplate))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.goToDiscovery.assertValues([])

      let url = URL(string: "https://www.kickstarter.com/discover/categories/random")!
      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: url,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.scheduler.advance()
      await self.settingsFeature.waitForOperations()

      let params = .defaults |> DiscoveryParams.lens.category .~ .none
      await self.lifecycleFeature.waitForOperations()
      self.goToDiscovery.assertValues([params])
    }
  }

  func testGoToDiscoveryWithSubcategoryName_ValidSubcategoryName_RoutesToSubcategory() async {
    let gamesTemplate = RootCategoriesEnvelope.template
      |> RootCategoriesEnvelope.lens.categories .~ [
        .art,
        .filmAndVideo,
        .illustration,
        .documentary,
        .games
      ]

    let mockService = MockService(fetchGraphCategoriesResult: .success(gamesTemplate))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.goToDiscovery.assertValues([])

      let url = URL(string: "https://www.kickstarter.com/discover/categories/games/tabletop%20games")!
      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: url,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.scheduler.advance()
      await self.settingsFeature.waitForOperations()

      let params = .defaults |> DiscoveryParams.lens.category .~ .tabletopGames
      await self.lifecycleFeature.waitForOperations()
      self.goToDiscovery.assertValues([params])
    }
  }

  func testGoToDiscoveryWithSubcategoryName_InvalidSubcategoryName_RoutesToCategory() async {
    let gamesTemplate = RootCategoriesEnvelope.template
      |> RootCategoriesEnvelope.lens.categories .~ [
        .art,
        .filmAndVideo,
        .illustration,
        .documentary,
        .games
      ]

    let mockService = MockService(fetchGraphCategoriesResult: .success(gamesTemplate))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.goToDiscovery.assertValues([])

      let url = URL(string: "https://www.kickstarter.com/discover/categories/games/tabletopgames")!
      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: url,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.scheduler.advance()
      await self.settingsFeature.waitForOperations()

      let params = .defaults |> DiscoveryParams.lens.category .~ .games
      await self.lifecycleFeature.waitForOperations()
      self.goToDiscovery.assertValues([params])
    }
  }

  func testGoToDiscoveryWithCategoryId_ValidCategoryId_RoutesToCategory() async {
    let mockService = MockService(fetchGraphCategoriesResult: .success(defaultRootCategoriesTemplate))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.goToDiscovery.assertValues([])

      let url =
        URL(
          string: "https://www.kickstarter.com/discover/advanced?category_id=1&sort=magic&seed=2714369&page=1"
        )!
      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: url,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.scheduler.advance()
      await self.settingsFeature.waitForOperations()

      let params = .defaults |> DiscoveryParams.lens.category .~ .art
        |> DiscoveryParams.lens.sort .~ .magic
        |> DiscoveryParams.lens.seed .~ 2_714_369
        |> DiscoveryParams.lens.page .~ 1
      await self.lifecycleFeature.waitForOperations()
      self.goToDiscovery.assertValues([params])
    }
  }

  func testGoToDiscoveryWithCategoryId_InvalidCategoryOrSubcategoryId_DoesNotRouteToAnyCategory() async {
    let mockService = MockService(fetchGraphCategoriesResult: .success(defaultRootCategoriesTemplate))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.goToDiscovery.assertValues([])

      let url =
        URL(
          string: "https://www.kickstarter.com/discover/advanced?category_id=9999&sort=magic&seed=2714369&page=1"
        )!
      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: url,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.scheduler.advance()
      await self.settingsFeature.waitForOperations()

      let params = .defaults |> DiscoveryParams.lens.category .~ .none
        |> DiscoveryParams.lens.sort .~ .magic
        |> DiscoveryParams.lens.seed .~ 2_714_369
        |> DiscoveryParams.lens.page .~ 1
      await self.lifecycleFeature.waitForOperations()
      self.goToDiscovery.assertValues([params])
    }
  }

  func testGoToDiscoveryWithSubcategoryId_ValidSubcategoryId_RoutesToSubcategory() async {
    let gamesTemplate = RootCategoriesEnvelope.template
      |> RootCategoriesEnvelope.lens.categories .~ [
        .art,
        .filmAndVideo,
        .illustration,
        .documentary,
        .games
      ]

    let mockService = MockService(fetchGraphCategoriesResult: .success(gamesTemplate))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.goToDiscovery.assertValues([])

      let url =
        URL(
          string: "https://www.kickstarter.com/discover/advanced?category_id=34&sort=magic&seed=2714369&page=1"
        )!
      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: url,
        options: [:]
      )
      XCTAssertTrue(result)

      await self.scheduler.advance()
      await self.settingsFeature.waitForOperations()

      let params = .defaults |> DiscoveryParams.lens.category .~ .tabletopGames
        |> DiscoveryParams.lens.sort .~ .magic
        |> DiscoveryParams.lens.seed .~ 2_714_369
        |> DiscoveryParams.lens.page .~ 1
      await self.lifecycleFeature.waitForOperations()
      self.goToDiscovery.assertValues([params])
    }
  }

  func testGoToLogin() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    self.goToLoginWithIntent.assertValueCount(0)

    let result = self.vm.inputs.applicationOpenUrl(
      application: UIApplication.shared,
      url: URL(string: "https://www.kickstarter.com/authorize")!,
      options: [:]
    )
    XCTAssertTrue(result)

    self.goToLoginWithIntent.assertValueCount(1)
  }

  func testGoToProfile() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    self.goToProfile.assertValueCount(0)

    let result = self.vm.inputs.applicationOpenUrl(
      application: UIApplication.shared,
      url: URL(string: "https://www.kickstarter.com/profile/me")!,
      options: [:]
    )
    XCTAssertTrue(result)

    self.goToProfile.assertValueCount(1)
  }

  func testGoToSearch() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    self.goToSearch.assertValueCount(0)

    let result = self.vm.inputs.applicationOpenUrl(
      application: UIApplication.shared,
      url: URL(string: "https://www.kickstarter.com/search")!,
      options: [:]
    )
    XCTAssertTrue(result)

    self.goToSearch.assertValueCount(1)
  }

  func testDeeplink_IsActivated_Success() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    await withEnvironment(currentUser: nil) {
      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: "https://www.kickstarter.com/search")!,
        options: [:]
      )

      XCTAssertTrue(result)

      self.goToSearch.assertValueCount(1)
    }
  }

  func testRegisterPushNotifications_Prompted() async {
    let segmentClient = MockTrackingClient()

    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: false)
    MockPushRegistration.registerProducer = .init(value: true)

    await withEnvironment(
      apiService: MockService(),
      currentUser: .template,
      ksrAnalytics: KSRAnalytics(segmentClient: segmentClient),
      pushRegistrationType: MockPushRegistration.self
    ) {
      self.pushRegistrationStarted.assertValueCount(0)
      self.pushTokenSuccessfullyRegistered.assertValueCount(0)

      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: [:])
      self.vm.inputs.userSessionStarted()
      self.vm.inputs.didAcceptReceivingRemoteNotifications()

      self.pushRegistrationStarted.assertValueCount(1)

      self.vm.inputs.didRegisterForRemoteNotifications(withDeviceTokenData: "token".data(using: .utf8)!)

      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      await self.lifecycleFeature.waitForOperations()
      self.pushTokenSuccessfullyRegistered.assertValueCount(1)

      XCTAssertEqual([], segmentClient.events)
    }
  }

  func testRegisterPushNotifications_PreviouslyAccepted() async {
    let segmentClient = MockTrackingClient()

    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: true)
    MockPushRegistration.registerProducer = .init(value: true)

    await withEnvironment(
      apiService: MockService(),
      currentUser: .template,
      ksrAnalytics: KSRAnalytics(segmentClient: segmentClient),
      pushRegistrationType: MockPushRegistration.self
    ) {
      self.pushRegistrationStarted.assertValueCount(0)
      self.pushTokenSuccessfullyRegistered.assertValueCount(0)

      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: [:])
      self.vm.inputs.userSessionStarted()

      self.pushRegistrationStarted.assertValueCount(1)

      self.vm.inputs.didRegisterForRemoteNotifications(withDeviceTokenData: "token".data(using: .utf8)!)

      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      await self.lifecycleFeature.waitForOperations()
      self.pushTokenSuccessfullyRegistered.assertValueCount(1)

      XCTAssertEqual([], segmentClient.events)
    }
  }

  func testRegisterPushNotifications_WhenNotPreviouslyAccepted() async {
    let segmentClient = MockTrackingClient()
    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: true)
    MockPushRegistration.registerProducer = .init(value: true)

    await withEnvironment(
      apiService: MockService(),
      currentUser: .template,
      ksrAnalytics: KSRAnalytics(segmentClient: segmentClient),
      pushRegistrationType: MockPushRegistration.self
    ) {
      self.pushRegistrationStarted.assertValueCount(0)
      self.pushTokenSuccessfullyRegistered.assertValueCount(0)

      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: [:])
      self.vm.inputs.userSessionStarted()

      self.pushRegistrationStarted.assertValueCount(1)

      self.vm.inputs.didRegisterForRemoteNotifications(withDeviceTokenData: "token".data(using: .utf8)!)

      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      await self.lifecycleFeature.waitForOperations()
      self.pushTokenSuccessfullyRegistered.assertValueCount(1)

      XCTAssertEqual([], segmentClient.events)
    }
  }

  func testTrackingPushAuthorizationOptIn() async {
    let segmentClient = MockTrackingClient()

    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: false)
    MockPushRegistration.registerProducer = .init(value: true)

    await withEnvironment(
      currentUser: .template,
      ksrAnalytics: KSRAnalytics(segmentClient: segmentClient),
      pushRegistrationType: MockPushRegistration.self
    ) {
      XCTAssertEqual([], segmentClient.events)

      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: [:])
      self.vm.inputs.userSessionStarted()

      self.vm.inputs.didAcceptReceivingRemoteNotifications()
    }
  }

  func testRegisterDeviceToken() async {
    await withEnvironment(currentUser: .template) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )
      self.vm.inputs.didRegisterForRemoteNotifications(withDeviceTokenData: "deadbeef".data(using: .utf8)!)
      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      await self.lifecycleFeature.waitForOperations()
      self.pushTokenSuccessfullyRegistered.assertValueCount(1)
    }
  }

  func testRegisterPushTokenInBraze() async {
    let data = Data("deadbeef".utf8)

    self.registerPushTokenInBraze.assertDidNotEmitValue()

    await withEnvironment(currentUser: .template) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )
      self.vm.inputs.didRegisterForRemoteNotifications(withDeviceTokenData: data)

      self.registerPushTokenInBraze.assertValueCount(1)
    }
  }

  func testOpenPushNotification_WhileInBackground() async {
    await withEnvironment(apiService: MockService(fetchProjectResult: .success(.template))) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.presentViewController.assertValueCount(0)

      self.vm.inputs.didReceive(remoteNotification: friendBackingPushData)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValueCount(1)
    }
  }

  func testOpenNotification_NewBacking_ForCreator_WithBadData() async {
    var badPushData = backingForCreatorPushData
    var badActivityData = badPushData["activity"] as? [String: AnyObject]
    badActivityData?["project_id"] = nil
    badPushData["activity"] = badActivityData

    self.vm.inputs.didReceive(remoteNotification: badPushData)
  }

  func testOpenNotification_Order() async {
    self.vm.inputs.didReceive(remoteNotification: orderPushData)

    await self.lifecycleFeature.waitForOperations()
    self.presentViewController.assertValueCount(1)
  }

  func testOpenNotification_Order_BadData() async {
    var badPushData = orderPushData
    badPushData["order"]?["id"] = nil

    self.vm.inputs.didReceive(remoteNotification: badPushData)

    self.presentViewController.assertValueCount(0)
  }

  func testOpenNotification_ProjectUpdate() async {
    await withEnvironment(apiService: MockService(fetchProjectResult: .success(.template))) {
      self.vm.inputs.didReceive(remoteNotification: updatePushData)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValueCount(1)
    }
  }

  func testOpenNotification_ProjectUpdate_BadData() async {
    var badPushData = updatePushData
    badPushData["activity"]?["update_id"] = nil

    self.vm.inputs.didReceive(remoteNotification: badPushData)

    self.presentViewController.assertValueCount(0)
  }

  func testOpenNotification_SurveyResponse() async {
    self.vm.inputs.didReceive(remoteNotification: surveyResponsePushData)

    await self.lifecycleFeature.waitForOperations()
    self.presentViewController.assertValueCount(1)
  }

  func testOpenNotification_SurveyResponse_BadData() async {
    var badPushData = surveyResponsePushData
    badPushData["survey"]?["id"] = nil

    self.vm.inputs.didReceive(remoteNotification: badPushData)

    self.presentViewController.assertValueCount(0)
  }

  func testOpenNotification_UpdateComment() async {
    await withEnvironment(apiService: MockService(fetchProjectResult: .success(.template))) {
      self.vm.inputs.didReceive(remoteNotification: updateCommentPushData)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValueCount(1)
    }
  }

  func testOpenNotification_UpdateComment_BadData() async {
    var badPushData = updatePushData
    badPushData["activity"]?["update_id"] = nil

    self.vm.inputs.didReceive(remoteNotification: badPushData)

    self.presentViewController.assertValueCount(0)
  }

  func testOpenNotification_ProjectComment() async {
    await withEnvironment(apiService: MockService(fetchProjectResult: .success(.template))) {
      self.vm.inputs.didReceive(remoteNotification: projectCommentPushData)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValueCount(1)
    }
  }

  func testOpenNotification_ProjectComment_WithBadData() async {
    await withEnvironment(apiService: MockService(fetchProjectResult: .success(.template))) {
      var badPushData = updatePushData
      badPushData["activity"]?["project_id"] = nil

      self.vm.inputs.didReceive(remoteNotification: badPushData)

      self.presentViewController.assertValueCount(0)
    }
  }

  func testOpenNotification_GenericProject() async {
    await withEnvironment(apiService: MockService(fetchProjectResult: .success(.template))) {
      self.vm.inputs.didReceive(remoteNotification: genericProjectPushData)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValueCount(1)
    }
  }

  func testOpenNotification_ProjectStateChanges() async {
    await withEnvironment(apiService: MockService(fetchProjectResult: .success(.template))) {
      let states: [Activity.Category] = [.failure, .launch, .success, .cancellation, .suspension]

      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      for (idx, state) in states.enumerated() {
        var pushData = genericActivityPushData
        pushData["activity"]?["category"] = state.rawValue

        self.vm.inputs.didReceive(remoteNotification: pushData)

        await self.lifecycleFeature.waitForOperations()
        self.presentViewController.assertValueCount(
          idx + 1, "Presents controller for \(state.rawValue) state change."
        )
      }
    }
  }

  func testOpenNotification_PostLike() async {
    await withEnvironment(apiService: MockService(fetchProjectResult: .success(.template))) {
      let pushData: [String: Any] = [
        "aps": [
          "alert": "Blob liked your update: Important message..."
        ],
        "post": [
          "id": 1,
          "project_id": 2
        ]
      ]

      self.vm.inputs.didReceive(remoteNotification: pushData)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([2])
    }
  }

  func testOpenNotification_UnrecognizedActivityType() async {
    let categories: [Activity.Category] = [.follow, .funding, .unknown, .watch]

    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    categories.enumerated().forEach { _, state in
      var pushData = genericActivityPushData
      pushData["activity"]?["category"] = state.rawValue

      self.vm.inputs.didReceive(remoteNotification: pushData)

      self.goToDiscovery.assertValueCount(0)
      self.presentViewController.assertValueCount(0)
    }
  }

  func testContinueUserActivity_ValidActivity() async {
    let userActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
    userActivity.webpageURL = URL(string: "https://www.kickstarter.com/activity")

    self.vm.inputs.applicationDidFinishLaunching(application: .shared, launchOptions: [:])

    self.goToActivity.assertValueCount(0)
    XCTAssertFalse(self.vm.outputs.continueUserActivityReturnValue.value)

    let result = self.vm.inputs.applicationContinueUserActivity(userActivity)
    XCTAssertTrue(result)

    self.goToActivity.assertValueCount(1)
    XCTAssertTrue(self.vm.outputs.continueUserActivityReturnValue.value)
  }

  func testContinueUserActivity_InvalidActivity() async {
    let userActivity = NSUserActivity(activityType: "Other")

    self.vm.inputs.applicationDidFinishLaunching(application: .shared, launchOptions: [:])
    let result = self.vm.inputs.applicationContinueUserActivity(userActivity)
    XCTAssertFalse(result)

    XCTAssertFalse(self.vm.outputs.continueUserActivityReturnValue.value)
  }

  func testContinueUserActivity_Success() async {
    let userActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
    userActivity.webpageURL = URL(string: "https://www.kickstarter.com/activity")

    await withEnvironment(currentUser: nil) {
      self.vm.inputs.applicationDidFinishLaunching(application: .shared, launchOptions: [:])

      self.goToActivity.assertValueCount(0)
      XCTAssertFalse(self.vm.outputs.continueUserActivityReturnValue.value)

      let result = self.vm.inputs.applicationContinueUserActivity(userActivity)
      XCTAssertTrue(result)

      XCTAssertTrue(self.vm.outputs.continueUserActivityReturnValue.value)
      self.goToActivity.assertValueCount(1)
    }
  }

  func testSetApplicationShortcutItems() async {
    self.setApplicationShortcutItems.assertValues([])

    self.vm.inputs.applicationDidFinishLaunching(application: .shared, launchOptions: [:])

    self.setApplicationShortcutItems.assertValues([])

    await self.scheduler.advance(by: .seconds(5))
    await self.settingsFeature.waitForOperations()

    await self.lifecycleFeature.waitForOperations()
    self.setApplicationShortcutItems.assertValues([[.projectsWeLove, .search]])

    self.vm.inputs.applicationDidEnterBackground()
    self.vm.inputs.applicationWillEnterForeground()
    await self.scheduler.advance(by: .seconds(5))
    await self.settingsFeature.waitForOperations()

    await self.lifecycleFeature.waitForOperations()
    self.setApplicationShortcutItems.assertValues(
      [
        [.projectsWeLove, .search],
        [.projectsWeLove, .search]
      ]
    )
  }

  func testSetApplicationShortcutItems_LoggedInUser_NonMember() async {
    let currentUser = User.template
      |> \.stats.memberProjectsCount .~ 0

    await withEnvironment(
      apiService: MockService(fetchUserSelfResponse: currentUser),
      currentUser: currentUser
    ) {
      self.setApplicationShortcutItems.assertValues([])

      self.vm.inputs.applicationDidFinishLaunching(application: .shared, launchOptions: [:])

      self.setApplicationShortcutItems.assertValues([])

      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      await self.lifecycleFeature.waitForOperations()
      self.setApplicationShortcutItems.assertValues([
        [.recommendedForYou, .projectsWeLove, .search]
      ])
    }
  }

  func testSetApplicationShortcutItems_LoggedInUser_Member() async {
    let currentUser = User.template
      |> \.stats.memberProjectsCount .~ 2

    await withEnvironment(
      apiService: MockService(fetchUserSelfResponse: currentUser),
      currentUser: currentUser
    ) {
      self.setApplicationShortcutItems.assertValues([])

      self.vm.inputs.applicationDidFinishLaunching(application: .shared, launchOptions: [:])

      self.setApplicationShortcutItems.assertValues([])

      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      await self.lifecycleFeature.waitForOperations()
      self.setApplicationShortcutItems.assertValues([
        [.recommendedForYou, .projectsWeLove, .search]
      ])
    }
  }

  func testPerformShortcutItem_ProjectsWeLove() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    self.goToDiscovery.assertValueCount(0)

    self.vm.inputs.applicationPerformActionForShortcutItem(
      ShortcutItem.projectsWeLove.applicationShortcutItem
    )

    let params = .defaults
      |> DiscoveryParams.lens.staffPicks .~ true
      |> DiscoveryParams.lens.sort .~ .magic
    await self.lifecycleFeature.waitForOperations()
    self.goToDiscovery.assertValues([params])
  }

  func testLaunchShortcutItem_ProjectsWeLove() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [
        UIApplication.LaunchOptionsKey.shortcutItem: ShortcutItem.projectsWeLove.applicationShortcutItem
      ]
    )

    let params = .defaults
      |> DiscoveryParams.lens.staffPicks .~ true
      |> DiscoveryParams.lens.sort .~ .magic
    await self.lifecycleFeature.waitForOperations()
    self.goToDiscovery.assertValues([params])
    XCTAssertFalse(self.vm.outputs.applicationDidFinishLaunchingReturnValue)
  }

  func testPerformShortcutItem_RecommendedForYou() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    self.goToDiscovery.assertValueCount(0)

    self.vm.inputs.applicationPerformActionForShortcutItem(
      ShortcutItem.recommendedForYou.applicationShortcutItem
    )

    let params = .defaults
      |> DiscoveryParams.lens.recommended .~ true
      |> DiscoveryParams.lens.sort .~ .magic
    await self.lifecycleFeature.waitForOperations()
    self.goToDiscovery.assertValues([params])
  }

  func testLaunchShortcutItem_RecommendedForYou() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [
        UIApplication.LaunchOptionsKey.shortcutItem: ShortcutItem.recommendedForYou.applicationShortcutItem
      ]
    )

    let params = .defaults
      |> DiscoveryParams.lens.recommended .~ true
      |> DiscoveryParams.lens.sort .~ .magic
    await self.lifecycleFeature.waitForOperations()
    self.goToDiscovery.assertValues([params])
    XCTAssertFalse(self.vm.outputs.applicationDidFinishLaunchingReturnValue)
  }

  func testPerformShortcutItem_Search() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    self.goToSearch.assertValueCount(0)

    self.vm.inputs.applicationPerformActionForShortcutItem(ShortcutItem.search.applicationShortcutItem)

    self.goToSearch.assertValueCount(1)
  }

  func testPerformShortcutItem_Success() async {
    await withEnvironment(currentUser: nil) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )
      self.vm.inputs.applicationPerformActionForShortcutItem(ShortcutItem.search.applicationShortcutItem)

      self.goToSearch.assertValueCount(1)
    }
  }

  func testLaunchShortcutItem_Search() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [
        UIApplication.LaunchOptionsKey.shortcutItem: ShortcutItem.search.applicationShortcutItem
      ]
    )

    self.goToSearch.assertValueCount(1)
    XCTAssertFalse(self.vm.outputs.applicationDidFinishLaunchingReturnValue)
  }

  func testLaunchShortcutItem_Failure() async {
    await withEnvironment(currentUser: nil) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [
          UIApplication.LaunchOptionsKey.shortcutItem: ShortcutItem.search.applicationShortcutItem
        ]
      )

      self.goToSearch.assertValueCount(1)
      XCTAssertFalse(self.vm.outputs.applicationDidFinishLaunchingReturnValue)
    }
  }

  func testVisitorCookies_ApplicationDidFinishLaunching() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    XCTAssertEqual(["vis", "vis"], AppEnvironment.current.cookieStorage.cookies!.map { $0.name })
    XCTAssertEqual(
      ["DEADBEEF-DEAD-BEEF-DEAD-DEADBEEFBEEF", "DEADBEEF-DEAD-BEEF-DEAD-DEADBEEFBEEF"],
      AppEnvironment.current.cookieStorage.cookies!.map { $0.value }
    )
    XCTAssertEqual(
      [
        AppEnvironment.current.apiService.serverConfig.apiBaseUrl.host,
        AppEnvironment.current.apiService.serverConfig.webBaseUrl.host
      ]
      .compact(),
      AppEnvironment.current.cookieStorage.cookies!.map { $0.domain }.sorted()
    )
  }

  func testVisitorCookies_ApplicationWillEnterForeground() async {
    let existingCookie = HTTPCookie(
      properties: [
        .name: "existing-cookie",
        .value: "existing-cookie-value",
        .domain: AppEnvironment.current.apiService.serverConfig.apiBaseUrl.host as Any,
        .path: "/",
        .version: 0,
        .expires: Date.distantFuture,
        .secure: true
      ]
    )

    AppEnvironment.current.cookieStorage.setCookie(existingCookie!)

    self.vm.inputs.applicationWillEnterForeground()

    XCTAssertEqual(
      ["existing-cookie", "vis", "vis"],
      AppEnvironment.current.cookieStorage.cookies!.map { $0.name }.sorted()
    )
    XCTAssertEqual(
      [
        "DEADBEEF-DEAD-BEEF-DEAD-DEADBEEFBEEF",
        "DEADBEEF-DEAD-BEEF-DEAD-DEADBEEFBEEF",
        "existing-cookie-value"
      ],
      AppEnvironment.current.cookieStorage.cookies!.map { $0.value }.sorted()
    )
    XCTAssertEqual(
      [
        AppEnvironment.current.apiService.serverConfig.apiBaseUrl.host,
        AppEnvironment.current.apiService.serverConfig.apiBaseUrl.host,
        AppEnvironment.current.apiService.serverConfig.webBaseUrl.host
      ]
      .compact(),
      AppEnvironment.current.cookieStorage.cookies!.map { $0.domain }.sorted()
    )
  }

  func testVisitorCookies_UserSessionStarted() async {
    let existingCookie = HTTPCookie(
      properties: [
        .name: "existing-cookie",
        .value: "existing-cookie-value",
        .domain: AppEnvironment.current.apiService.serverConfig.apiBaseUrl.host as Any,
        .path: "/",
        .version: 0,
        .expires: Date.distantFuture,
        .secure: true
      ]
    )

    AppEnvironment.current.cookieStorage.setCookie(existingCookie!)

    self.vm.inputs.userSessionStarted()

    XCTAssertEqual(
      ["existing-cookie", "vis", "vis"],
      AppEnvironment.current.cookieStorage.cookies!.map { $0.name }.sorted()
    )
    XCTAssertEqual(
      [
        "DEADBEEF-DEAD-BEEF-DEAD-DEADBEEFBEEF",
        "DEADBEEF-DEAD-BEEF-DEAD-DEADBEEFBEEF",
        "existing-cookie-value"
      ],
      AppEnvironment.current.cookieStorage.cookies!.map { $0.value }.sorted()
    )
    XCTAssertEqual(
      [
        AppEnvironment.current.apiService.serverConfig.apiBaseUrl.host,
        AppEnvironment.current.apiService.serverConfig.apiBaseUrl.host,
        AppEnvironment.current.apiService.serverConfig.webBaseUrl.host
      ]
      .compact(),
      AppEnvironment.current.cookieStorage.cookies!.map { $0.domain }.sorted()
    )
  }

  func testVisitorCookies_UserSessionEnded() async {
    let existingCookie = HTTPCookie(
      properties: [
        .name: "existing-cookie",
        .value: "existing-cookie-value",
        .domain: AppEnvironment.current.apiService.serverConfig.apiBaseUrl.host as Any,
        .path: "/",
        .version: 0,
        .expires: Date.distantFuture,
        .secure: true
      ]
    )

    AppEnvironment.current.cookieStorage.setCookie(existingCookie!)

    self.vm.inputs.userSessionEnded()

    XCTAssertEqual(
      ["existing-cookie", "vis", "vis"],
      AppEnvironment.current.cookieStorage.cookies!.map { $0.name }.sorted()
    )
    XCTAssertEqual(
      [
        "DEADBEEF-DEAD-BEEF-DEAD-DEADBEEFBEEF",
        "DEADBEEF-DEAD-BEEF-DEAD-DEADBEEFBEEF",
        "existing-cookie-value"
      ],
      AppEnvironment.current.cookieStorage.cookies!.map { $0.value }.sorted()
    )
    XCTAssertEqual(
      [
        AppEnvironment.current.apiService.serverConfig.apiBaseUrl.host,
        AppEnvironment.current.apiService.serverConfig.apiBaseUrl.host,
        AppEnvironment.current.apiService.serverConfig.webBaseUrl.host
      ]
      .compact(),
      AppEnvironment.current.cookieStorage.cookies!.map { $0.domain }.sorted()
    )
  }

  func testEmailDeepLinking() async {
    await withEnvironment(apiService: MockService(fetchProjectResult: .success(.template))) {
      let emailUrl = URL(string: "https://clicks.kickstarter.com/?qs=deadbeef")!

      // The application launches.
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.findRedirectUrl.assertValues([])
      self.presentViewController.assertValues([])
      self.goToMobileSafari.assertValues([])

      // We deep-link to an email url.
      self.vm.inputs.applicationDidEnterBackground()
      self.vm.inputs.applicationWillEnterForeground()
      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: emailUrl,
        options: [:]
      )
      XCTAssertTrue(result)

      self.findRedirectUrl.assertValues([emailUrl], "Ask to find the redirect after open the email url.")
      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([], "No view controller is presented yet.")
      self.goToMobileSafari.assertValues([])

      // We find the redirect to be a project url.
      self.vm.inputs.foundRedirectUrl(URL(string: "https://www.kickstarter.com/projects/creator/project")!)

      self.findRedirectUrl.assertValues([emailUrl], "Nothing new is emitted.")
      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValueCount(1, "Present the project view controller.")
      self.goToMobileSafari.assertValues([])
    }
  }

  func testEmailDeepLinking_ContinuedUserActivity() async {
    await withEnvironment(apiService: MockService(fetchProjectResult: .success(.template))) {
      let emailUrl = URL(string: "https://emails.kickstarter.com/?qs=deadbeef")!
      let userActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
      userActivity.webpageURL = emailUrl

      // The application launches.
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.findRedirectUrl.assertValues([])
      self.presentViewController.assertValues([])
      self.goToMobileSafari.assertValues([])

      // We deep-link to an email url.
      self.vm.inputs.applicationDidEnterBackground()
      self.vm.inputs.applicationWillEnterForeground()
      let result = self.vm.inputs.applicationContinueUserActivity(userActivity)
      XCTAssertTrue(result)

      self.findRedirectUrl.assertValues([emailUrl], "Ask to find the redirect after open the email url.")
      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([], "No view controller is presented yet.")
      self.goToMobileSafari.assertValues([])

      // We find the redirect to be a project url.
      self.vm.inputs.foundRedirectUrl(URL(string: "https://www.kickstarter.com/projects/creator/project")!)

      self.findRedirectUrl.assertValues([emailUrl], "Nothing new is emitted.")
      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValueCount(1, "Present the project view controller.")
      self.goToMobileSafari.assertValues([])
    }
  }

  func testEmailDeepLinking_UnrecognizedUrl() async {
    let emailUrl = URL(string: "https://clicks.kickstarter.com/?qs=deadbeef")!

    // The application launches.
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    self.findRedirectUrl.assertValues([])
    self.presentViewController.assertValueCount(0)
    self.goToMobileSafari.assertValues([])

    // We deep-link to an email url.
    self.vm.inputs.applicationDidEnterBackground()
    self.vm.inputs.applicationWillEnterForeground()
    let result = self.vm.inputs.applicationOpenUrl(
      application: UIApplication.shared,
      url: emailUrl,
      options: [:]
    )
    XCTAssertTrue(result)

    self.findRedirectUrl.assertValues([emailUrl], "Ask to find the redirect after open the email url.")
    await self.lifecycleFeature.waitForOperations()
    self.presentViewController.assertValues([], "No view controller is presented.")
    self.goToMobileSafari.assertValues([], "Do not go to mobile safari")

    // We find the redirect to be an unrecognized url.
    let unrecognizedUrl = URL(string: "https://www.kickstarter.com/unreconizable")!
    self.vm.inputs.foundRedirectUrl(unrecognizedUrl)

    self.findRedirectUrl.assertValues([emailUrl], "Nothing new is emitted.")
    await self.lifecycleFeature.waitForOperations()
    self.presentViewController.assertValues([], "Do not present controller since the url was unrecognizable.")
    self.goToMobileSafari.assertValues([unrecognizedUrl], "Go to mobile safari for the unrecognized url.")
  }

  func testEmailDeepLinking_UnrecognizedUrl_ProjectPreview() async {
    let emailUrl = URL(string: "https://emails.kickstarter.com/?qs=deadbeef")!

    // The application launches.
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    self.findRedirectUrl.assertValues([])
    self.presentViewController.assertValueCount(0)
    self.goToMobileSafari.assertValues([])

    // We deep-link to an email url.
    self.vm.inputs.applicationDidEnterBackground()
    self.vm.inputs.applicationWillEnterForeground()
    let result = self.vm.inputs.applicationOpenUrl(
      application: UIApplication.shared,
      url: emailUrl,
      options: [:]
    )
    XCTAssertTrue(result)

    self.findRedirectUrl.assertValues([emailUrl], "Ask to find the redirect after open the email url.")
    await self.lifecycleFeature.waitForOperations()
    self.presentViewController.assertValues([], "No view controller is presented.")
    self.goToMobileSafari.assertValues([], "Do not go to mobile safari")

    // We find the redirect to be an unrecognized url (project preview).
    let unrecognizedUrl = URL(string: "https://www.kickstarter.com/projects/creator/project?token=4")!
    self.vm.inputs.foundRedirectUrl(unrecognizedUrl)

    self.findRedirectUrl.assertValues([emailUrl], "Nothing new is emitted.")
    await self.lifecycleFeature.waitForOperations()
    self.presentViewController.assertValues([], "Do not present controller since the url was unrecognizable.")
    self.goToMobileSafari.assertValues([unrecognizedUrl], "Go to mobile safari for the unrecognized url.")
  }

  func testProjectSurveyDeepLink() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    self.presentViewController.assertValues([])

    let projectUrl = "https://www.kickstarter.com"
      + "/projects/tequila/help-me-transform-this-pile-of-wood/surveys/123"
    let result = self.vm.inputs.applicationOpenUrl(
      application: UIApplication.shared,
      url: URL(string: projectUrl)!,
      options: [:]
    )
    XCTAssertTrue(result)

    await self.lifecycleFeature.waitForOperations()
    self.presentViewController.assertValues([1])
  }

  func testErroredPledgeDeepLink_LoggedIn() async {
    let project = Project.template
      |> \.personalization.backing .~ .template
    let service = MockService(fetchProjectResult: .success(project))

    await withEnvironment(apiService: service, currentUser: .template) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.goToLoginWithIntent.assertDidNotEmitValue()
      self.presentViewController.assertValues([])

      let projectUrl = "https://www.kickstarter.com"
        + "/projects/sshults/greensens-the-easy-way-to-take-care-of-your-houseplants-0"
        + "/pledge?at=4f7d35e7c9d2bb57&ref=ksr_email_backer_failed_transaction"

      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: projectUrl)!,
        options: [:]
      )
      XCTAssertTrue(result)

      self.goToLoginWithIntent.assertDidNotEmitValue()
      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([2])
    }
  }

  func testErroredPledgeDeepLink_LoggedOut() async {
    await withEnvironment(
      apiService: MockService(fetchProjectResult: .success(.template)),
      currentUser: nil
    ) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      self.goToLoginWithIntent.assertDidNotEmitValue()
      self.presentViewController.assertValues([])

      let projectUrl = "https://www.kickstarter.com"
        + "/projects/sshults/greensens-the-easy-way-to-take-care-of-your-houseplants-0"
        + "/pledge?at=4f7d35e7c9d2bb57&ref=ksr_email_backer_failed_transaction"

      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: projectUrl)!,
        options: [:]
      )
      XCTAssertTrue(result)

      self.goToLoginWithIntent.assertValues([.erroredPledge])
      self.presentViewController.assertDidNotEmitValue()
    }
  }

  func testErroredPledgePushDeepLink_LoggedIn() async {
    let project = Project.template
      |> \.personalization.backing .~ .template
    let service = MockService(fetchProjectResult: .success(project))

    await withEnvironment(apiService: service, currentUser: .template) {
      self.goToLoginWithIntent.assertDidNotEmitValue()
      self.presentViewController.assertDidNotEmitValue()

      let pushData: [String: Any] = [
        "aps": [
          "alert": "You have an errored pledge."
        ],
        "errored_pledge": [
          "project_id": 2
        ]
      ]

      self.vm.inputs.didReceive(remoteNotification: pushData)

      self.goToLoginWithIntent.assertDidNotEmitValue()
      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([2])
    }
  }

  func testErroredPledgePushDeepLink_LoggedOut() async {
    await withEnvironment(
      apiService: MockService(fetchProjectResult: .success(.template)),
      currentUser: nil
    ) {
      self.goToLoginWithIntent.assertDidNotEmitValue()
      self.presentViewController.assertDidNotEmitValue()

      let pushData: [String: Any] = [
        "aps": [
          "alert": "You have an errored pledge."
        ],
        "errored_pledge": [
          "project_id": 2
        ]
      ]

      self.vm.inputs.didReceive(remoteNotification: pushData)

      self.goToLoginWithIntent.assertValues([.erroredPledge])
      self.presentViewController.assertDidNotEmitValue()
    }
  }

  func testGoToLoginWithIntent_EmitsCorrectIntents() async {
    self.goToLoginWithIntent.assertDidNotEmitValue()

    self.vm.inputs.goToLoginSignup(from: .generic)
    self.vm.inputs.goToLoginSignup(from: .onboarding)

    XCTAssertEqual(self.goToLoginWithIntent.values, [.generic, .onboarding])
  }

  func testUserSurveyDeepLink() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    self.presentViewController.assertValues([])

    let projectUrl = "https://www.kickstarter.com/users/tequila/surveys/123"
    let result = self.vm.inputs.applicationOpenUrl(
      application: UIApplication.shared,
      url: URL(string: projectUrl)!,
      options: [:]
    )
    XCTAssertTrue(result)

    await self.lifecycleFeature.waitForOperations()
    self.presentViewController.assertValues([1])
  }

  func testShowAlertEmitsIf_CanShowDialog() async {
    let notification = Notification(
      name: Notification.Name(rawValue: "deadbeef"),
      userInfo: ["context": PushNotificationDialog.Context.login]
    )

    userDefaults.set(["message"], forKey: "com.kickstarter.KeyValueStoreType.deniedNotificationContexts")
    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: false)

    await withEnvironment(
      currentUser: .template,
      pushRegistrationType: MockPushRegistration.self,
      userDefaults: userDefaults
    ) {
      self.vm.inputs.applicationWillEnterForeground()
      self.vm.inputs.didReceive(remoteNotification: updatePushData)
      self.vm.inputs.showNotificationDialog(notification: notification)

      self.showAlert.assertValue(notification)
    }
  }

  func testShowAlertDoesNotEmitIf_CanNotShowDialog() async {
    let notification = Notification(
      name: Notification.Name(rawValue: "deadbeef"),
      userInfo: ["context": PushNotificationDialog.Context.login]
    )

    userDefaults.set(["login"], forKey: "com.kickstarter.KeyValueStoreType.deniedNotificationContexts")

    await withEnvironment(currentUser: .template, userDefaults: userDefaults) {
      self.vm.inputs.applicationWillEnterForeground()
      self.vm.inputs.didReceive(remoteNotification: updatePushData)
      self.vm.inputs.showNotificationDialog(notification: notification)

      self.showAlert.assertDidNotEmitValue()
    }
  }

  func testVerifyEmail_Success() async {
    self.emailVerificationCompletedMessage.assertDidNotEmitValue()
    self.emailVerificationCompletedSuccess.assertDidNotEmitValue()

    guard let url = URL(string: "https://www.kickstarter.com/profile/verify_email?at=12345") else {
      XCTFail("Should have a url")
      return
    }

    let env = EmailVerificationResponseEnvelope(
      message: "Thanks—you’ve successfully verified your email address."
    )

    let mockService = MockService(verifyEmailResult: .success(env))

    await withEnvironment(apiService: mockService) {
      _ = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: url,
        options: [:]
      )

      await self.scheduler.advance()
      await self.settingsFeature.waitForOperations()
      await self.scheduler.advance()

      self.emailVerificationCompletedSuccess.assertValues([true])
      self.emailVerificationCompletedMessage.assertValues(
        ["Thanks—you’ve successfully verified your email address."]
      )
    }
  }

  func testVerifyEmail_Failure() async {
    self.emailVerificationCompletedMessage.assertDidNotEmitValue()
    self.emailVerificationCompletedSuccess.assertDidNotEmitValue()

    guard let url = URL(string: "https://www.kickstarter.com/profile/verify_email?at=12345") else {
      XCTFail("Should have a url")
      return
    }

    let errorEnvelope = ErrorEnvelope(
      errorMessages: ["Error Message"],
      ksrCode: .UnknownCode,
      httpCode: 403,
      exception: nil
    )

    let mockService = MockService(verifyEmailResult: .failure(errorEnvelope))

    await withEnvironment(apiService: mockService) {
      _ = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: url,
        options: [:]
      )

      await self.scheduler.advance()
      await self.settingsFeature.waitForOperations()
      await self.scheduler.advance()

      self.emailVerificationCompletedSuccess.assertValues([false])
      self.emailVerificationCompletedMessage.assertValues(
        ["Error Message"]
      )
    }
  }

  func testVerifyEmail_Failure_UnknownError() async {
    self.emailVerificationCompletedMessage.assertDidNotEmitValue()
    self.emailVerificationCompletedSuccess.assertDidNotEmitValue()

    guard let url = URL(string: "https://www.kickstarter.com/profile/verify_email?at=12345") else {
      XCTFail("Should have a url")
      return
    }

    let errorEnvelope = ErrorEnvelope(
      errorMessages: [],
      ksrCode: .UnknownCode,
      httpCode: 500,
      exception: nil
    )

    let mockService = MockService(verifyEmailResult: .failure(errorEnvelope))

    await withEnvironment(apiService: mockService) {
      _ = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: url,
        options: [:]
      )

      await self.scheduler.advance()
      await self.settingsFeature.waitForOperations()
      await self.scheduler.advance()

      self.emailVerificationCompletedSuccess.assertValues([false])
      self.emailVerificationCompletedMessage.assertValues(
        ["Something went wrong, please try again."]
      )
    }
  }

  func testFeatureFlagsRetainedInConfig_NotRelease() async {
    let mockBundle = MockBundle(
      bundleIdentifier: KickstarterBundleIdentifier.beta.rawValue
    )

    let config = Config.template
      |> Config.lens.features .~ [
        "my_enabled_feature": true,
        "my_disabled_feature": false
      ]

    let incomingConfig = Config.template
      |> Config.lens.features .~ [
        "my_enabled_feature": false,
        "my_disabled_feature": true,
        "my_new_feature": true
      ]

    let service = MockService(fetchConfigResponse: incomingConfig)

    self.updateConfigInEnvironment.assertDidNotEmitValue()

    await withEnvironment(apiService: service, config: config, mainBundle: mockBundle) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: .shared,
        launchOptions: [:]
      )

      await self.lifecycleFeature.waitForOperations()
      self.updateConfigInEnvironment.assertValueCount(1)

      let updatedFeatures = self.updateConfigInEnvironment.lastValue?.features

      XCTAssertEqual(updatedFeatures?["my_enabled_feature"], true, "Retains stored value")
      XCTAssertEqual(updatedFeatures?["my_disabled_feature"], false, "Retains stored value")
      XCTAssertEqual(updatedFeatures?["my_new_feature"], true, "Uses incoming value")
    }
  }

  func testFeatureFlagsRetainedInConfig_Release() async {
    let mockBundle = MockBundle(
      bundleIdentifier: KickstarterBundleIdentifier.release.rawValue
    )

    let config = Config.template
      |> Config.lens.features .~ [
        "my_enabled_feature": true,
        "my_disabled_feature": false
      ]

    let incomingConfig = Config.template
      |> Config.lens.features .~ [
        "my_enabled_feature": false,
        "my_disabled_feature": true,
        "my_new_feature": true
      ]

    let service = MockService(fetchConfigResponse: incomingConfig)

    self.updateConfigInEnvironment.assertDidNotEmitValue()

    await withEnvironment(apiService: service, config: config, mainBundle: mockBundle) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: .shared,
        launchOptions: [:]
      )

      await self.lifecycleFeature.waitForOperations()
      self.updateConfigInEnvironment.assertValueCount(1)

      let updatedFeatures = self.updateConfigInEnvironment.lastValue?.features

      XCTAssertEqual(updatedFeatures?["my_enabled_feature"], false, "Uses incoming value")
      XCTAssertEqual(updatedFeatures?["my_disabled_feature"], true, "Uses incoming value")
      XCTAssertEqual(updatedFeatures?["my_new_feature"], true, "Uses incoming value")
    }
  }

  func testConfigureSegment_Release() async {
    let mockBundle = MockBundle(
      bundleIdentifier: KickstarterBundleIdentifier.release.rawValue
    )

    self.configureSegmentWithBraze.assertDidNotEmitValue()

    await withEnvironment(mainBundle: mockBundle) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: .shared,
        launchOptions: [:]
      )

      self.configureSegmentWithBraze.assertValues([Secrets.Segment.production])
    }
  }

  func testConfigureSegment_NotRelease() async {
    let mockBundle = MockBundle(
      bundleIdentifier: KickstarterBundleIdentifier.beta.rawValue
    )

    self.configureSegmentWithBraze.assertDidNotEmitValue()

    await withEnvironment(mainBundle: mockBundle) {
      self.vm.inputs.applicationDidFinishLaunching(
        application: .shared,
        launchOptions: [:]
      )

      self.configureSegmentWithBraze.assertValues([Secrets.Segment.staging])
    }
  }

  func testSegmentIsEnabled_IsEnabled_DidUpdateConfig() async {
    self.segmentIsEnabled.assertDidNotEmitValue()

    let config = Config.template
      |> Config.lens.features .~ [Feature.segment.rawValue: true]

    await withEnvironment(config: config) {
      self.vm.inputs.didUpdateConfig(config)

      self.segmentIsEnabled.assertValues([true])
    }
  }

  func testSegmentIsEnabled_IsDisabled_ConfigUpdatedNotificationObserved() async {
    self.segmentIsEnabled.assertDidNotEmitValue()

    let config = Config.template
      |> Config.lens.features .~ [Feature.segment.rawValue: false]

    await withEnvironment(config: config) {
      self.vm.inputs.configUpdatedNotificationObserved()

      self.segmentIsEnabled.assertValues([false])
    }
  }

  func testDeepLinkNotificationFailureDoesNotReportSuccess() async throws {
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
    let original = AppEnvironment.current.currentUser?.notifications
    let url =
      try XCTUnwrap(URL(string: "https://www.kickstarter.com/settings/notify_mobile_of_messages/true"))
    await withEnvironment(apiService: MockService(updateUserSelfError: .couldNotParseJSON)) {
      XCTAssertTrue(self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared, url: url, options: [:]
      ))
      await self.settingsFeature.waitForOperations()
      await self.scheduler.advance()
      await self.settingsFeature.waitForOperations()
      self.notificationSettingsUpdated.assertDidNotEmitValue()
      self.updateCurrentUserInEnvironment.assertDidNotEmitValue()
      XCTAssertEqual(AppEnvironment.current.currentUser?.notifications, original)
      XCTAssertNotNil(self.settingsFeature.lastError)
    }
  }

  func testDeepLinkCompletionDoesNotReplaySavedUserAfterPresentationDelay() async throws {
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
    let url =
      try XCTUnwrap(URL(string: "https://www.kickstarter.com/settings/notify_mobile_of_messages/true"))
    XCTAssertTrue(self.vm.inputs.applicationOpenUrl(
      application: UIApplication.shared, url: url, options: [:]
    ))
    await self.settingsFeature.waitForOperations()
    XCTAssertEqual(AppEnvironment.current.currentUser?.notifications.mobileMessages, true)
    self.notificationSettingsUpdated.assertDidNotEmitValue()
    var newer = try XCTUnwrap(AppEnvironment.current.currentUser)
    newer.newsletters.games = true
    AppEnvironment.updateCurrentUser(newer)
    await self.scheduler.advance()
    await self.settingsFeature.waitForOperations()
    self.notificationSettingsUpdated.assertValueCount(1)
    self.updateCurrentUserInEnvironment.assertDidNotEmitValue()
    XCTAssertEqual(AppEnvironment.current.currentUser?.newsletters.games, true)
  }

  func testDeepLink_UserDidUpdateNotificationSettings() async {
    self.updateCurrentUserInEnvironment.assertDidNotEmitValue()

    await withEnvironment(apiService: MockService()) {
      let user = User.template
        |> User.lens.notifications.mobileMessages .~ false

      let env = AccessTokenEnvelope(accessToken: "deadbeef", user: user)
      AppEnvironment.login(env)

      self.vm.inputs.applicationDidFinishLaunching(
        application: UIApplication.shared,
        launchOptions: [:]
      )

      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      self.updateCurrentUserInEnvironment.assertValues([user])

      let updatedUser = user
        |> User.lens.notifications.mobileMessages .~ true

      let url =
        "https://\(AppEnvironment.current.apiService.serverConfig.webBaseUrl.host ?? "")/settings/notify_mobile_of_messages/true"

      let result = self.vm.inputs.applicationOpenUrl(
        application: UIApplication.shared,
        url: URL(string: url)!,
        options: [:]
      )
      XCTAssertTrue(result)

      self.updateCurrentUserInEnvironment.assertValues([user])

      await self.settingsFeature.waitForOperations()
      await self.scheduler.advance()
      await self.settingsFeature.waitForOperations()

      self.updateCurrentUserInEnvironment.assertValues([user])
      self.notificationSettingsUpdated.assertValueCount(1)
      XCTAssertEqual(AppEnvironment.current.currentUser?.notifications, updatedUser.notifications)
    }
  }

  func testRequestATTrackingAuthorizationStatus_WhenAppBecomesActive_WhenAdvertisingIdentifierNil_WhenShouldRequestAuthorizationStatusTrue_RequestAllowed_ShowsConsentDialogAndUpdatesAdId_whenHasSeenOnboardingIsTrue(
  ) async {
    let appTrackingTransparency = MockAppTrackingTransparency()
    appTrackingTransparency.requestAndSetAuthorizationStatusFlag = true
    appTrackingTransparency.shouldRequestAuthStatus = true

    userDefaults.set(true, forKey: AppKeys.hasSeenOnboarding.rawValue)

    await withEnvironment(
      appTrackingTransparency: appTrackingTransparency
    ) {
      self.requestATTrackingAuthorizationStatus.assertValueCount(0)

      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)

      self.vm.inputs.applicationActive(state: false)
      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)
      self.vm.inputs.applicationActive(state: true)

      await self.scheduler.advance(by: .seconds(1))
      await self.settingsFeature.waitForOperations()

      XCTAssertEqual(appTrackingTransparency.advertisingIdentifier, "advertisingIdentifier")
      self.requestATTrackingAuthorizationStatus.assertValueCount(1)
    }
  }

  func testRequestATTrackingAuthorizationStatus_WhenAppBecomesActive_WhenAdvertisingIdentifierNil_WhenShouldRequestAuthorizationStatusTrue_RequestAllowed_ShowsConsentDialogAndUpdatesAdId_WhenHasSeenOnboardingIsFalse(
  ) async {
    let appTrackingTransparency = MockAppTrackingTransparency()
    appTrackingTransparency.requestAndSetAuthorizationStatusFlag = true
    appTrackingTransparency.shouldRequestAuthStatus = true

    await withEnvironment(
      appTrackingTransparency: appTrackingTransparency
    ) {
      self.requestATTrackingAuthorizationStatus.assertValueCount(0)

      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)

      self.vm.inputs.applicationActive(state: false)
      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)
      self.vm.inputs.applicationActive(state: true)

      await self.scheduler.advance(by: .seconds(1))
      await self.settingsFeature.waitForOperations()

      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)
      self.requestATTrackingAuthorizationStatus.assertValueCount(0)
    }
  }

  func testRequestATTrackingAuthorizationStatus_WhenAppBecomesActive_WhenAdvertisingIdentifierNil_WhenConsentManagementFeatureFlagOn_WhenShouldRequestAuthorizationStatusTrue_RequestAllowed_DoesNot_ShowConsentDialogAndUpdateAdId(
  ) async {
    let appTrackingTransparency = MockAppTrackingTransparency()
    appTrackingTransparency.requestAndSetAuthorizationStatusFlag = true
    appTrackingTransparency.shouldRequestAuthStatus = true

    await withEnvironment(
      appTrackingTransparency: appTrackingTransparency
    ) {
      self.requestATTrackingAuthorizationStatus.assertValueCount(0)

      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)

      self.vm.inputs.applicationActive(state: false)
      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)
      self.vm.inputs.applicationActive(state: true)

      await self.scheduler.advance(by: .seconds(1))
      await self.settingsFeature.waitForOperations()

      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)
      self.requestATTrackingAuthorizationStatus.assertValueCount(0)
    }
  }

  func testRequestATTrackingAuthorizationStatus_WhenAppBecomesActive_WhenAdvertisingIdentifierNil_WhenConsentManagementFeatureFlagOn_WhenShouldRequestAuthorizationStatusFalse_RequestAllowed_DoesNotShowConsentDialogAndDoesNotUpdateAdId(
  ) async {
    let appTrackingTransparency = MockAppTrackingTransparency()
    appTrackingTransparency.requestAndSetAuthorizationStatusFlag = true
    appTrackingTransparency.shouldRequestAuthStatus = false

    userDefaults.set(true, forKey: AppKeys.hasSeenOnboarding.rawValue)

    await withEnvironment(
      appTrackingTransparency: appTrackingTransparency
    ) {
      self.requestATTrackingAuthorizationStatus.assertValueCount(0)

      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)

      self.vm.inputs.applicationActive(state: false)
      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)
      self.vm.inputs.applicationActive(state: true)

      await self.scheduler.advance(by: .seconds(1))
      await self.settingsFeature.waitForOperations()

      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)
      self.requestATTrackingAuthorizationStatus.assertValueCount(1)
    }
  }

  func testTriggerOnboardingFlow_WhenUserHasNotDeterminedPushNotificationsOrATTPermissions() async {
    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: false)
    MockPushRegistration.registerProducer = .init(value: true)

    let appTrackingTransparency = MockAppTrackingTransparency()
    appTrackingTransparency.requestAndSetAuthorizationStatusFlag = true
    appTrackingTransparency.shouldRequestAuthStatus = true

    await withEnvironment(
      appTrackingTransparency: appTrackingTransparency,
      pushRegistrationType: MockPushRegistration.self
    ) {
      self.triggerOnboardingFlow.assertValueCount(0)

      self.pushRegistrationStarted.assertValueCount(0)
      self.pushTokenSuccessfullyRegistered.assertValueCount(0)

      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)

      self.vm.inputs.applicationActive(state: false)
      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)
      self.vm.inputs.applicationActive(state: true)

      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      self.pushRegistrationStarted.assertValueCount(0)
      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)
      self.requestATTrackingAuthorizationStatus.assertValueCount(0)

      self.triggerOnboardingFlow.assertValueCount(1)
    }
  }

  func testTriggerOnboardingFlow_IsNotCalled_WhenUserHasAuthorizedPushNotifications_ButNotATTPermissions(
  ) async {
    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: true)
    MockPushRegistration.registerProducer = .init(value: true)

    let appTrackingTransparency = MockAppTrackingTransparency()
    appTrackingTransparency.requestAndSetAuthorizationStatusFlag = false
    appTrackingTransparency.shouldRequestAuthStatus = false

    await withEnvironment(
      appTrackingTransparency: appTrackingTransparency,
      pushRegistrationType: MockPushRegistration.self
    ) {
      self.triggerOnboardingFlow.assertValueCount(0)

      self.vm.inputs.applicationActive(state: false)
      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)
      self.vm.inputs.applicationActive(state: true)

      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      self.triggerOnboardingFlow.assertValueCount(0)
    }
  }

  func testTriggerOnboardingFlow_IsNotCalled_WhenUserHasAuthorizedATTPermissions_ButNotPushNotifications(
  ) async {
    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: false)
    MockPushRegistration.registerProducer = .init(value: false)

    let appTrackingTransparency = MockAppTrackingTransparency()
    appTrackingTransparency.requestAndSetAuthorizationStatusFlag = true
    appTrackingTransparency.shouldRequestAuthStatus = false

    await withEnvironment(
      appTrackingTransparency: appTrackingTransparency,
      pushRegistrationType: MockPushRegistration.self
    ) {
      self.triggerOnboardingFlow.assertValueCount(0)

      self.vm.inputs.applicationActive(state: false)
      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)
      self.vm.inputs.applicationActive(state: true)

      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      self.triggerOnboardingFlow.assertValueCount(0)
    }
  }

  func testTriggerOnboardingFlow_IsNotCalled_WhenOnboardingFlowFeatureFlagDisabled() async {
    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: false)
    MockPushRegistration.registerProducer = .init(value: false)

    let appTrackingTransparency = MockAppTrackingTransparency()
    appTrackingTransparency.requestAndSetAuthorizationStatusFlag = false
    appTrackingTransparency.shouldRequestAuthStatus = false

    await withEnvironment(
      appTrackingTransparency: appTrackingTransparency,
      pushRegistrationType: MockPushRegistration.self
    ) {
      self.triggerOnboardingFlow.assertValueCount(0)

      self.vm.inputs.applicationActive(state: false)
      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)
      self.vm.inputs.applicationActive(state: true)

      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      self.triggerOnboardingFlow.assertValueCount(0)
    }
  }

  func testTriggerOnboardingFlow_IsNotCalled_UserDefaultsHasSeenOnboardingIsTrue() async {
    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: false)
    MockPushRegistration.registerProducer = .init(value: true)

    let appTrackingTransparency = MockAppTrackingTransparency()
    appTrackingTransparency.requestAndSetAuthorizationStatusFlag = true
    appTrackingTransparency.shouldRequestAuthStatus = true

    userDefaults.set(true, forKey: AppKeys.hasSeenOnboarding.rawValue)

    await withEnvironment(
      appTrackingTransparency: appTrackingTransparency,
      pushRegistrationType: MockPushRegistration.self
    ) {
      self.triggerOnboardingFlow.assertValueCount(0)

      self.pushRegistrationStarted.assertValueCount(0)
      self.pushTokenSuccessfullyRegistered.assertValueCount(0)

      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)

      self.vm.inputs.applicationActive(state: false)
      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)
      self.vm.inputs.applicationActive(state: true)

      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      self.pushRegistrationStarted.assertValueCount(0)
      XCTAssertEqual(appTrackingTransparency.advertisingIdentifier, "advertisingIdentifier")
      self.requestATTrackingAuthorizationStatus.assertValueCount(1)

      self.triggerOnboardingFlow.assertValueCount(0)
    }
  }

  func testTriggerOnboardingFlow_WhenUserDefaultsHasSeenOnboardingIsFalse() async {
    MockPushRegistration.hasAuthorizedNotificationsProducer = .init(value: false)
    MockPushRegistration.registerProducer = .init(value: true)

    let appTrackingTransparency = MockAppTrackingTransparency()
    appTrackingTransparency.requestAndSetAuthorizationStatusFlag = true
    appTrackingTransparency.shouldRequestAuthStatus = true

    await withEnvironment(
      appTrackingTransparency: appTrackingTransparency,
      pushRegistrationType: MockPushRegistration.self
    ) {
      self.triggerOnboardingFlow.assertValueCount(0)

      self.pushRegistrationStarted.assertValueCount(0)
      self.pushTokenSuccessfullyRegistered.assertValueCount(0)

      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)

      self.vm.inputs.applicationActive(state: false)
      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)
      self.vm.inputs.applicationActive(state: true)

      await self.scheduler.advance(by: .seconds(5))
      await self.settingsFeature.waitForOperations()

      self.pushRegistrationStarted.assertValueCount(0)
      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)
      self.requestATTrackingAuthorizationStatus.assertValueCount(0)

      XCTAssertFalse(userDefaults.bool(forKey: AppKeys.hasSeenOnboarding.rawValue))

      self.triggerOnboardingFlow.assertValueCount(1)
    }
  }

  func testRequestATTrackingAuthorizationStatus_WhenAppBecomesActive_WhenAdvertisingIdentifierNil_WhenShouldRequestAuthorizationStatusTrue_RequestDenied_DoesNotShowConsentDialogAndDoesNotUpdateAdId(
  ) async {
    let appTrackingTransparency = MockAppTrackingTransparency()
    appTrackingTransparency.requestAndSetAuthorizationStatusFlag = false
    appTrackingTransparency.shouldRequestAuthStatus = true

    await withEnvironment(
      appTrackingTransparency: appTrackingTransparency
    ) {
      self.requestATTrackingAuthorizationStatus.assertValueCount(0)

      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)

      self.vm.inputs.applicationActive(state: false)
      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)
      self.vm.inputs.applicationActive(state: true)

      await self.scheduler.advance(by: .seconds(1))
      await self.settingsFeature.waitForOperations()

      XCTAssertNil(appTrackingTransparency.advertisingIdentifier)
      self.requestATTrackingAuthorizationStatus.assertValueCount(0)
    }
  }

  func testRequestAppTrackingSignalAuthorize() async {
    let appTrackingTransparency = MockAppTrackingTransparency()
    await withEnvironment(
      appTrackingTransparency: appTrackingTransparency
    ) {
      self.vm.inputs.applicationActive(state: false)
      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)

      appTrackingTransparency.authorizationStatusValue = .notDetermined
      XCTAssertEqual(self.trackingAuthorizationStatus.values, [.notDetermined])
      XCTAssertTrue(appTrackingTransparency.shouldRequestAuthStatus)

      appTrackingTransparency.requestAndSetAuthorizationStatus()
      XCTAssertEqual(self.trackingAuthorizationStatus.values, [.notDetermined, .authorized])
      XCTAssertFalse(appTrackingTransparency.shouldRequestAuthStatus)
    }
  }

  func testRequestAppTrackingSignalDeny() async {
    let appTrackingTransparency = MockAppTrackingTransparency()
    await withEnvironment(
      appTrackingTransparency: appTrackingTransparency
    ) {
      self.vm.inputs.applicationActive(state: false)
      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)

      appTrackingTransparency.authorizationStatusValue = .notDetermined
      XCTAssertEqual(self.trackingAuthorizationStatus.values, [.notDetermined])
      XCTAssertTrue(appTrackingTransparency.shouldRequestAuthStatus)

      appTrackingTransparency.authorizationStatusValue = .denied
      XCTAssertEqual(self.trackingAuthorizationStatus.values, [.notDetermined, .denied])
      XCTAssertFalse(appTrackingTransparency.shouldRequestAuthStatus)
    }
  }

  func testPresentViewController_BrazeInAppNotificationDeeplink_ProjectCommentThread_Success() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    await withEnvironment(apiService: MockService(fetchCommentRepliesEnvelopeResult: .success(
      CommentRepliesEnvelope
        .successfulRepliesTemplate
    ), fetchProjectResult: .success(.template))) {
      let url =
        "https://\(AppEnvironment.current.apiService.serverConfig.webBaseUrl.host ?? "")/projects/fjorden/fjorden-iphone-photography-reinvented/"

      self.presentViewController.assertValues([])

      self.vm.inputs.urlFromBrazeNotification(URL(string: url)!)

      await self.lifecycleFeature.waitForOperations()
      self.presentViewController.assertValues([1])
    }
  }

  func testGoToMobileSafari_BrazeInAppNotificaton() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    let url = URL(string: "https://fake-url.com")!
    self.vm.inputs.urlFromBrazeNotification(url)

    self.goToMobileSafari.assertValues([url])
    self.presentViewController.assertValues([])
  }

  func testGoToMobileSafari_unrecognizedDeeplink() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    let url = URL(string: "https://fake-url.com")!
    _ = self.vm.inputs.applicationOpenUrl(application: nil, url: url, options: [:])

    self.goToMobileSafari.assertLastValue(url)
  }

  func testGoToMobileSafari_deeplinkFound() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    let url = URL(string: "https://kickstarter.com/activity")!
    _ = self.vm.inputs.applicationOpenUrl(application: nil, url: url, options: [:])

    self.goToMobileSafari.assertDidNotEmitValue()
  }

  func testGoToMobileSafari_ksrUnrecognizedDeeplink() async throws {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    let url = URL(string: "ksr://fake-url.com")!
    _ = self.vm.inputs.applicationOpenUrl(application: nil, url: url, options: [:])

    self.goToMobileSafari.assertDidNotEmitValue()
  }

  func testGoToMobileSafari_ksrDeeplinkFound() async {
    self.vm.inputs.applicationDidFinishLaunching(
      application: UIApplication.shared,
      launchOptions: [:]
    )

    let url = URL(string: "https://kickstarter.com/activity")!
    _ = self.vm.inputs.applicationOpenUrl(application: nil, url: url, options: [:])

    self.goToMobileSafari.assertDidNotEmitValue()
  }

  func testRemoteConfigClientConfiguredNotification_Success() async {
    let mockService = MockService(serverConfig: ServerConfig.staging)

    await withEnvironment(apiService: mockService) {
      self.postNotificationName.assertDidNotEmitValue()

      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)

      self.vm.inputs.didUpdateRemoteConfigClient()

      self.postNotificationName.assertValues([.ksr_remoteConfigClientConfigured])
    }
  }

  func testRemoteConfigClientConfigurationFailedNotification() async {
    let mockService = MockService(serverConfig: ServerConfig.staging)

    await withEnvironment(apiService: mockService) {
      self.postNotificationName.assertDidNotEmitValue()

      self.vm.inputs.applicationDidFinishLaunching(application: UIApplication.shared, launchOptions: nil)

      self.vm.inputs.remoteConfigClientConfigurationFailed()

      self.postNotificationName.assertValues([.ksr_remoteConfigClientConfigurationFailed])
    }
  }

  func testUserSessionStarted_fetchesUserEmail_andClearsOnLogout() async {
    let fetchUserSetupQueryData = GraphAPI.FetchUserSetupQuery.Data(
      me: GraphAPI.FetchUserSetupQuery.Data.Me(
        email: "user@example.com",
        enabledFeatures: []
      )
    )

    guard let envelope = UserEnvelope<GraphUserSetup>.userEnvelope(from: fetchUserSetupQueryData) else {
      XCTFail()
      return
    }

    let mockService = MockService(
      fetchGraphUserSetupResult: .success(envelope)
    )

    await withEnvironment(apiService: mockService) {
      XCTAssertNil(AppEnvironment.current.currentUserEmail)

      self.vm.inputs.userSessionStarted()
      await self.settingsFeature.waitForOperations()

      XCTAssertEqual(AppEnvironment.current.currentUserEmail, "user@example.com")

      AppEnvironment.logout()

      XCTAssertNil(AppEnvironment.current.currentUserEmail)
    }
  }
}

private let backingForCreatorPushData: [String: Any] = [
  "aps": [
    "alert": "HEYYYY"
  ],
  "activity": [
    "category": "backing",
    "id": 1,
    "project_id": 1
  ],
  "for_creator": true
]

private let friendBackingPushData = [
  "aps": [
    "alert": "HEYYYY"
  ],
  "activity": [
    "category": "backing",
    "id": 1,
    "project_id": 1
  ]
]

private let genericActivityPushData = [
  "aps": [
    "alert": "HEYYYY"
  ],
  "activity": [
    "category": "success",
    "id": 1,
    "project_id": 1
  ]
]

private let genericProjectPushData = [
  "aps": [
    "alert": "HEYYYY"
  ],
  "project": [
    "id": 1
  ]
]
private let projectCommentPushData = [
  "aps": [
    "alert": "HEYYYY"
  ],
  "activity": [
    "category": "comment-project",
    "id": 1,
    "project_id": 1
  ]
]

private let orderPushData = [
  "aps": [
    "alert": "Response needed! Get your reward for backing some project."
  ],
  "order": [
    "id": 1,
    "project_id": 1,
    "pledge_manager_path": "/projects/fakeCreatorId/1/backing/redeem"
  ]
]

private let surveyResponsePushData = [
  "aps": [
    "alert": "Response needed! Get your reward for backing some project."
  ],
  "survey": [
    "id": 1,
    "project_id": 1,
    "urls": [
      "web": [
        "survey": "/projects/fakeCreatorId/1/surveys/0"
      ]
    ]
  ]
]

private let updateCommentPushData = [
  "aps": [
    "alert": "HEYYYY"
  ],
  "activity": [
    "category": "comment-post",
    "id": 1,
    "project_id": 1,
    "update_id": 1
  ]
]

private let updatePushData = [
  "aps": [
    "alert": "HEYYYY"
  ],
  "activity": [
    "category": "update",
    "id": 1,
    "project_id": 1,
    "update_id": 1
  ]
]
