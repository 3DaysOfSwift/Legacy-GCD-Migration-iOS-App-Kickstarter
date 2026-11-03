import Foundation

public protocol AppEnvironmentType {
  @MainActor static func logout()
}
