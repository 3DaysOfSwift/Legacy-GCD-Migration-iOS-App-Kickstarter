import KDS
import KsApi
import Prelude
import Observation
import UIKit

public enum BetaToolsRow: Int, CaseIterable {
  case debugConfigFeatureFlags
  case debugRemoteConfigFeatureFlags
  case debugPushNotifications
  case statsig
  case designSystem
  case colors
  case paginatedScrollView
  case richTextExample
  case changeEnvironment
  case changeLanguage

  public var cellStyle: UITableViewCell.CellStyle {
    switch self {
    case .debugConfigFeatureFlags, .debugRemoteConfigFeatureFlags, .debugPushNotifications,
         .statsig: return .default
    default: return .value1
    }
  }

  public var selectionStyle: UITableViewCell.SelectionStyle {
    switch self {
    case .changeEnvironment, .changeLanguage: return .none
    default: return .default
    }
  }

  public var titleText: String {
    switch self {
    case .debugConfigFeatureFlags: return "Config Feature Flags"
    case .debugRemoteConfigFeatureFlags: return "Remote Config and Statsig Feature Flags"
    case .debugPushNotifications: return "Debug Push Notifications"
    case .statsig: return "Statsig Debugger"
    case .designSystem: return "Design System"
    case .colors: return "Semantic Colors"
    case .paginatedScrollView: return "Paginated Scroll View"
    case .richTextExample: return "Rich Text Example"
    case .changeEnvironment: return "Change Environment"
    case .changeLanguage: return "Change Language"
    }
  }

  public var rightIconImageName: String? {
    switch self {
    case .debugConfigFeatureFlags, .debugRemoteConfigFeatureFlags,
         .debugPushNotifications, .statsig, .paginatedScrollView, .richTextExample, .designSystem,
         .colors: return "chevron-right"
    default: return nil
    }
  }

  public func detailText(from data: BetaToolsData) -> String? {
    switch self {
    case .changeEnvironment: return data.currentEnvironment
    case .changeLanguage: return data.currentLanguage
    default: return nil
    }
  }
}

public typealias BetaToolsData = (currentLanguage: String, currentEnvironment: String)

@MainActor
@Observable
public final class BetaToolsViewModel {
  public private(set) var data: BetaToolsData?
  public var onSelectRow: ((BetaToolsRow) -> Void)?
  public var onFeedback: ((Bool) -> Void)?
  public var onLanguage: ((Language) -> Void)?
  public var onEnvironment: ((EnvironmentType) -> Void)?
  public var onLogout: ((DiscoveryParams) -> Void)?
  private var originalLanguage: Language?
  private var originalEnvironment: EnvironmentType?
  private var lastLanguage: Language?
  private var lastEnvironment: EnvironmentType?
  private var selectedLanguage: Language?
  private var selectedEnvironment: EnvironmentType?

  public init() {}
  public func viewDidLoad() {
    self.originalLanguage = AppEnvironment.current.language
    self.originalEnvironment = AppEnvironment.current.apiService.serverConfig.environment
    self.selectedLanguage = self.originalLanguage
    self.selectedEnvironment = self.originalEnvironment
    self.updateData()
  }
  public func betaFeedbackButtonTapped(canSendMail: Bool) { self.onFeedback?(canSendMail) }
  public func didSelectBetaToolsRow(_ row: BetaToolsRow) { self.onSelectRow?(row) }
  public func setCurrentLanguage(_ language: Language) {
    guard self.lastLanguage != language else { return }
    self.lastLanguage = language
    guard let originalLanguage = self.originalLanguage, originalLanguage != language else { return }
    self.selectedLanguage = language
    self.updateData()
    self.onLanguage?(language)
  }
  public func setEnvironment(_ environment: EnvironmentType) {
    guard self.lastEnvironment != environment else { return }
    self.lastEnvironment = environment
    guard let originalEnvironment = self.originalEnvironment, originalEnvironment != environment else { return }
    self.selectedEnvironment = environment
    self.updateData()
    self.onEnvironment?(environment)
  }
  public func didUpdateEnvironment() {
    self.onLogout?(.defaults |> DiscoveryParams.lens.includePOTD .~ true |> DiscoveryParams.lens.sort .~ .magic)
  }
  private func updateData() {
    guard let language = self.selectedLanguage, let environment = self.selectedEnvironment else { return }
    self.data = (currentLanguage: language.displayString, currentEnvironment: environment.description)
  }
}
