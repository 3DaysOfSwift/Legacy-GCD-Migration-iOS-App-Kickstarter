@testable import Kickstarter_iOS
import AppTrackingTransparency
import Foundation

@MainActor
class MockAppTrackingTransparency: AppTrackingTransparencyType {
  public private(set) var advertisingIdentifier: String?
  public var requestAndSetAuthorizationStatusFlag = false
  public var authorizationStatusValue: AppTrackingAuthorization = .notDetermined {
    didSet {
      guard oldValue != self.authorizationStatusValue else { return }
      for observer in Array(self.observers.values) { observer(self.authorizationStatusValue) }
    }
  }
  public var shouldRequestAuthStatus: Bool {
    get { self.authorizationStatusValue == .notDetermined }
    set { self.authorizationStatusValue = newValue ? .notDetermined : .authorized }
  }
  func updateAdvertisingIdentifier() {
    self.advertisingIdentifier = self.shouldRequestAuthStatus ? "advertisingIdentifer" : nil
  }
  func requestAndSetAuthorizationStatus(_ completion: ((ATTrackingManager.AuthorizationStatus) -> Void)? = nil) {
    self.authorizationStatusValue = .authorized
    self.advertisingIdentifier = self.requestAndSetAuthorizationStatusFlag ? "advertisingIdentifier" : nil
    completion?(.authorized)
  }
  func shouldRequestAuthorizationStatus() -> Bool { self.shouldRequestAuthStatus }
  private var observers: [UUID: @MainActor (AppTrackingAuthorization) -> Void] = [:]
  func observeAuthorizationStatus(_ observer: @escaping @MainActor (AppTrackingAuthorization) -> Void) -> UUID {
    let id = UUID()
    self.observers[id] = observer
    observer(self.authorizationStatusValue)
    return id
  }
  func removeAuthorizationObserver(_ id: UUID) { self.observers[id] = nil }
}
