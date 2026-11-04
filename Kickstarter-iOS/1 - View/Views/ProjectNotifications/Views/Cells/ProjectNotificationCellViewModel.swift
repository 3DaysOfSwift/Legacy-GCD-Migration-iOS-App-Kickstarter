import Foundation
import KsApi
import Prelude

@MainActor
public final class ProjectNotificationCellViewModel {
  var onName: ((String) -> Void)?
  var onSwitch: ((Bool) -> Void)?
  var onError: ((String) -> Void)?
  private let feature: SettingsFeature
  private let sleep: (TimeInterval) async throws -> Void
  private var notification: ProjectNotification?
  private var presentation: Task<Void, Never>?
  private var revision = UUID()
  private var lastSwitch: Bool?

  public init(feature: SettingsFeature? = nil, sleep: @escaping (TimeInterval) async throws -> Void = { delay in
    if delay.isInfinite { try await Task.sleep(nanoseconds: UInt64.max) }
    else if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
  }) {
    self.feature = feature ?? AppModel.shared.settingsFeature
    self.sleep = sleep
  }

  private func publishSwitch(_ on: Bool) {
    guard self.lastSwitch != on else { return }
    self.lastSwitch = on
    self.onSwitch?(on)
  }

  public func configureWith(notification: ProjectNotification) {
    self.revision = UUID()
    self.presentation?.cancel()
    let current = self.feature.cachedProjectNotification(notification)
    self.notification = current
    self.onName?(current.project.name)
    self.publishSwitch(current.email && current.mobile)
  }

  public func notificationTapped(on: Bool) {
    guard let source = self.notification else { return }
    self.publishSwitch(on)
    let edited = source |> ProjectNotification.lens.email .~ on |> ProjectNotification.lens.mobile .~ on
    self.presentation?.cancel()
    let revision = UUID()
    self.revision = revision
    let session = self.feature.sessionFeature
    let userID = session.currentUser?.id
    let generation = session.generation
    guard let command = try? self.feature.requestProjectNotificationSave(edited) else { return }
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let sleep = self.sleep
    self.presentation = Task { [weak self] in
      let result = await command.result
      do { try await sleep(delay); try Task.checkCancellation() } catch { return }
      guard let self, self.revision == revision,
            session.isCurrent(userID: userID, generation: generation) else { return }
      if case let .failure(error) = result, !(error is CancellationError) {
        let confirmed = self.feature.cachedProjectNotification(source)
        self.onError?((error as? ErrorEnvelope)?.errorMessages.first ?? Strings.profile_settings_error())
        self.publishSwitch(confirmed.email && confirmed.mobile)
      }
    }
  }

  func waitForPresentation() async { await self.presentation?.value }
}
