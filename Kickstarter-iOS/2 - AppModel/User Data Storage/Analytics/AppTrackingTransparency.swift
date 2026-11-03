import AdSupport
import AppTrackingTransparency
import Foundation
import ReactiveSwift

public typealias AppTrackingAuthorization = ATTrackingManager.AuthorizationStatus

@MainActor
public protocol AppTrackingTransparencyType {
  var advertisingIdentifier: String? { get }
  var authorizationStatus: SignalProducer<AppTrackingAuthorization, Never> { get }
  func updateAdvertisingIdentifier()
  func requestAndSetAuthorizationStatus(_ completion: ((ATTrackingManager.AuthorizationStatus) -> Void)?)
  func shouldRequestAuthorizationStatus() -> Bool
}

public class AppTrackingTransparency: AppTrackingTransparencyType {
  public private(set) var advertisingIdentifier: String?

  public init() {
    self.updateAdvertisingIdentifier()
  }

  public func requestAndSetAuthorizationStatus(
    _ completion: ((ATTrackingManager.AuthorizationStatus) -> Void)? = nil
  ) {
    if let completion { self.authorizationCompletions.append(completion) }
    guard self.authorizationTask == nil else { return }
    self.authorizationTask = Task {
      let authStatus = await ATTrackingManager.requestTrackingAuthorization()
      self.authorizationStatusProperty.value = authStatus
      self.advertisingIdentifier = authStatus == .authorized
        ? ASIdentifierManager.shared().advertisingIdentifier.uuidString : nil
      let completions = self.authorizationCompletions
      self.authorizationCompletions.removeAll()
      self.authorizationTask = nil
      for completion in completions { completion(authStatus) }
    }
  }

  // Consent survives navigation: a system prompt cannot be retracted. The adapter
  // remains alive until its shared native request delivers every admitted completion.
  private var authorizationTask: Task<Void, Never>?
  private var authorizationCompletions: [(AppTrackingAuthorization) -> Void] = []

  public func shouldRequestAuthorizationStatus() -> Bool {
    ATTrackingManager.trackingAuthorizationStatus == .notDetermined
  }

  public func updateAdvertisingIdentifier() {
    let status = ATTrackingManager.trackingAuthorizationStatus
    self.authorizationStatusProperty.value = status

    switch status {
    case .authorized:
      self.advertisingIdentifier = ASIdentifierManager.shared().advertisingIdentifier.uuidString
    default:
      self.advertisingIdentifier = nil
    }
  }

  public var authorizationStatus: SignalProducer<AppTrackingAuthorization, Never> {
    self.authorizationStatusProperty.producer
      .replayLazily(upTo: 1)
      .skipRepeats()
  }

  // MARK: Subjects

  private let authorizationStatusProperty = MutableProperty<AppTrackingAuthorization>(.notDetermined)
}
