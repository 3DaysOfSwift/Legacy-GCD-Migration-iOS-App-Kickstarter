import FacebookLogin
import KsApi
import Observation

@MainActor
@Observable
public final class FindFriendsFacebookConnectCellViewModel {
  public private(set) var hideCloseButton = false
  public private(set) var isLoading = false
  public private(set) var title = ""
  public private(set) var subtitle = ""
  public private(set) var buttonTitle = ""
  public var onAttemptLogin: (() -> Void)?
  public var onDismiss: (() -> Void)?
  public var onConnected: (() -> Void)?
  public var onError: ((AlertError) -> Void)?
  private let settingsFeature: SettingsFeature
  private let sleep: (TimeInterval) async throws -> Void
  private var task: Task<Void, Never>?
  private var revision = 0

  public init(settingsFeature: SettingsFeature? = nil, sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
    if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
  }) {
    self.settingsFeature = settingsFeature ?? AppModel.shared.settingsFeature
    self.sleep = sleep
  }
  public func configureWith(source: FriendsSource) {
    self.hideCloseButton = source == .findFriends
    if let type = Self.connectionType(user: AppEnvironment.current.currentUser) {
      self.title = type.titleText
      self.subtitle = type.subtitleText
      self.buttonTitle = type.buttonText
    }
  }
  public func closeButtonTapped() { self.onDismiss?() }
  public func facebookConnectButtonTapped() { self.onAttemptLogin?() }
  public func facebookLoginFail(error: Error?) {
    guard let error = error as NSError? else { return }
    self.onError?(.facebookLoginAttemptFail(error: error))
  }
  public func facebookLoginSuccess(result: LoginManagerLoginResult) {
    self.task?.cancel()
    self.revision += 1
    let revision = self.revision
    let token = result.token?.tokenString ?? ""
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.isLoading = true
    self.task = Task { [weak self, settingsFeature, sleep] in
      do {
        _ = try await settingsFeature.updateAccount(.facebook(token))
        try Task.checkCancellation()
        guard self?.revision == revision else { return }
        self?.isLoading = false
        try await sleep(delay)
        try Task.checkCancellation()
        guard let self, self.revision == revision else { return }
        NotificationCenter.default.post(name: .ksr_userUpdated, object: nil)
        self.onConnected?()
      } catch {
        guard let self, !Task.isCancelled, !(error is CancellationError), self.revision == revision else { return }
        self.isLoading = false
        do { try await sleep(delay); try Task.checkCancellation() } catch { return }
        guard self.revision == revision else { return }
        let envelope = error as? ErrorEnvelope ?? .couldNotParseJSON
        switch envelope.ksrCode {
        case .FacebookInvalidAccessToken: self.onError?(.facebookTokenFail)
        case .FacebookConnectAccountTaken: self.onError?(.facebookConnectAccountTaken(envelope: envelope))
        case .FacebookConnectEmailTaken: self.onError?(.facebookConnectEmailTaken(envelope: envelope))
        default: self.onError?(.genericFacebookError(envelope: envelope))
        }
      }
    }
  }
  internal func waitForConnection() async { await self.task?.value }
}

extension FindFriendsFacebookConnectCellViewModel {
  nonisolated public static func showFacebookConnectionSection(for user: User?) -> Bool {
    guard let isFacebookConnected = user?.facebookConnected else {
      return true
    }

    let needsFreshFacebookToken = user?.needsFreshFacebookToken ?? false

    // Show section in "reconnect" state if facebook connected but requiring a new token
    return !isFacebookConnected || (
      isFacebookConnected
        && needsFreshFacebookToken
    )
  }

  private static func connectionType(user: User?) -> FacebookConnectionType? {
    guard let isFacebookConnected = user?.facebookConnected else {
      return .connect
    }

    let needsRefresh = user?.needsFreshFacebookToken ?? false

    if isFacebookConnected, needsRefresh {
      return .reconnect
    }

    return .connect
  }
}
