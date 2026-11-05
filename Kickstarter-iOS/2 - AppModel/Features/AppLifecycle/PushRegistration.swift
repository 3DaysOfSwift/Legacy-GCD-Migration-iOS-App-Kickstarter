import Foundation
import UserNotifications

@MainActor
public struct PushRegistration: PushRegistrationType {
  public static func register(for options: UNAuthorizationOptions, completion: @escaping @MainActor (Bool) -> Void) -> Task<Void, Never>? {
    Task { @MainActor in
      guard !Task.isCancelled else { return }
      let granted = await AppModel.shared.appLifecycleFeature.notificationAuthorization(options: options)
      guard !Task.isCancelled else { return }
      completion(granted)
    }
  }

  public static func hasAuthorizedNotifications(completion: @escaping @MainActor (Bool) -> Void) -> Task<Void, Never>? {
    Task { @MainActor in
      guard !Task.isCancelled else { return }
      let settings = await UNUserNotificationCenter.current().notificationSettings()
      guard !Task.isCancelled else { return }
      completion(settings.authorizationStatus == .authorized)
    }
  }
}
