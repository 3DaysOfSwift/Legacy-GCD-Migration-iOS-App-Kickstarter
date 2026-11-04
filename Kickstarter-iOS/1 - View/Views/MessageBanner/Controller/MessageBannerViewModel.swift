import Foundation
import Observation
import UIKit

public typealias MessageBannerConfiguration = (type: MessageBannerType, message: String)

@MainActor
@Observable
public final class MessageBannerViewModel {
  public var onConfiguration: ((MessageBannerConfiguration) -> Void)?
  public var onHidden: ((Bool) -> Void)?
  private let sleep: (TimeInterval) async throws -> Void
  private var hidden: Bool?
  private var voiceOverTask: Task<Void, Never>?
  private var standardTask: Task<Void, Never>?

  public init(sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
    try await Task.sleep(for: .seconds(seconds))
  }) {
    self.sleep = sleep
  }

  public func update(with configuration: MessageBannerConfiguration) { self.onConfiguration?(configuration) }
  public func bannerViewWillShow(_ show: Bool) { self.setHidden(!show) }

  public func bannerViewAnimationFinished(isHidden: Bool) {
    guard !isHidden else { return }
    let voiceOver = AppEnvironment.current.isVoiceOverRunning()
    if voiceOver { self.voiceOverTask?.cancel() } else { self.standardTask?.cancel() }
    let sleep = self.sleep
    let task = Task { [weak self] in
      do { try await sleep(voiceOver ? 10 : 4) } catch { return }
      guard !Task.isCancelled else { return }
      self?.setHidden(true)
    }
    if voiceOver { self.voiceOverTask = task } else { self.standardTask = task }
  }

  private func setHidden(_ value: Bool) {
    guard self.hidden != value else { return }
    self.hidden = value
    self.onHidden?(value)
  }

  internal func waitForDismissal(voiceOver: Bool) async {
    await (voiceOver ? self.voiceOverTask : self.standardTask)?.value
  }
}
