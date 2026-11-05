@testable import Kickstarter_iOS
import Foundation
import UserNotifications

@MainActor
public struct MockPushRegistration: PushRegistrationType {
  static var registerValue: Bool?
  static var authorizedValue: Bool?
  public static func register(for _: UNAuthorizationOptions, completion: @escaping @MainActor (Bool) -> Void) -> Task<Void, Never>? {
    if let value = self.registerValue { completion(value) }
    return nil
  }
  public static func hasAuthorizedNotifications(completion: @escaping @MainActor (Bool) -> Void) -> Task<Void, Never>? {
    if let value = self.authorizedValue { completion(value) }
    return nil
  }
}
