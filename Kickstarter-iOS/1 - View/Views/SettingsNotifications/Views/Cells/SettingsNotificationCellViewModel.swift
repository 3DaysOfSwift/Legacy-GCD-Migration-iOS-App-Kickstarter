import Foundation
import KsApi
import Observation

@MainActor
@Observable
public final class SettingsNotificationCellViewModel {
  public private(set) var emailEnabled: Bool?
  public private(set) var pushEnabled: Bool?
  public private(set) var cellType: SettingsNotificationCellType?
  public private(set) var projectCountText = ""
  public var onChange: (() -> Void)?
  public var onError: ((String) -> Void)?
  public var onUserUpdated: ((User) -> Void)?
  private let feature: SettingsFeature
  private let sleep: (TimeInterval) async throws -> Void
  private var user: User?
  private var initialEmail: Bool?
  private var initialPush: Bool?
  private var lastEmailTap: Bool?
  private var lastPushTap: Bool?
  private var revision = 0
  private var saves: [UUID: Task<Void, Never>] = [:]

  public init(feature: SettingsFeature? = nil, sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
    if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
  }) {
    self.feature = feature ?? AppModel.shared.settingsFeature
    self.sleep = sleep
  }

  public func configure(with value: SettingsNotificationCellValue) {
    self.cellType = value.cellType
    self.user = value.user
    if let attribute = Self.notificationFor(cellType: value.cellType, notificationType: .email),
       let enabled = value.user[keyPath: UserAttribute.notification(attribute).keyPath] {
      self.initialEmail = enabled
      self.emailEnabled = enabled
    }
    if let attribute = Self.notificationFor(cellType: value.cellType, notificationType: .push),
       let enabled = value.user[keyPath: UserAttribute.notification(attribute).keyPath] {
      self.initialPush = enabled
      self.pushEnabled = enabled
    }
    self.projectCountText = Format.wholeNumber(value.user.stats.backedProjectsCount ?? 0)
    self.onChange?()
  }

  public func didTapEmailNotificationsButton(selected: Bool) { self.toggle(.email, selected: selected) }
  public func didTapPushNotificationsButton(selected: Bool) { self.toggle(.push, selected: selected) }

  private func toggle(_ type: NotificationType, selected: Bool) {
    let enabled = !selected
    if type == .email { self.emailEnabled = enabled } else { self.pushEnabled = enabled }
    self.onChange?()
    let previousTap = type == .email ? self.lastEmailTap : self.lastPushTap
    if type == .email { self.lastEmailTap = enabled } else { self.lastPushTap = enabled }
    guard previousTap != enabled, let cellType = self.cellType, let user = self.user,
          let attribute = Self.notificationFor(cellType: cellType, notificationType: type) else { return }
    self.revision += 1
    let revision = self.revision
    let id = UUID()
    let feature = self.feature
    let sleep = self.sleep
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.saves[id] = Task { [weak self] in
      defer { self?.saves[id] = nil }
      let result: Result<User, Error>
      do { result = .success(try await feature.save([.init(.notification(attribute), enabled)], from: user)) }
      catch { result = .failure(error) }
      do { try await sleep(delay) } catch { return }
      guard let self, self.revision == revision else { return }
      switch result {
      case let .success(user): self.onUserUpdated?(user)
      case let .failure(error):
        guard !(error is CancellationError) else { return }
        self.onError?((error as? ErrorEnvelope)?.errorMessages.first ?? Strings.profile_settings_error())
        if let initialEmail = self.initialEmail { self.emailEnabled = initialEmail }
        if let initialPush = self.initialPush { self.pushEnabled = initialPush }
        self.onChange?()
      }
    }
  }

  internal func waitForSaves() async { for task in Array(self.saves.values) { await task.value } }
}

public enum NotificationType {
  case email
  case push
}

extension SettingsNotificationCellViewModel {
  public static func notificationFor(
    cellType: SettingsNotificationCellType,
    notificationType: NotificationType
  ) -> UserAttribute.Notification? {
    switch cellType {
    case .projectUpdates:
      return notificationType == .email
        ? UserAttribute.Notification.updates : UserAttribute.Notification.mobileUpdates
    case .pledgeActivity:
      return notificationType == .email
        ? UserAttribute.Notification.pledgeActivity : UserAttribute.Notification.mobilePledgeActivity
    case .newComments:
      return notificationType == .email
        ? UserAttribute.Notification.comments : UserAttribute.Notification.mobileComments
    case .newLikes:
      return notificationType == .email
        ? UserAttribute.Notification.postLikes : UserAttribute.Notification.mobilePostLikes
    case .creatorTips:
      return notificationType == .email
        ? UserAttribute.Notification.creatorTips : nil
    case .marketingUpdate:
      return notificationType == .email
        ? nil : UserAttribute.Notification.mobileMarketingUpdate
    case .messages:
      return notificationType == .email
        ? UserAttribute.Notification.messages : UserAttribute.Notification.mobileMessages
    case .newFollowers:
      return notificationType == .email
        ? UserAttribute.Notification.follower : UserAttribute.Notification.mobileFollower
    case .friendBacksProject:
      return notificationType == .email
        ? UserAttribute.Notification.friendActivity : UserAttribute.Notification.mobileFriendActivity
    case .commentReplyDigest:
      return notificationType == .email
        ? UserAttribute.Notification.commentReplies : nil
    default:
      return nil
    }
  }
}
