import AppTrackingTransparency
import Foundation
import KsApi
import UserNotifications

@MainActor
public protocol OnboardingViewModelInputs {
  func allowTrackingTapped()
  func didCompleteAppTrackingDialog(with authStatus: ATTrackingManager.AuthorizationStatus)
  func didCompletePushNotificationsDialog(with authStatus: UNAuthorizationStatus)
  func getNotifiedTapped()
  func goToLoginSignupTapped()
  func goToNextItemTapped(item: OnboardingItem)
  func onAppear()
  func onboardingFlowEnded()
}

@MainActor
public protocol OnboardingViewModelOutputs {
  var onboardingItems: [OnboardingItem] { get }
}

@MainActor
public protocol OnboardingViewModelType {
  var inputs: OnboardingViewModelInputs { get }
  var outputs: OnboardingViewModelOutputs { get }
}

@MainActor
public final class OnboardingViewModel: OnboardingViewModelType, Equatable & Identifiable & ObservableObject,
  OnboardingViewModelOutputs, OnboardingViewModelInputs {
  @MainActor private var completionTask: Task<Void, Never>?
  @MainActor private var completionVersion = UUID()
  var onTrackingPrompt: (() -> Void)?
  var onNotificationCompletion: ((UNAuthorizationStatus) -> Void)?

  /// Own the subscriptions for this appearance and invalidate callbacks on exit.
  @MainActor public func bind(
    items: @escaping ([OnboardingItem]) -> Void,
    advance: @escaping () -> Void
  ) {
    self.stopObserving()
    items(self.onboardingItems)
    self.onNotificationCompletion = { [weak self] status in
      self?.didCompletePushNotificationsDialog(with: status)
      advance()
    }
    self.onTrackingPrompt = { [weak self] in
      self?.completeTracking(advance: advance)
    }
  }
  @MainActor public func cancelCompletion() {
    self.completionTask?.cancel()
    self.completionTask = nil
    self.completionVersion = UUID()
  }
  @MainActor public func stopObserving() {
    self.cancelCompletion()
    self.onNotificationCompletion = nil
    self.onTrackingPrompt = nil
  }
  @MainActor private func completeTracking(advance: @escaping () -> Void) {
    guard self.completionTask == nil else { return }
    let version = self.completionVersion
    let feature = self.lifecycleFeature ?? AppModel.shared.appLifecycleFeature
    self.completionTask = Task { [weak self] in
      let status = await feature.trackingAuthorization()
      guard !Task.isCancelled, let self, self.completionVersion == version else { return }
      self.didCompleteAppTrackingDialog(with: status)
      advance()
    }
  }

  // MARK: - Properties

  private let lifecycleFeature: AppLifecycleFeature?
  private let useCase: OnboardingUseCaseType

  // MARK: - Outputs

  public let onboardingItems: [OnboardingItem]

  // MARK: - Init

  public init(with bundle: Bundle = .main, lifecycleFeature: AppLifecycleFeature? = nil) {
    self.lifecycleFeature = lifecycleFeature
    self.useCase = OnboardingUseCase(for: bundle)

    self.onboardingItems = self.useCase.uiOutputs.onboardingItems

  }

  public nonisolated static func == (lhs: OnboardingViewModel, rhs: OnboardingViewModel) -> Bool {
    lhs.id == rhs.id
  }

  public var inputs: OnboardingViewModelInputs { return self }
  public var outputs: OnboardingViewModelOutputs { return self }

  // MARK: - Inputs

  public func onAppear() {
    AppEnvironment.current.ksrAnalytics.trackOnboardingPageViewed(at: .welcome)
  }

  public func getNotifiedTapped() {
    guard self.completionTask == nil else { return }
    let feature = self.lifecycleFeature ?? AppModel.shared.appLifecycleFeature
    let version = self.completionVersion
    self.completionTask = Task { [weak self] in
      let existing = await feature.notificationStatus()
      guard !Task.isCancelled, let self, self.completionVersion == version else { return }
      guard existing != .authorized else { self.completionTask = nil; return }
      AppEnvironment.current.ksrAnalytics.trackSystemPermissionsDialogViewed(on: .onboardingNotificationsDialog)
      _ = await feature.notificationAuthorization(options: [.alert, .sound, .badge])
      guard !Task.isCancelled, self.completionVersion == version else { return }
      let status = await feature.notificationStatus()
      guard !Task.isCancelled, self.completionVersion == version else { return }
      self.onNotificationCompletion?(status)
    }

    AppEnvironment.current.ksrAnalytics.trackOnboardingPageButtonTapped(
      context: .onboardingGetNotified,
      item: .enableNotifications
    )
  }

  public func allowTrackingTapped() {
    if self.useCase.uiInputs.allowTrackingTapped(), let prompt = self.onTrackingPrompt {
      AppEnvironment.current.ksrAnalytics.trackSystemPermissionsDialogViewed(on: .onboardingAppTrackingDialog)
      prompt()
    }

    AppEnvironment.current.ksrAnalytics.trackOnboardingPageButtonTapped(
      context: .onboardingAllowTracking,
      item: .allowTracking
    )
  }

  public func didCompletePushNotificationsDialog(with authStatus: UNAuthorizationStatus) {
    /// Send analytics event when the user has finished interacting with the PN system dialog. `authStatus` let's insights know whether they allowed or denied permissions.

    AppEnvironment.current.ksrAnalytics.trackPushNotificationPermissionsDialogInteraction(
      .onboardingNotificationsDialog,
      authStatus: authStatus
    )
  }

  public func didCompleteAppTrackingDialog(with authStatus: ATTrackingManager.AuthorizationStatus) {
    /// Send analytics event if the user has allowed AppTracking permission.
    guard authStatus == .authorized else { return }

    AppEnvironment.current.ksrAnalytics.trackAppTrackingTransparencyPermissionsDialogInteraction(
      .onboardingAppTrackingDialog
    )
  }

  public func goToLoginSignupTapped() {
    AppEnvironment.current.ksrAnalytics.trackOnboardingPageButtonTapped(
      context: .onboardingSignUpLogIn,
      item: .loginSignUp
    )

    AppEnvironment.current.ksrAnalytics.trackOnboardingPageButtonTapped(context: .onboardingClose)
  }

  public func onboardingFlowEnded() {
    AppEnvironment.current.ksrAnalytics.trackOnboardingPageButtonTapped(context: .onboardingClose)
  }

  public func goToNextItemTapped(item: OnboardingItem) {
    AppEnvironment.current.ksrAnalytics.trackOnboardingPageViewed(at: item.type)
    AppEnvironment.current.ksrAnalytics.trackOnboardingPageButtonTapped(
      context: .onboardingNext,
      item: item.type
    )
  }
}
