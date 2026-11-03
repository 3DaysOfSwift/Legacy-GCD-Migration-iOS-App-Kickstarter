import FirebaseRemoteConfig
import Foundation

public protocol RemoteConfigClientType: AnyObject {
  @MainActor func fetchAndActivateAsync() async throws
  func activate(completion: (@Sendable (Bool, Error?) -> Void)?)
  func fetch(completionHandler: (@Sendable (RemoteConfigFetchStatus, Error?) -> Void)?)
  func fetchAndActivate(completionHandler: (@Sendable (RemoteConfigFetchAndActivateStatus, Error?) -> Void)?)
  func setDefaults(_ defaults: [String: NSObject]?)
  func addOnConfigUpdateListener(remoteConfigUpdateCompletion listener: @escaping @Sendable (
    RemoteConfigUpdate?,
    Error?
  ) -> Void) -> ConfigUpdateListenerRegistration
  func configValue(forKey key: String?) -> RemoteConfigValue
}

extension RemoteConfigClientType {
  /* Returns all features the app knows about */

  public func allFeatures() -> [RemoteConfigFeature] {
    return RemoteConfigFeature.allCases
  }

  public func isFeatureEnabled(featureKey: RemoteConfigFeature) -> Bool {
    self.configValue(forKey: featureKey.rawValue).boolValue == true
  }
}
