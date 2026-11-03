import Foundation
import ReactiveSwift
import UIKit
import UserNotifications

@MainActor
public protocol PushRegistrationType {
  static func register(for options: UNAuthorizationOptions) -> SignalProducer<Bool, Never>
  static func hasAuthorizedNotifications() -> SignalProducer<Bool, Never>
}
