import Foundation

public struct SettingsDeleteOrRequestCellViewModel {
  public init() {}

  public func policyURL(languageCode: String? = Locale.current.languageCode) -> URL? {
    URL(string: "https://legal.kickstarter.com/policies/\(languageCode ?? "en")/?modal=take-control")
  }
}
