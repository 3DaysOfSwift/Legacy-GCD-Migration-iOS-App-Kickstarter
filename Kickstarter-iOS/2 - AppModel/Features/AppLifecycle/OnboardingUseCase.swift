import Foundation
import KsApi
import Lottie
import UIKit

public enum OnboardingItemType {
  case welcome, saveProjects, enableNotifications, allowTracking, loginSignUp

  /// Used to send analytics around whether the user decided to skip the push notification or apptracking permission request dialogs.
  var isPermissionType: Bool {
    switch self {
    case .allowTracking, .enableNotifications:
      return true
    default:
      return false
    }
  }

  var lottieFileName: String {
    switch self {
    case .welcome:
      "onboarding-flow-welcome"
    case .allowTracking:
      "onboarding-flow-activity-tracking"
    case .enableNotifications:
      "onboarding-flow-enable-notifications"
    case .saveProjects:
      "onboarding-flow-save-projects"
    case .loginSignUp:
      "onboarding-flow-login-signup"
    }
  }
}

public struct OnboardingItem: Identifiable, Equatable {
  public let id: UUID = .init()
  public let title: String
  public let subtitle: String
  public var lottieView: LottieAnimationView
  public let type: OnboardingItemType

  @MainActor public init(
    title: String,
    subtitle: String,
    lottieView: LottieAnimationView = .init(),
    type: OnboardingItemType
  ) {
    self.title = title
    self.subtitle = subtitle
    self.lottieView = lottieView
    self.type = type
  }
}

@MainActor
public protocol OnboardingUseCaseType {
  var uiInputs: OnboardingUseCaseUIInputs { get }
  var uiOutputs: OnboardingUseCaseUIOutputs { get }
}

@MainActor
public protocol OnboardingUseCaseUIInputs {
  /// Indicates whether the tracking permission prompt is needed.
  func allowTrackingTapped() -> Bool
}

@MainActor
public protocol OnboardingUseCaseUIOutputs {
  var onboardingItems: [OnboardingItem] { get }
}

/// Provides onboarding content and determines whether tracking permission is needed.
@MainActor
public final class OnboardingUseCase: OnboardingUseCaseType, OnboardingUseCaseUIInputs,
  OnboardingUseCaseUIOutputs {
  // MARK: - Initialization

  /// Injecting a bundle so that we can test that the correct Lottie JSON files are being loaded as expected.
  init(for bundle: Bundle = .main) {
    let onboardingItems = allOnboardingItems(in: bundle)

    self.onboardingItems = onboardingItems
  }

  // MARK: - Inputs

  public func allowTrackingTapped() -> Bool {
    let tracking = AppEnvironment.current.appTrackingTransparency
    return tracking.advertisingIdentifier == nil && tracking.shouldRequestAuthorizationStatus()
  }

  // MARK: - Data Outputs

  public let onboardingItems: [OnboardingItem]

  // MARK: - Type

  public var uiInputs: any OnboardingUseCaseUIInputs { return self }
  public var uiOutputs: any OnboardingUseCaseUIOutputs { return self }
}

// MARK: - Helpers

@MainActor
private func allOnboardingItems(
  in bundle: Bundle = .main
) -> [OnboardingItem] {
  return [
    makeOnboardingItem(
      title: Strings.onboarding_welcome_to_kickstarter_title(),
      subTitle: Strings.onboarding_welcome_to_kickstarter_subtitle(),
      type: .welcome,
      in: bundle
    ),
    makeOnboardingItem(
      title: Strings.onboarding_save_projects_for_later_title(),
      subTitle: Strings.onboarding_save_projects_for_later_subtitle(),
      type: .saveProjects,
      in: bundle
    ),
    makeOnboardingItem(
      title: Strings.onboarding_personalize_your_experience_title(),
      subTitle: Strings.onboarding_personalize_your_experience_subtitle(),
      type: .allowTracking,
      in: bundle
    ),
    makeOnboardingItem(
      title: Strings.onboarding_stay_in_the_know_title(),
      subTitle: Strings.onboarding_stay_in_the_know_subtitle(),
      type: .enableNotifications,
      in: bundle
    ),
    makeOnboardingItem(
      title: Strings.onboarding_join_the_community_title(),
      subTitle: Strings.onboarding_join_the_community_subtitle(),
      type: .loginSignUp,
      in: bundle
    )
  ]
  .compactMap { $0 }
}

@MainActor
private func makeOnboardingItem(
  title: String,
  subTitle: String,
  type: OnboardingItemType,
  in bundle: Bundle = .main
) -> OnboardingItem? {
  guard let lottieName = localizedOnboardingLottieFile(for: type.lottieFileName, in: bundle) else {
    assertionFailure("Missing Lottie file for onboarding type: \(type)")
    return nil
  }

  return OnboardingItem(
    title: title,
    subtitle: subTitle,
    lottieView: .init(name: lottieName, bundle: bundle),
    type: type
  )
}
