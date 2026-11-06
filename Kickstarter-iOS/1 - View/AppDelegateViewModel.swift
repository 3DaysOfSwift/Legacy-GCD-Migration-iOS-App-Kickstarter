import Experimentation
import FirebaseCrashlytics
import KsApi

import Prelude
import ReactiveSwift
import UIKit
import UserNotifications

public enum NotificationAuthorizationStatus {
  case authorized
  case denied
  case notDetermined
  case provisional
}

@MainActor
public protocol AppDelegateViewModelInputs {
  /// Call when the application is handed off to.
  func applicationContinueUserActivity(_ userActivity: NSUserActivity) -> Bool

  /// Call when the application finishes launching.
  func applicationDidFinishLaunching(
    application: UIApplication?, launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  )

  /// Call when the application will enter foreground.
  func applicationWillEnterForeground()

  /// Call when the application enters background.
  func applicationDidEnterBackground()

  /// Call when the application becomes active `UIApplicationStateActive` and `UIApplicationStateInactive`
  func applicationActive(state: Bool)

  /// Call when the aplication receives memory warning from the system.
  func applicationDidReceiveMemoryWarning()

  /// Call to open a url that was sent to the app
  func applicationOpenUrl(
    application: UIApplication?,
    url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any]
  ) -> Bool

  /// Call when the application receives a request to perform a shortcut action.
  func applicationPerformActionForShortcutItem(_ item: UIApplicationShortcutItem)

  /// Call after having invoked AppEnvironment.updateCurrentUser with a fresh user.
  func currentUserUpdatedInEnvironment()

  /// Call when the `ksr_configUpdated` notification is observed (config updated elsewhere, eg. debug tools).
  func configUpdatedNotificationObserved()

  /// Call when the user taps "OK" from the contextual alert.
  func didAcceptReceivingRemoteNotifications()

  /// Call when the app delegate receives a remote notification.
  func didReceive(remoteNotification notification: [AnyHashable: Any])
  func didReceive(pushEnvelope: PushEnvelope)

  /// Call when the app delegate gets notice of a successful notification registration.
  func didRegisterForRemoteNotifications(withDeviceTokenData data: Data)

  /// Call when the config has been updated the AppEnvironment
  func didUpdateConfig(_ config: Config)

  /// Call when the Remote Config client has been updated in the AppEnvironment
  func didUpdateRemoteConfigClient()

  /// Call when the redirect URL has been found, see `findRedirectUrl` for more information.
  func resolveEmailRedirect(_ url: URL)
  func foundRedirectUrl(_ url: URL)

  /// Call when the users taps 'Log in or Sign up' from the onboarding flow (`OnboardingView`).
  func goToLoginSignup(from intent: LoginIntent)

  /// Call when Remote Config configuration has failed
  func remoteConfigClientConfigurationFailed()

  /// Call when the contextual PushNotification dialog should be presented.
  func showNotificationDialog(notification: Notification)

  /// Call when Braze in-app notifications send a valid URL.
  func urlFromBrazeNotification(_ url: URL?)

  /// Call when the controller has received a user session ended notification.
  func userSessionEnded()

  /// Call when the controller has received a user session started notification.
  func userSessionStarted()
}

@MainActor
public protocol AppDelegateViewModelOutputs: AnyObject {
  /// The value to return from the delegate's `application:didFinishLaunchingWithOptions:` method.
  var applicationDidFinishLaunchingReturnValue: Bool { get }

  /// Emits the application icon badge number
  var applicationIconBadgeNumber: Signal<Int, Never> { get }

  /// Emits when the application should configure Firebase
  var onConfigureFirebase: (() -> Void)? { get set }

  /// Emits when the application should configure Segment with an instance of Braze.
  var onConfigureSegmentWithBraze: ((String) -> Void)? { get set }

  /// Emits when the application should configure Statsig
  var onConfigureStatsig: ((StatsigClientSDKKey) -> Void)? { get set }

  /// Return this value in the delegate method.
  var continueUserActivityReturnValue: Bool { get }

  /// Emits the response from email verification with a message and success/failure.
  var emailVerificationCompleted: Signal<(String, Bool), Never> { get }

  /// Emits when the view needs to figure out the redirect URL for the emitted URL.
  /// Required in order to handle email links.
  var findRedirectUrl: Signal<URL, Never> { get }

  /// Emits when opening the app with an invalid access token.
  var forceLogout: Signal<(), Never> { get }

  /// Emits when the root view controller should navigate to activity.
  var goToActivity: Signal<(), Never> { get }

  /// Emits when the root view controller should navigate to the discovery screen.
  var goToDiscovery: Signal<DiscoveryParams?, Never> { get }

  /// Emits when the root view controller should present the login modal.
  var goToLoginWithIntent: Signal<LoginIntent, Never> { get }

  /// Emits a message thread when we should navigate to it.
  var goToMessageThread: Signal<MessageThread, Never> { get }

  /// Emits when the root view controller should navigate to the user's profile.
  var goToProfile: Signal<(), Never> { get }

  /// Emits a URL when we should open it in the safari browser.
  var goToMobileSafari: Signal<URL, Never> { get }

  /// Emits when the root view controller should navigate to search.
  var goToSearch: Signal<(), Never> { get }

  /// Emits an Notification that should be immediately posted.
  var onPostNotification: ((Notification) -> Void)? { get set }

  /// Emits when a view controller should be presented.
  var presentViewController: Signal<UIViewController, Never> { get }

  /// Emits when the push token registration begins.
  var pushTokenRegistrationStarted: Signal<(), Never> { get }

  /// Emits the push token that has been successfully registered on the server.
  var onPushTokenSuccessfullyRegistered: ((String) -> Void)? { get set }

  /// Emits when we should register the device push token in Braze.
  var onRegisterPushTokenInBraze: ((Data) -> Void)? { get set }

  /// Emits when application didFinishLaunchingWithOptions.
  var requestATTrackingAuthorizationStatus: Signal<Void, Never> { get }

  /// Emits when our config updates with the enabled state for Semgent Analytics.
  var onSegmentEnabled: ((Bool) -> Void)? { get set }

  /// Emits an array of short cut items to put into the shared application.
  var setApplicationShortcutItems: Signal<[ShortcutItem], Never> { get }

  /// Emits when an alert should be shown.
  var onShowAlert: ((Notification) -> Void)? { get set }

  /// Emits to synchronize iCloud on app launch.
  var onSynchronizeUbiquitousStore: (() -> Void)? { get set }

  /// Emits immediately and when the user's authorization status changes
  var trackingAuthorizationStatus: SignalProducer<AppTrackingAuthorization, Never> { get }

  /// Emits when application didFinishLaunchingWithOptions and the Onboarding Flow feature flag is enabled.
  var triggerOnboardingFlow: Signal<(), Never> { get }

  /// Emits when we should unregister the user from notifications.
  var onUnregisterForRemoteNotifications: (() -> Void)? { get set }

  /// Emits a fresh user to be updated in the app environment.
  var updateCurrentUserInEnvironment: Signal<User, Never> { get }

  /// A preference command has already persisted; observers must not re-save its snapshot.
  var notificationSettingsUpdated: Signal<Void, Never> { get }

  /// Emits a config value that should be updated in the environment.
  var onUpdateConfig: ((Config) -> Void)? { get set }
}

@MainActor
public protocol AppDelegateViewModelType {
  var inputs: AppDelegateViewModelInputs { get }
  var outputs: AppDelegateViewModelOutputs { get }
}

@MainActor
public final class AppDelegateViewModel: AppDelegateViewModelType, AppDelegateViewModelInputs,
  AppDelegateViewModelOutputs {
  private let lifecycleFeature: AppLifecycleFeature
  private let navigationRoute = UUID()
  @MainActor private final class RedirectObservation {
    var task: Task<Void, Never>?
    var input: URL?
    var id: UUID?
    func cancel() { self.task?.cancel(); self.task = nil; self.input = nil; self.id = nil }
  }
  private let redirectObservation = RedirectObservation()
  private let pushDebounce: @MainActor () async throws -> Void
  private var pushDebounceTask: Task<Void, Never>?
  private var pushPresentationTask: Task<Void, Never>?
  private var configurationTask: Task<Void, Never>?
  private var lastSegmentEnabled: Bool?

  public init(
    lifecycleFeature: AppLifecycleFeature? = nil,
    pushDebounce: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .seconds(5)) }
  ) {
    self.pushDebounce = pushDebounce
    let lifecycleFeature = lifecycleFeature ?? AppModel.shared.appLifecycleFeature
    self.lifecycleFeature = lifecycleFeature
    let route = self.navigationRoute
    let redirectObservation = self.redirectObservation
    let settingsFeature = lifecycleFeature.settingsFeature
    let currentUserEvent = Signal
      .merge(
        self.applicationWillEnterForegroundProperty.signal,
        self.applicationLaunchOptionsProperty.signal.ignoreValues(),
        self.userSessionEndedProperty.signal,
        self.userSessionStartedProperty.signal
      )
      .ksr_debounce(.seconds(5), on: AppEnvironment.current.scheduler)
      .switchMap { _ -> SignalProducer<Signal<User?, ErrorEnvelope>.Event, Never> in
        guard AppEnvironment.current.apiService.isAuthenticated || AppEnvironment.current.currentUser != nil else {
          return SignalProducer(value: .value(nil))
        }
        let request = settingsFeature.requestRefresh(allowSessionRestore: AppEnvironment.current.apiService.isAuthenticated)
        return lifecycleReadResult(request).wrapInOptional().materialize()
      }

    let fetchUserSetupEvent = Signal
      .merge(
        self.applicationWillEnterForegroundProperty.signal,
        self.applicationLaunchOptionsProperty.signal.ignoreValues(),
        self.userSessionStartedProperty.signal
      )
      .switchMap { _ -> SignalProducer<Signal<GraphUserSetup?, ErrorEnvelope>.Event, Never> in
        let request = settingsFeature.requestSetup()
        return lifecycleResult(feature: lifecycleFeature) {
          try await withTaskCancellationHandler { try await request.value } onCancel: { request.cancel() }
        }.wrapInOptional().materialize()
      }

    self.fetchUserEmail = fetchUserSetupEvent.values()
      .map { user in
        // SessionFeature has already stored the guarded setup snapshot.
        guard user?.email != nil else { return }

        NotificationCenter.default.post(.init(name: .ksr_userUpdated))
      }

    self.forceLogout = currentUserEvent
      .errors()
      .filter { $0.ksrCode == .AccessTokenInvalid }
      .ignoreValues()

    let openUrl = self.applicationOpenUrlProperty.signal.skipNil()

    // iCloud


    // Push notifications

    let pushNotificationsPreviouslyAuthorized = self.applicationLaunchOptionsProperty.signal
      .flatMap { _ in pushAuthorizationStatusProducer() }

    let pushTokenRegistrationStartedEvents = Signal.merge(
      self.didAcceptReceivingRemoteNotificationsProperty.signal,
      pushNotificationsPreviouslyAuthorized
        .filter { isPreviouslyAuthorzied in isPreviouslyAuthorzied }
        .ignoreValues()
    )
    .flatMap {
      pushRegistrationProducer()
        .materialize()
    }

    let pushTokenRegistrationStartedValues = pushTokenRegistrationStartedEvents.values()

    self.pushTokenRegistrationStarted = pushTokenRegistrationStartedValues
      .ignoreValues()





    // MARK: - Onboarding Flow

    /// Trigger if the user hasn't authorized or denied Push Notification or AppTrackingTransparency permissions yet and hasn't seen the onboarding flow already..
    self.triggerOnboardingFlow = Signal.combineLatest(
      self.applicationLaunchOptionsProperty.signal.ignoreValues(),
      pushNotificationsPreviouslyAuthorized.filter { isFalse($0) }
    )
    .filter { _ in
      let shouldRequestAppTracking = AppEnvironment.current.appTrackingTransparency
        .shouldRequestAuthorizationStatus() == true
      let hasNotSeenOnboarding = AppEnvironment.current.userDefaults.hasSeenOnboarding == false

      return shouldRequestAppTracking && hasNotSeenOnboarding
    }
    .mapConst(())

    // Deep links. For more information, see
    // https://app.getguru.com/card/cyRdjqgi/How-iOS-Universal-Links-work

    let deepLinkFromNotification = self.remoteNotificationProperty.signal.skipNil()
      .map { navigation(fromPushEnvelope: $0) }

    let urlFromBraze = self.brazeNotificationURLProperty.signal.skipNil()

    let deepLinkFromBraze = urlFromBraze.map { Navigation.deepLinkMatch($0) }

    let continueUserActivity = self.applicationContinueUserActivityProperty.signal.skipNil()

    let deepLinkUrl = Signal
      .merge(
        openUrl.map { $0.url },
        self.foundRedirectUrlProperty.signal.skipNil(),
        continueUserActivity
          .filter { $0.activityType == NSUserActivityTypeBrowsingWeb }
          .map { $0.webpageURL }
          .skipNil()
      )

    let deepLinkFromUrl = deepLinkUrl.map { Navigation.match($0) }

    let performShortcutItem = Signal.merge(
      self.performActionForShortcutItemProperty.signal.skipNil(),
      self.applicationLaunchOptionsProperty.signal
        .map { $0?.options?[UIApplication.LaunchOptionsKey.shortcutItem] as? UIApplicationShortcutItem }
        .skipNil()
    )
    .map { ShortcutItem(typeString: $0.type) }
    .skipNil()

    let deepLinkFromShortcut = performShortcutItem
      .switchMap(navigation(fromShortcutItem:))

    let deeplinkActivated = Signal
      .merge(
        deepLinkFromUrl,
        deepLinkFromNotification,
        deepLinkFromBraze,
        deepLinkFromShortcut
      )
      .skipNil()

    let deepLink = deeplinkActivated
    let destinations = deepLink.switchMap { navigation -> SignalProducer<AppLifecycleFeature.Destination, Never> in
      if navigation == .emailClick { return .empty }
      redirectObservation.cancel()
      // Admit synchronously so every newer link invalidates old work immediately.
      let request = lifecycleFeature.requestDestination(navigation, route: route)
      return lifecycleResult(feature: lifecycleFeature) { try await request.value }.demoteErrors().skipNil()
    }

    let updatedUserNotificationSettings = deepLink.filter { nav in
      guard case .settings(.notifications) = nav else { return false }
      return true
    }
    .flatMap { navigation -> SignalProducer<User, Never> in
      guard case let .settings(.notifications(notification, enabled)) = navigation else { return .empty }
      guard let request = settingsFeature.requestNotification(named: notification, enabled: enabled) else { return .empty }
      return lifecycleResult(feature: lifecycleFeature) { try await request.value }
        .ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
        .demoteErrors()
    }

    self.updateCurrentUserInEnvironment = currentUserEvent.values().skipNil()
    self.notificationSettingsUpdated = updatedUserNotificationSettings.ignoreValues()

    let emailVerificationEvent = deepLinkUrl
      .filter { Navigation.match($0) == .profile(.verifyEmail) }
      .map(accessTokenFromUrl)
      .skipNil()
      .switchMap { accessToken in
        let request = settingsFeature.requestVerification(token: accessToken)
        return lifecycleResult(feature: lifecycleFeature) { try await request.value }
          .ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
          .materialize()
      }

    self.emailVerificationCompleted = emailVerificationEvent
      .map(emailVerificationCompletionData)
      .skipNil()

    self.findRedirectUrl = deepLinkUrl
      .filter { Navigation.match($0) == .emailClick }

    self.goToDiscovery = destinations
      .map { destination -> DiscoveryParams?? in
        guard case let .discovery(params) = destination else { return nil }
        return .some(params)
      }
      .skipNil()

    let fixErroredPledgeLinkAndNeedsToLogIn = deepLink
      .filter { link in
        guard case let .project(_, subpage, _, _) = link else { return false }
        guard case .pledge(.manage) = subpage else { return false }

        return AppEnvironment.current.currentUser == nil
      }

    self.goToActivity = deepLink
      .filter { $0 == .tab(.activity) }
      .ignoreValues()

    self.goToSearch = deepLink
      .filter { $0 == .tab(.search) }
      .ignoreValues()

    let goToLogin = deepLink
      .filter { $0 == .tab(.login) }
      .ignoreValues()

    self.goToLoginWithIntent = Signal.merge(
      fixErroredPledgeLinkAndNeedsToLogIn.mapConst(.erroredPledge),
      goToLogin.mapConst(.generic),
      self.goToLoginSignupProperty.signal.skipNil()
    )

    self.goToMessageThread = destinations.map { destination -> MessageThread? in
      guard case let .message(thread) = destination else { return nil }
      return thread
    }.skipNil()

    self.goToProfile = deepLink
      .filter { $0 == .tab(.me) }
      .ignoreValues()

    self.goToMobileSafari = Signal.merge(
      deepLinkUrl,
      urlFromBraze
    )
    .filter { shouldOpenUrlInBrowser($0) }

    let pledgeManagerLink = destinations
      .map { destination -> String? in
        guard case let .survey(url) = destination else { return nil }
        return url
      }.skipNil()
      .observeForUI()
      .map { url -> UINavigationController in
        let pm = PledgeManagerWebViewController.configuredWith(url: url)
        let navigation = UINavigationController(rootViewController: pm)
        navigation.modalPresentationStyle = .pageSheet
        return navigation
      }

    let projectLinks = destinations
      .map { destination -> AppLifecycleFeature.ProjectDestination? in
        guard case let .project(project) = destination else { return nil }
        return project
      }.skipNil().observeForUI()
      .map(ProjectDeepLink.viewController).skipNil()

    self.presentViewController = Signal.merge(
      projectLinks,
      pledgeManagerLink
    ).map { $0 as UIViewController }



    self.setApplicationShortcutItems = currentUserEvent
      .values()
      .switchMap { user in shortcutItems(forUser: user, feature: lifecycleFeature) }


    self.applicationIconBadgeNumber = Signal.merge(
      self.applicationWillEnterForegroundProperty.signal,
      self.applicationLaunchOptionsProperty.signal.ignoreValues()
    )
    .flatMap { pushAuthorizationStatusProducer() }
    .filter(isTrue)
    .mapConst(0)




    /// Request AppTransparencyTracking outside of onboarding.
    self.requestATTrackingAuthorizationStatus = Signal
      .combineLatest(
        self.applicationLaunchOptionsProperty.signal.ignoreValues(),
        self.applicationActiveProperty.signal
      )
      .map(second)
      .skipRepeats()
      .ksr_delay(.seconds(1), on: AppEnvironment.current.scheduler)
      .filter { applicationIsActive in
        /// Only attempt to request authorization outside of onboarding if the application is active and the user has seen the onboarding flow.
        /// We don't want to request authorzation in the onboarding flow unless they've tapped the "all tracking" CTA.
        let hasSeenOnboarding = AppEnvironment.current.userDefaults.hasSeenOnboarding == true

        return applicationIsActive && hasSeenOnboarding
      }
      .map { _ in AppEnvironment.current.appTrackingTransparency }
      .map { appTrackingTransparency in
        if
          appTrackingTransparency.advertisingIdentifier == nil &&
          appTrackingTransparency.shouldRequestAuthorizationStatus() {
          appTrackingTransparency.requestAndSetAuthorizationStatus(nil)
        }
        return ()
      }

    self.trackingAuthorizationStatus = SignalProducer
      .merge(
        self.applicationLaunchOptionsProperty.signal.ignoreValues(),
        self.applicationActiveProperty.signal.ignoreValues()
      )
      .flatMap { () in
        SignalProducer { observer, lifetime in
          let tracking = AppEnvironment.current.appTrackingTransparency
          let id = tracking.observeAuthorizationStatus { observer.send(value: $0) }
          lifetime.observeEnded {
            Task { @MainActor in tracking.removeAuthorizationObserver(id) }
          }
        }
      }
  }

  deinit {
    self.pushDebounceTask?.cancel()
    self.pushPresentationTask?.cancel()
    self.configurationTask?.cancel()
    let redirectObservation = self.redirectObservation
    let feature = self.lifecycleFeature
    let route = self.navigationRoute
    Task { @MainActor in
      redirectObservation.cancel()
      feature.release(route: route)
    }
  }

  public var inputs: AppDelegateViewModelInputs { return self }
  public var outputs: AppDelegateViewModelOutputs { return self }

  private func refreshConfiguration() {
    visitorCookies().forEach(AppEnvironment.current.cookieStorage.setCookie)
    self.configurationTask?.cancel()
    let request = self.lifecycleFeature.requestConfiguration()
    self.configurationTask = Task { [weak self] in
      do {
        let config = try await request.value
        try Task.checkCancellation()
        self?.onUpdateConfig?(configRetainingDebugFeatureFlags(config))
      } catch { /* Configuration failures leave the current configuration in place. */ }
    }
  }

  func waitForConfiguration() async { await self.configurationTask?.value }

  public func resolveEmailRedirect(_ url: URL) {
    if self.redirectObservation.input == url, self.redirectObservation.task != nil { return }
    self.redirectObservation.task?.cancel()
    self.redirectObservation.input = url
    let id = UUID()
    self.redirectObservation.id = id
    let feature = self.lifecycleFeature, route = self.navigationRoute
    self.redirectObservation.task = Task { [weak self] in
      defer {
        if self?.redirectObservation.id == id { self?.redirectObservation.task = nil; self?.redirectObservation.input = nil }
      }
      do {
        let destination = try await feature.firstRedirect(url, route: route)
        try Task.checkCancellation()
        guard let self, self.redirectObservation.id == id, let destination else { return }
        self.foundRedirectUrl(destination)
      } catch { /* Preserve the existing silent failure/no-redirect behavior. */ }
    }
  }

  fileprivate let applicationContinueUserActivityProperty = MutableProperty<NSUserActivity?>(nil)
  public func applicationContinueUserActivity(_ userActivity: NSUserActivity) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
      self.continueUserActivityReturnValue = userActivity.webpageURL.flatMap { Navigation.match($0) } != nil
    }
    self.applicationContinueUserActivityProperty.value = userActivity
    return self.continueUserActivityReturnValue
  }

  fileprivate typealias ApplicationWithOptions = (
    application: UIApplication?, options: [UIApplication.LaunchOptionsKey: Any]?
  )
  fileprivate let applicationLaunchOptionsProperty = MutableProperty<ApplicationWithOptions?>(nil)
  public func applicationDidFinishLaunching(
    application: UIApplication?,
    launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) {
    self.applicationDidFinishLaunchingReturnValue = launchOptions?[UIApplication.LaunchOptionsKey.shortcutItem] == nil
    self.applicationLaunchOptionsProperty.value = (application, launchOptions)
    self.refreshConfiguration()
    self.onSynchronizeUbiquitousStore?()
    self.onConfigureFirebase?()
    self.onConfigureStatsig?(statsigSDKKey())
    self.onConfigureSegmentWithBraze?(
      AppEnvironment.current.mainBundle.isRelease ? Secrets.Segment.production : Secrets.Segment.staging
    )
  }

  fileprivate let applicationWillEnterForegroundProperty = MutableProperty(())
  public func applicationWillEnterForeground() {
    self.applicationWillEnterForegroundProperty.value = ()
    self.refreshConfiguration()
  }

  fileprivate let applicationActiveProperty = MutableProperty<Bool>(false)
  public func applicationActive(state: Bool) {
    self.applicationActiveProperty.value = state
  }

  public func applicationDidEnterBackground() {
    self.onPostNotification?(Notification(name: .ksr_applicationDidEnterBackground, object: nil))
  }

  fileprivate let applicationDidReceiveMemoryWarningProperty = MutableProperty(())
  public func applicationDidReceiveMemoryWarning() {
    self.applicationDidReceiveMemoryWarningProperty.value = ()
  }

  fileprivate let performActionForShortcutItemProperty = MutableProperty<UIApplicationShortcutItem?>(nil)
  public func applicationPerformActionForShortcutItem(_ item: UIApplicationShortcutItem) {
    self.performActionForShortcutItemProperty.value = item
  }

  public func currentUserUpdatedInEnvironment() {
    self.onPostNotification?(Notification(name: .ksr_userUpdated, object: nil))
  }

  public func configUpdatedNotificationObserved() {
    self.publishSegmentEnabledIfChanged()
  }

  private func publishSegmentEnabledIfChanged() {
    let enabled = featureSegmentIsEnabled()
    guard self.lastSegmentEnabled != enabled else { return }
    self.lastSegmentEnabled = enabled
    self.onSegmentEnabled?(enabled)
  }

  fileprivate let remoteNotificationProperty = MutableProperty<PushEnvelope?>(nil)
  public func didReceive(remoteNotification notification: [AnyHashable: Any]) {
    self.remoteNotificationProperty.value = PushEnvelope.decodeJSONDictionary(notification)
  }

  public func didReceive(pushEnvelope: PushEnvelope) {
    self.remoteNotificationProperty.value = pushEnvelope
  }

  public func didRegisterForRemoteNotifications(withDeviceTokenData data: Data) {
    self.onRegisterPushTokenInBraze?(data)
    self.pushDebounceTask?.cancel()
    let token = deviceToken(fromData: data)
    let debounce = self.pushDebounce
    self.pushDebounceTask = Task { [weak self] in
      do {
        try await debounce()
        try Task.checkCancellation()
        guard let self else { return }
        self.pushPresentationTask?.cancel()
        let request = self.lifecycleFeature.requestPushRegistration(token: token)
        self.pushPresentationTask = Task { [weak self] in
          do {
            let registeredToken = try await request.value
            try Task.checkCancellation()
            self?.onPushTokenSuccessfullyRegistered?(registeredToken)
          } catch { /* Keep registration failures silent. */ }
        }
      } catch { /* A newer token superseded this debounce. */ }
    }
  }

  func waitForPushRegistration() async {
    await self.pushDebounceTask?.value
    await self.pushPresentationTask?.value
  }

  fileprivate let didAcceptReceivingRemoteNotificationsProperty = MutableProperty(())
  public func didAcceptReceivingRemoteNotifications() {
    self.didAcceptReceivingRemoteNotificationsProperty.value = ()
  }

  public func didUpdateConfig(_ config: Config) {
    self.publishSegmentEnabledIfChanged()
    self.onPostNotification?(Notification(name: .ksr_configUpdated, object: nil))
  }

  public func didUpdateRemoteConfigClient() {
    self.onPostNotification?(Notification(name: .ksr_remoteConfigClientConfigured, object: nil))
  }

  private let foundRedirectUrlProperty = MutableProperty<URL?>(nil)
  public func foundRedirectUrl(_ url: URL) {
    self.foundRedirectUrlProperty.value = url
  }

  private let goToLoginSignupProperty = MutableProperty<LoginIntent?>(nil)
  public func goToLoginSignup(from intent: LoginIntent) {
    self.goToLoginSignupProperty.value = intent
  }

  fileprivate typealias ApplicationOpenUrl = (
    application: UIApplication?,
    url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any]
  )
  fileprivate let applicationOpenUrlProperty = MutableProperty<ApplicationOpenUrl?>(nil)
  public func applicationOpenUrl(
    application: UIApplication?,
    url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any]
  ) -> Bool {
    self.applicationOpenUrlProperty.value = (application, url, options)
    return true
  }

  public func showNotificationDialog(notification: Notification) {
    guard let context = notification.userInfo?[UserInfoKeys.context] as? PushNotificationDialog.Context,
          PushNotificationDialog.canShowDialog(for: context) else { return }
    self.onShowAlert?(notification)
  }

  fileprivate let userSessionEndedProperty = MutableProperty(())
  public func userSessionEnded() {
    self.userSessionEndedProperty.value = ()
    self.refreshConfiguration()
    self.onUnregisterForRemoteNotifications?()
  }

  fileprivate let userSessionStartedProperty = MutableProperty(())
  public func userSessionStarted() {
    self.userSessionStartedProperty.value = ()
    self.refreshConfiguration()
  }

  fileprivate let brazeNotificationURLProperty = MutableProperty<URL?>(nil)
  public func urlFromBrazeNotification(_ url: URL?) {
    self.brazeNotificationURLProperty.value = url
  }

  public private(set) var applicationDidFinishLaunchingReturnValue = true

  public func remoteConfigClientConfigurationFailed() {
    self.onPostNotification?(Notification(name: .ksr_remoteConfigClientConfigurationFailed, object: nil))
  }

  public let applicationIconBadgeNumber: Signal<Int, Never>
  public var onConfigureFirebase: (() -> Void)?
  public var onConfigureSegmentWithBraze: ((String) -> Void)?
  public var onConfigureStatsig: ((StatsigClientSDKKey) -> Void)?
  public private(set) var continueUserActivityReturnValue = false
  public let emailVerificationCompleted: Signal<(String, Bool), Never>
  public let findRedirectUrl: Signal<URL, Never>
  public let forceLogout: Signal<(), Never>
  private let fetchUserEmail: Signal<(), Never>
  public let goToActivity: Signal<(), Never>
  public let goToDiscovery: Signal<DiscoveryParams?, Never>
  public let goToLoginWithIntent: Signal<LoginIntent, Never>
  public let goToMessageThread: Signal<MessageThread, Never>
  public let goToProfile: Signal<(), Never>
  public let goToMobileSafari: Signal<URL, Never>
  public let goToSearch: Signal<(), Never>
  public var onPostNotification: ((Notification) -> Void)?
  public let presentViewController: Signal<UIViewController, Never>
  public let pushTokenRegistrationStarted: Signal<(), Never>
  public var onPushTokenSuccessfullyRegistered: ((String) -> Void)?
  public var onRegisterPushTokenInBraze: ((Data) -> Void)?
  public let requestATTrackingAuthorizationStatus: Signal<Void, Never>
  public var onSegmentEnabled: ((Bool) -> Void)?
  public let setApplicationShortcutItems: Signal<[ShortcutItem], Never>
  public var onShowAlert: ((Notification) -> Void)?
  public var onSynchronizeUbiquitousStore: (() -> Void)?
  public let trackingAuthorizationStatus: SignalProducer<AppTrackingAuthorization, Never>
  public let triggerOnboardingFlow: Signal<(), Never>
  public var onUnregisterForRemoteNotifications: (() -> Void)?
  public let updateCurrentUserInEnvironment: Signal<User, Never>
  public let notificationSettingsUpdated: Signal<Void, Never>
  public var onUpdateConfig: ((Config) -> Void)?
}

/// Handles the deeplink route with both an id and text based name for a deeplink to categories.
private func deviceToken(fromData data: Data) -> String {
  return data
    .map { String(format: "%02.2hhx", $0 as CVarArg) }
    .joined()
}

@MainActor
private func shouldOpenUrlInBrowser(_ url: URL) -> Bool {
  // If url has a deeplink match, never attempt to open the url in the browser.
  if Navigation.deepLinkMatch(url) != nil {
    return false
  }
  // Never attempt to open `ksr` urls in the browser; they'll redirect straight back to our app.
  if let scheme = url.scheme, scheme == "ksr" {
    print(
      "Error: Unable to open 'ksr' deeplink. Please doublecheck that the url "
        + "is included in the list of deeplinks and that you're not trying to "
        + "use a staging url in prod (or vice versa)."
    )
    let error = NSError(domain: "Kickstarter.Deeplink", code: 0, userInfo: [
      NSLocalizedDescriptionKey: "Unable to open unsupported ksr deeplink."
    ])
    Crashlytics.crashlytics().record(error: error)
    return false
  }
  // Otherwise, open url in browser.
  return true
}

@MainActor
private func navigation(fromPushEnvelope envelope: PushEnvelope) -> Navigation? {
  if let activity = envelope.activity {
    switch activity.category {
    case .backing:
      guard let projectId = activity.projectId else { return nil }
      return .project(.id(projectId), .root, refInfo: RefInfo(.push))
    case .failure, .launch, .success, .cancellation, .suspension:
      guard let projectId = activity.projectId else { return nil }
      return .project(.id(projectId), .root, refInfo: RefInfo(.push))

    case .update:
      guard let projectId = activity.projectId, let updateId = activity.updateId else { return nil }
      return .project(.id(projectId), .update(updateId, .root), refInfo: RefInfo(.push))

    case .commentPost:
      guard let projectId = activity.projectId, let updateId = activity.updateId else { return nil }

      if let commentId = activity.commentId {
        return .project(
          .id(projectId),
          .update(updateId, .commentThread(commentId, activity.replyId)),
          refInfo: RefInfo(.push)
        )
      }
      return .project(.id(projectId), .update(updateId, .comments), refInfo: RefInfo(.push))

    case .commentProject:
      guard let projectId = activity.projectId else { return nil }

      if let commentId = activity.commentId {
        return .project(.id(projectId), .commentThread(commentId, activity.replyId), refInfo: RefInfo(.push))
      }
      return .project(.id(projectId), .comments, refInfo: RefInfo(.push))

    case .follow:
      return .tab(.activity)

    case .funding, .shipped, .unknown, .watch:
      return nil
    }
  }

  if let order = envelope.order {
    let path = order.pledgeManagerPath
    let url = AppEnvironment.current.apiService.serverConfig.webBaseUrl.absoluteString + path
    return .project(.id(order.projectId), .pledgeManagerWebview(url), refInfo: RefInfo(.push))
  }

  if let project = envelope.project {
    return .project(.id(project.id), .root, refInfo: RefInfo(.push))
  }

  if let message = envelope.message {
    return .messages(messageThreadId: message.messageThreadId)
  }

  if let survey = envelope.survey {
    let path = survey.urls.web.survey
    let url = AppEnvironment.current.apiService.serverConfig.webBaseUrl.absoluteString + path
    return .project(.id(survey.projectId), .pledgeManagerWebview(url), refInfo: RefInfo(.push))
  }

  if let update = envelope.update {
    return .project(.id(update.projectId), .update(update.id, .root), refInfo: RefInfo(.push))
  }

  if let erroredPledge = envelope.erroredPledge {
    return .project(.id(erroredPledge.projectId), .pledge(.manage), refInfo: RefInfo(.push))
  }

  return nil
}

// Figures out a `Navigation` to route the user to from a shortcut item.
private func navigation(fromShortcutItem shortcutItem: ShortcutItem) -> SignalProducer<Navigation?, Never> {
  switch shortcutItem {
  case .recommendedForYou:
    let params = .defaults
      |> DiscoveryParams.lens.recommended .~ true
      |> DiscoveryParams.lens.sort .~ .magic
    return SignalProducer(value: .tab(.discovery(params.queryParams)))

  case .projectsWeLove:
    let params = .defaults
      |> DiscoveryParams.lens.staffPicks .~ true
      |> DiscoveryParams.lens.sort .~ .magic
    return SignalProducer(value: .tab(.discovery(params.queryParams)))

  case .search:
    return SignalProducer(value: .tab(.search))
  }
}

// The settings owner checks its own session, including permitted token restoration.
@MainActor
private func lifecycleReadResult<Value>(_ request: Task<Value, Error>) -> SignalProducer<Value, ErrorEnvelope> {
  SignalProducer { observer, lifetime in
    let waiter = Task { @MainActor in
      do {
        let value = try await request.value
        try Task.checkCancellation()
        observer.send(value: value)
        observer.sendCompleted()
      } catch {
        if Task.isCancelled || error is CancellationError { observer.sendInterrupted() }
        else { observer.send(error: (error as? ErrorEnvelope) ?? .couldNotParseJSON) }
      }
    }
    lifetime.observeEnded { waiter.cancel(); request.cancel() }
  }
}

// Transitional adapter owned by the legacy app delegate presentation layer.
@MainActor
private func lifecycleResult<Value>(
  feature: AppLifecycleFeature, operation: @escaping @MainActor () async throws -> Value
) -> SignalProducer<Value, ErrorEnvelope> {
  let admitted = feature.sessionBound(operation)
  return SignalProducer { observer, lifetime in
    MainActor.assumeIsolated {
      let task = Task { @MainActor in
        do {
          let value = try await admitted()
          observer.send(value: value)
          observer.sendCompleted()
        } catch {
          if Task.isCancelled || error is CancellationError { observer.sendInterrupted() }
          else { observer.send(error: (error as? ErrorEnvelope) ?? .couldNotParseJSON) }
        }
      }
      lifetime.observeEnded { task.cancel() }
    }
  }
}

// Rendering policy remains unchanged; the Feature owns the recommendation read.
@MainActor
private func shortcutItems(forUser user: User?, feature: AppLifecycleFeature) -> SignalProducer<[ShortcutItem], Never> {
  lifecycleResult(feature: feature) { try await feature.hasRecommendations(for: user) }
    .map { shortcutItems(isProjectMember: (user?.stats.memberProjectsCount ?? 0) > 0, hasRecommendations: $0) }
    .demoteErrors()
}

// Figures out which shortcut items to show to a user based on whether they are a project member and/or
// has recommendations.
private func shortcutItems(isProjectMember _: Bool, hasRecommendations: Bool)
  -> [ShortcutItem] {
  var items: [ShortcutItem] = []

  if hasRecommendations {
    items.append(.recommendedForYou)
  }

  items.append(.projectsWeLove)

  if items.count < 4 {
    items.append(.search)
  }

  return items
}

private func dictionary(fromUrlComponents urlComponents: URLComponents) -> [String: String] {
  let queryItems = urlComponents.queryItems ?? []
  return [String: String?].keyValuePairs(queryItems.map { ($0.name, $0.value) }).compact()
}

extension ShortcutItem {
  public var applicationShortcutItem: UIApplicationShortcutItem {
    switch self {
    case .projectsWeLove:
      return .init(
        type: self.typeString,
        localizedTitle: Strings.Projects_We_Love(),
        localizedSubtitle: nil,
        icon: UIApplicationShortcutIcon(templateImageName: "shortcut-icon-k"),
        userInfo: nil
      )
    case .recommendedForYou:
      return .init(
        type: self.typeString,
        localizedTitle: Strings.Recommended(),
        localizedSubtitle: nil,
        icon: UIApplicationShortcutIcon(templateImageName: "shortcut-icon-star"),
        userInfo: nil
      )
    case .search:
      return .init(
        type: self.typeString,
        localizedTitle: Strings.tabbar_search(),
        localizedSubtitle: nil,
        icon: UIApplicationShortcutIcon(templateImageName: "shortcut-icon-search"),
        userInfo: nil
      )
    }
  }
}

@MainActor
private func visitorCookies() -> [HTTPCookie] {
  let uuidString = (AppEnvironment.current.device.identifierForVendor ?? UUID()).uuidString

  return [HTTPCookie?].init(
    arrayLiteral:
    HTTPCookie(
      properties: [
        .name: "vis",
        .value: uuidString,
        .domain: AppEnvironment.current.apiService.serverConfig.webBaseUrl.host as Any,
        .path: "/",
        .version: 0,
        .expires: Date.distantFuture,
        .secure: true
      ]
    ),
    HTTPCookie(
      properties: [
        .name: "vis",
        .value: uuidString,
        .domain: AppEnvironment.current.apiService.serverConfig.apiBaseUrl.host as Any,
        .path: "/",
        .version: 0,
        .expires: Date.distantFuture,
        .secure: true
      ]
    )
  )
  .compact()
}

private func accessTokenFromUrl(_ url: URL?) -> String? {
  return url.flatMap { url in
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
  }?
    .first { item in item.name == "at" }?
    .value
}

private func emailVerificationCompletionData(
  event: Signal<EmailVerificationResponseEnvelope, ErrorEnvelope>.Event
) -> (String, Bool)? {
  guard !event.isCompleted else { return nil }

  guard isNil(event.error), let message = event.value?.message else {
    let message = event.error?.errorMessages.first ?? Strings.Something_went_wrong_please_try_again()

    return (message, false)
  }

  return (message, true)
}

@MainActor
private func configRetainingDebugFeatureFlags(_ config: Config) -> Config {
  guard AppEnvironment.current.mainBundle.isRelease == false else { return config }

  let currentFeatures = config.features
  let currentFeatureKeys = Set(currentFeatures.keys)

  let storedFeatures = (AppEnvironment.current.config?.features ?? [:])
    .filter { key, _ in currentFeatureKeys.contains(key) }

  return config |> Config.lens.features .~ currentFeatures.withAllValuesFrom(storedFeatures)
}

/// Pure UIKit composition from one fully resolved destination.
@MainActor
private enum ProjectDeepLink {
  static func viewController(_ destination: AppLifecycleFeature.ProjectDestination) -> UINavigationController? {
    let project = destination.project
    let page = ProjectPageViewController.configuredWith(
      projectOrParam: .left(project), refInfo: destination.refInfo,
      secretRewardToken: destination.secretRewardToken
    )
    var controllers: [UIViewController] = [page]
    switch destination.subpage {
    case .root: break
    case .comments:
      controllers.append(commentsViewController(for: project, update: nil))
    case let .commentThread(_, replyID):
      guard let replies = destination.replies else { return nil }
      controllers += [commentsViewController(for: project, update: nil),
        CommentRepliesViewController.configuredWith(comment: replies.comment, project: project, update: nil,
          inputAreaBecomeFirstResponder: false, replyId: replyID)]
    case .updates:
      controllers.append(ProjectUpdatesViewController.configuredWith(project: project))
    case let .update(_, subpage):
      guard let update = destination.update else { return nil }
      controllers.append(UpdateViewController.configuredWith(project: project, update: update, context: .deepLink))
      switch subpage {
      case .root: break
      case .comments: controllers.append(commentsViewController(update: update))
      case let .commentThread(_, replyID):
        guard let replies = destination.replies else { return nil }
        controllers += [commentsViewController(for: nil, update: update),
          CommentRepliesViewController.configuredWith(comment: replies.comment, project: project, update: update,
            inputAreaBecomeFirstResponder: false, replyId: replyID)]
      }
    case .pledge(.manage):
      guard AppEnvironment.current.currentUser != nil, let backingID = project.personalization.backing?.id else { return nil }
      let controller = ManagePledgeViewController.instantiate()
      controller.configureWith(params: (.id(project.id), .id(backingID)))
      controllers.append(controller)
      let navigation = RewardPledgeNavigationController(nibName: nil, bundle: nil)
      navigation.viewControllers = controllers
      navigation.modalPresentationStyle = .pageSheet
      return navigation
    default: return nil
    }
    return ProjectPageViewController.navigationController(withViewControllers: controllers)
  }
}

@MainActor
private func statsigSDKKey() -> StatsigClientSDKKey {
  let mainBundle = AppEnvironment.current.mainBundle

  if mainBundle.isRelease {
    return .productionTier(Secrets.Statsig.production)
  } else if mainBundle.isBeta {
    return .stagingTier(Secrets.Statsig.staging)
  } else if mainBundle.isDebug {
    return .developmentTier(Secrets.Statsig.development)
  }

  return .stagingTier(Secrets.Statsig.sandbox)
}

// Temporary presentation adapters; the registration service itself owns native tasks.
@MainActor
private func pushAuthorizationStatusProducer() -> SignalProducer<Bool, Never> {
  SignalProducer { observer, lifetime in
    let task = AppEnvironment.current.pushRegistrationType.hasAuthorizedNotifications { value in
      observer.send(value: value)
      observer.sendCompleted()
    }
    lifetime.observeEnded { task?.cancel() }
  }
}

@MainActor
private func pushRegistrationProducer() -> SignalProducer<Bool, Never> {
  SignalProducer { observer, lifetime in
    let task = AppEnvironment.current.pushRegistrationType.register(for: [.alert, .sound, .badge]) { value in
      observer.send(value: value)
      observer.sendCompleted()
    }
    lifetime.observeEnded { task?.cancel() }
  }
}
