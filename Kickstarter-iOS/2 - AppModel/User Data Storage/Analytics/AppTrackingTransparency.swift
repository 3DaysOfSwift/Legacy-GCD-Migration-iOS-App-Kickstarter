import AdSupport
import AppTrackingTransparency
import Foundation

public typealias AppTrackingAuthorization = ATTrackingManager.AuthorizationStatus

@MainActor
public protocol AppTrackingTransparencyType {
  var advertisingIdentifier: String? { get }
  func observeAuthorizationStatus(_ observer: @escaping @MainActor (AppTrackingAuthorization) -> Void) -> UUID
  func removeAuthorizationObserver(_ id: UUID)
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
      self.setAuthorizationStatus(authStatus)
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
    self.setAuthorizationStatus(status)

    switch status {
    case .authorized:
      self.advertisingIdentifier = ASIdentifierManager.shared().advertisingIdentifier.uuidString
    default:
      self.advertisingIdentifier = nil
    }
  }

  private var authorizationStatus: AppTrackingAuthorization = .notDetermined
  private var authorizationObservers: [UUID: @MainActor (AppTrackingAuthorization) -> Void] = [:]

  public func observeAuthorizationStatus(_ observer: @escaping @MainActor (AppTrackingAuthorization) -> Void) -> UUID {
    let id = UUID()
    self.authorizationObservers[id] = observer
    observer(self.authorizationStatus)
    return id
  }

  public func removeAuthorizationObserver(_ id: UUID) {
    self.authorizationObservers[id] = nil
  }

  private func setAuthorizationStatus(_ status: AppTrackingAuthorization) {
    guard self.authorizationStatus != status else { return }
    self.authorizationStatus = status
    for observer in Array(self.authorizationObservers.values) { observer(status) }
  }
}
