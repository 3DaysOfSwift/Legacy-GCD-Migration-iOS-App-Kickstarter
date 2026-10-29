import Foundation
import ReactiveSwift
import UIKit
import UserNotifications

public struct PushRegistration: PushRegistrationType {
  /// Compatibility output adapter. The lifecycle Feature owns admitted prompts;
  /// disposing this observer suppresses delivery without retracting system consent.
  public static func register(for options: UNAuthorizationOptions) -> SignalProducer<Bool, Never> {
    SignalProducer { observer, lifetime in
      let task = Task { @MainActor in
        guard !Task.isCancelled else { return }
        let granted = await AppModel.shared.appLifecycleFeature.notificationAuthorization(options: options)
        guard !Task.isCancelled else { return }
        observer.send(value: granted)
        observer.sendCompleted()
      }
      lifetime.observeEnded { task.cancel() }
    }
  }

  /// Native settings read; no background-thread delivery contract is required by
  /// consumers, which already observe UI work through their UI scheduler.
  public static func hasAuthorizedNotifications() -> SignalProducer<Bool, Never> {
    SignalProducer { observer, lifetime in
      let task = Task { @MainActor in
        guard !Task.isCancelled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard !Task.isCancelled else { return }
        observer.send(value: settings.authorizationStatus == .authorized)
        observer.sendCompleted()
      }
      lifetime.observeEnded { task.cancel() }
    }
  }
}
