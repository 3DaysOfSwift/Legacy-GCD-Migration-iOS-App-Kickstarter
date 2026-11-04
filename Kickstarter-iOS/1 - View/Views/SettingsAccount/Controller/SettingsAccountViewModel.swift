import KsApi

import Observation
import UIKit

public typealias SettingsAccountData = (
  currency: Currency,
  email: String?,
  shouldHideEmailWarning: Bool,
  shouldHideEmailPasswordSection: Bool,
  isAppleConnectedAccount: Bool
)

@MainActor
@Observable
public final class SettingsAccountViewModel {
  public private(set) var data: SettingsAccountData?
  public private(set) var createPasswordFooter: (Bool, String?)?
  public var onFetchError: (() -> Void)?
  public var onSelect: ((SettingsAccountCellType, Currency) -> Void)?
  private let feature: SettingsFeature
  private let sleep: (TimeInterval) async throws -> Void
  private var task: Task<Void, Never>?
  private var revision = 0
  private var appeared = false

  public init(feature: SettingsFeature? = nil, sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
    if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
  }) {
    self.feature = feature ?? AppModel.shared.settingsFeature
    self.sleep = sleep
  }
  public func viewDidLoad() { self.load() }
  public func viewWillAppear() {
    if self.appeared { self.load() }
    self.appeared = true
  }
  public func didSelectRow(cellType: SettingsAccountCellType) {
    guard let currency = self.data?.currency else { return }
    self.onSelect?(cellType, currency)
  }
  private func load() {
    self.task?.cancel()
    self.revision += 1
    let revision = self.revision
    self.task = Task { [weak self, feature, sleep] in
      do {
        let user = try await feature.accountFields(sleep: sleep)
        try Task.checkCancellation()
        guard let self, self.revision == revision else { return }
        let apple = user.isAppleConnected == .some(true)
        let hideWarning = apple || (user.isEmailVerified == nil || user.isDeliverable == nil)
          || (user.isEmailVerified == true && user.isDeliverable == true)
        self.createPasswordFooter = (user.hasPassword != .some(true) && !apple, user.email)
        self.data = (currency: Currency(rawValue: user.chosenCurrency ?? Currency.USD.rawValue) ?? .USD,
                     email: user.email, shouldHideEmailWarning: hideWarning,
                     shouldHideEmailPasswordSection: user.hasPassword == .some(false) || apple,
                     isAppleConnectedAccount: apple)
      } catch {
        guard let self, !Task.isCancelled, !(error is CancellationError), self.revision == revision else { return }
        self.onFetchError?()
      }
    }
  }
  internal func waitForLoad() async { await self.task?.value }
}
