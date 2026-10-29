import Foundation
import UIKit
import AppTrackingTransparency
import UserNotifications
import KsApi
import Prelude
import ReactiveSwift

@MainActor
public protocol AppLifecycleProvider {
  func configuration() async throws -> Config
  func register(token: String) async throws
  func recommendations() async throws -> Int
  func categories() async throws -> RootCategoriesEnvelope
  func survey(id: Int) async throws -> SurveyResponse
  func project(param: Param) async throws -> Project
  func update(id: Int, project: Param) async throws -> Update
  func replies(id: String) async throws -> CommentRepliesEnvelope
}

@MainActor
public struct AsyncAppLifecycleProvider: AppLifecycleProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func configuration() async throws -> Config {
    try await self.service.applicationConfiguration()
  }
  public func register(token: String) async throws {
    try await self.service.registerApplicationPushToken(token)
  }
  public func recommendations() async throws -> Int {
    let params =
      DiscoveryParams.defaults
      |> DiscoveryParams.lens.recommended .~ true
      |> DiscoveryParams.lens.state .~ .live
      |> DiscoveryParams.lens.perPage .~ 1
    return try await self.service.discoveryPage(params: params).stats.count
  }
  public func categories() async throws -> RootCategoriesEnvelope {
    try await self.service.fetchSearchCategories()
  }
  public func survey(id: Int) async throws -> SurveyResponse {
    try await self.service.applicationSurvey(id: id)
  }
  public func project(param: Param) async throws -> Project {
    try await self.service.discussionProject(param: param)
  }
  public func update(id: Int, project: Param) async throws -> Update {
    try await self.service.projectUpdate(id: id, project: project)
  }
  public func replies(id: String) async throws -> CommentRepliesEnvelope {
    try await self.service.discussionReplies(id: id, cursor: nil)
  }
}

/// Owns startup reads, ordered push registrations and complete deep-link loads.
/// UIKit remains a renderer of resolved destinations; a partial project/update/
/// reply chain never escapes this owner. Settings and messages retain their stores.
@MainActor
public final class AppLifecycleFeature {
  public let sessionFeature: SessionFeature
  public let settingsFeature: SettingsFeature
  public let messagingFeature: MessagingFeature
  public struct ProjectDestination {
    public let project: Project
    public let subpage: Navigation.Project
    public let refInfo: RefInfo?
    public let secretRewardToken: String?
    public let update: Update?
    public let replies: CommentRepliesEnvelope?
  }
  public enum Destination {
    case discovery(DiscoveryParams?)
    case project(ProjectDestination)
    case survey(String)
    case message(MessageThread)
  }
  private struct Session: Equatable {
    let userID: Int?
    let generation: Int
  }
  private struct Pending<Value> {
    let id: UUID
    let session: Session
    let task: Task<Value, Error>
  }
  private let makeReachabilityMonitor: () -> (any ReachabilityMonitoring)?
  private var reachabilityMonitor: (any ReachabilityMonitoring)?
  private var connectivityTask: Task<Void, Never>?
  private var connectivityStarted = false
  private let connectivityState = MutableProperty<Reachability>(.none)

  public var connectivity: Reachability {
    self.startConnectivity()
    return self.connectivityState.value
  }
  public var connectivityProducer: SignalProducer<Reachability, Never> {
    self.startConnectivity()
    return self.connectivityState.producer
  }
  private func startConnectivity() {
    guard !self.connectivityStarted else { return }
    self.connectivityStarted = true
    guard let monitor = self.makeReachabilityMonitor() else { return }
    self.reachabilityMonitor = monitor
    self.connectivityState.value = monitor.initial
    let updates = monitor.updates
    self.connectivityTask = Task { [weak self] in
      for await value in updates {
        guard !Task.isCancelled, let self else { return }
        self.connectivityState.value = value
      }
    }
  }
  // Connectivity is application-scoped, so account reset does not stop it.
  deinit { self.connectivityTask?.cancel() }

  private var remoteConfigurationRequest: (client: ObjectIdentifier, id: UUID, task: Task<Void, Error>)?
  private var notificationRequest: (options: UInt, id: UUID, task: Task<Bool, Never>)?
  private var trackingRequest: Task<UInt, Never>?
  private let authorizeNotifications: (UNAuthorizationOptions) async -> Bool
  private let registerNotifications: () -> Void
  private let readNotificationStatus: () async -> UNAuthorizationStatus
  private let authorizeTracking: () async -> UInt
  private let makeProvider: () -> any AppLifecycleProvider
  private let resolveRedirect: (URL) async throws -> URL?
  private var redirects: [UUID: (url: URL, request: Pending<URL?>)] = [:]
  private var redirectVersions: [UUID: UUID] = [:]
  private var redirectTasks: [UUID: Task<URL?, Error>] = [:]
  private let sleep: (TimeInterval) async throws -> Void
  private var config: Pending<Config>?
  private var recommendations: (userID: Int?, request: Pending<Bool>)?
  private var destinations: [UUID: (navigation: Navigation, request: Pending<Destination?>)] = [:]
  private var pushTail: (token: String, request: Pending<String>)?
  private var configTasks: [UUID: Task<Config, Error>] = [:]
  private var recommendationTasks: [UUID: Task<Bool, Error>] = [:]
  private var destinationTasks: [UUID: Task<Destination?, Error>] = [:]
  private var pushTasks: [UUID: Task<String, Error>] = [:]
  private var observers: [UUID: Task<Void, Never>] = [:]

  public init(
    sessionFeature: SessionFeature, settingsFeature: SettingsFeature,
    messagingFeature: MessagingFeature, makeProvider: @escaping () -> any AppLifecycleProvider,
    makeReachabilityMonitor: @escaping () -> (any ReachabilityMonitoring)? = { nil },
    authorizeNotifications: @escaping (UNAuthorizationOptions) async -> Bool = { options in
      (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
    },
    registerNotifications: @escaping () -> Void = { UIApplication.shared.registerForRemoteNotifications() },
    readNotificationStatus: @escaping () async -> UNAuthorizationStatus = {
      await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    },
    authorizeTracking: @escaping () async -> UInt = {
      await withCheckedContinuation { continuation in
        AppEnvironment.current.appTrackingTransparency.requestAndSetAuthorizationStatus { status in
          continuation.resume(returning: status.rawValue)
        }
      }
    },
    resolveRedirect: @escaping (URL) async throws -> URL? = { try await FirstRedirectResolver.resolve($0) },
    sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
      if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    }
  ) {
    self.makeReachabilityMonitor = makeReachabilityMonitor
    self.sessionFeature = sessionFeature
    self.settingsFeature = settingsFeature
    self.messagingFeature = messagingFeature
    self.makeProvider = makeProvider
    self.sleep = sleep
    self.resolveRedirect = resolveRedirect
    self.authorizeNotifications = authorizeNotifications
    self.registerNotifications = registerNotifications
    self.readNotificationStatus = readNotificationStatus
    self.authorizeTracking = authorizeTracking
  }
  private var session: Session {
    Session(userID: self.sessionFeature.currentUser?.id, generation: self.sessionFeature.generation)
  }
  private func requireCurrent(_ session: Session) throws {
    try Task.checkCancellation()
    guard self.session == session else { throw CancellationError() }
  }

  /// Admitted system prompts settle even if their UI observer goes away. Equal
  /// pending requests share; distinct option sets serialize behind the prompt.
  public func notificationAuthorization(options: UNAuthorizationOptions) async -> Bool {
    if let pending = self.notificationRequest, pending.options == options.rawValue {
      return await pending.task.value
    }
    let previous = self.notificationRequest?.task
    let id = UUID()
    let task = Task { [authorizeNotifications, registerNotifications] in
      if let previous { _ = await previous.value }
      let granted = await authorizeNotifications(options)
      if granted { registerNotifications() }
      return granted
    }
    self.notificationRequest = (options.rawValue, id, task)
    let value = await task.value
    if self.notificationRequest?.id == id { self.notificationRequest = nil }
    return value
  }

  public func notificationStatus() async -> UNAuthorizationStatus {
    await self.readNotificationStatus()
  }

  public func trackingAuthorization() async -> ATTrackingManager.AuthorizationStatus {
    if let task = self.trackingRequest {
      return ATTrackingManager.AuthorizationStatus(rawValue: await task.value) ?? .notDetermined
    }
    let task = Task { [authorizeTracking] in await authorizeTracking() }
    self.trackingRequest = task
    let value = await task.value
    self.trackingRequest = nil
    return ATTrackingManager.AuthorizationStatus(rawValue: value) ?? .notDetermined
  }

  @discardableResult public func requestRemoteConfiguration(
    client: AnyObject, activate: @escaping @MainActor () async throws -> Void
  ) -> Task<Void, Error> {
    let clientID = ObjectIdentifier(client)
    if let pending = self.remoteConfigurationRequest, pending.client == clientID { return pending.task }
    self.remoteConfigurationRequest?.task.cancel()
    let id = UUID()
    let task = Task { [self] in
      defer { if self.remoteConfigurationRequest?.id == id { self.remoteConfigurationRequest = nil } }
      try Task.checkCancellation()
      try await activate()
      try Task.checkCancellation()
      guard self.remoteConfigurationRequest?.id == id else { throw CancellationError() }
    }
    self.remoteConfigurationRequest = (clientID, id, task)
    return task
  }

  public func configuration() async throws -> Config {
    try Task.checkCancellation()
    let value = try await self.requestConfiguration().value
    try Task.checkCancellation()
    return value
  }
  @discardableResult public func requestConfiguration() -> Task<Config, Error> {
    let session = self.session
    if let config = self.config, config.session == session { return config.task }
    self.config?.task.cancel()
    let id = UUID()
    let provider = self.makeProvider()
    let task = Task { [self] in
      defer {
        self.configTasks[id] = nil
        if self.config?.id == id { self.config = nil }
      }
      try self.requireCurrent(session)
      let value = try await provider.configuration()
      try self.requireCurrent(session)
      return value
    }
    self.config = Pending(id: id, session: session, task: task)
    self.configTasks[id] = task
    return task
  }

  public func hasRecommendations(for user: User?) async throws -> Bool {
    try Task.checkCancellation()
    let session = self.session
    if let pending = self.recommendations, pending.userID == user?.id,
      pending.request.session == session
    {
      let value = try await pending.request.task.value
      try self.requireCurrent(session)
      return value
    }
    self.recommendations?.request.task.cancel()
    let id = UUID()
    let provider = self.makeProvider()
    let task = Task { [self] in
      defer {
        self.recommendationTasks[id] = nil
        if self.recommendations?.request.id == id { self.recommendations = nil }
      }
      try self.requireCurrent(session)
      guard user != nil else { return false }
      do {
        let count = try await provider.recommendations()
        try self.requireCurrent(session)
        return count > 0
      } catch {
        try self.requireCurrent(session)
        if error is CancellationError { throw error }
        return false  // Original shortcut fallback on failure.
      }
    }
    self.recommendations = (user?.id, Pending(id: id, session: session, task: task))
    self.recommendationTasks[id] = task
    let value = try await task.value
    try self.requireCurrent(session)
    return value
  }

  /// The debounce precedes admission. Distinct admitted tokens are serialized;
  /// abandoning observation cannot retract a server-accepted registration.
  @discardableResult public func requestPushRegistration(token: String) -> Task<String, Error> {
    let session = self.session
    if let tail = self.pushTail, tail.token == token, tail.request.session == session {
      return tail.request.task
    }
    let previous = self.pushTail?.request.task
    let id = UUID()
    let provider = self.makeProvider()
    let task = Task { [self] in
      defer {
        self.pushTasks[id] = nil
        if self.pushTail?.request.id == id { self.pushTail = nil }
      }
      if let previous { _ = await previous.result }
      try self.requireCurrent(session)
      try await provider.register(token: token)
      try self.requireCurrent(session)
      return token
    }
    self.pushTail = (token, Pending(id: id, session: session, task: task))
    self.pushTasks[id] = task
    return task
  }

  /// One replaceable email-link read per navigation route. URL is Sendable;
  /// the session and operation identity are checked again after every waiter resumes.
  public func firstRedirect(_ url: URL, route: UUID) async throws -> URL? {
    try Task.checkCancellation()
    let session = self.session
    let pending: Pending<URL?>
    if let current = self.redirects[route], current.url == url, current.request.session == session {
      pending = current.request
    } else {
      self.release(route: route)
      let id = UUID()
      let task = Task { [self] in
        defer {
          self.redirectTasks[id] = nil
          if self.redirects[route]?.request.id == id { self.redirects[route] = nil }
        }
        try self.requireCurrent(session)
        let value = try await self.resolveRedirect(url)
        try self.requireCurrent(session)
        guard self.redirectVersions[route] == id else { throw CancellationError() }
        return value
      }
      pending = Pending(id: id, session: session, task: task)
      self.redirects[route] = (url, pending)
      self.redirectVersions[route] = id
      self.redirectTasks[id] = task
    }
    let value = try await pending.task.value
    try self.requireCurrent(session)
    guard self.redirectVersions[route] == pending.id else { throw CancellationError() }
    return value
  }

  public func resolve(_ navigation: Navigation, route: UUID) async throws -> Destination? {
    try Task.checkCancellation()
    let result = try await self.requestDestination(navigation, route: route).value
    try Task.checkCancellation()
    return result
  }
  @discardableResult public func requestDestination(_ navigation: Navigation, route: UUID) -> Task<
    Destination?, Error
  > {
    let session = self.session
    if let pending = self.destinations[route], pending.navigation == navigation,
      pending.request.session == session
    {
      return pending.request.task
    }
    self.release(route: route)
    let id = UUID()
    let provider = self.makeProvider()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let task = Task { [self] in
      defer {
        self.destinationTasks[id] = nil
        if self.destinations[route]?.request.id == id { self.destinations[route] = nil }
      }
      try self.requireCurrent(session)
      let destination: Destination?
      do {
        destination = try await self.load(
          navigation, provider: provider, session: session, delay: delay)
      } catch {
        try self.requireCurrent(session)
        throw error
      }
      try self.requireCurrent(session)
      guard self.destinations[route]?.request.id == id else { throw CancellationError() }
      return destination
    }
    self.destinations[route] = (navigation, Pending(id: id, session: session, task: task))
    self.destinationTasks[id] = task
    return task
  }

  private func load(
    _ navigation: Navigation, provider: any AppLifecycleProvider, session: Session,
    delay: TimeInterval
  ) async throws -> Destination? {
    switch navigation {
    case .tab(.discovery(let rawParams)):
      guard let rawParams, let params = DiscoveryParams.decodeJSONDictionary(rawParams) else {
        return .discovery(nil)
      }
      let (category, subcategory) = deepLinkCategories(rawParams: rawParams)
      guard let category else { return .discovery(params) }
      let envelope = try await provider.categories()
      try self.requireCurrent(session)
      let matched = findCategoryFromRootCategories(
        envelope: envelope, categoryParam: category, subcategoryParam: subcategory)
      try await self.sleep(delay)
      return .discovery(params |> DiscoveryParams.lens.category .~ matched)
    case .user(_, .survey(let id)):
      let survey = try await provider.survey(id: id)
      return .survey(survey.urls.web.survey)
    case .messages(let id):
      return try await self.messagingFeature.thread(id: id).map { .message($0.messageThread) }
    case .project(_, .pledgeManagerWebview(let url), _, _):
      return .survey(url)
    case .project(let param, let subpage, let refInfo, let token):
      let project = try await provider.project(param: param)
      try self.requireCurrent(session)
      // Prelaunch projects only expose their root, as before.
      guard project.displayPrelaunch != true || subpage == .root else { return nil }
      var update: Update?
      var replies: CommentRepliesEnvelope?
      switch subpage {
      case .commentThread(let id?, _):
        replies = try await provider.replies(id: id)
      case .update(let id, let child):
        update = try await provider.update(id: id, project: .id(project.id))
        try self.requireCurrent(session)
        if case .commentThread(let commentID?, _) = child {
          replies = try await provider.replies(id: commentID)
        }
      default: break
      }
      return .project(
        ProjectDestination(
          project: project, subpage: subpage, refInfo: refInfo, secretRewardToken: token,
          update: update, replies: replies))
    default: return nil  // Synchronous destinations still invalidate an earlier async link.
    }
  }

  public func release(route: UUID) {
    self.destinations.removeValue(forKey: route)?.request.task.cancel()
    self.redirects.removeValue(forKey: route)?.request.task.cancel()
    self.redirectVersions[route] = nil
  }
  public func reset() {
    self.config?.task.cancel()
    self.recommendations?.request.task.cancel()
    for route in Set(self.destinations.keys).union(self.redirectVersions.keys) { self.release(route: route) }
    for task in self.observers.values { task.cancel() }
  }
  public func waitForOperations() async {
    while !self.configTasks.isEmpty || !self.recommendationTasks.isEmpty
      || !self.redirectTasks.isEmpty || !self.destinationTasks.isEmpty || !self.pushTasks.isEmpty || !self.observers.isEmpty
    {
      for task in Array(self.configTasks.values) { _ = await task.result }
      for task in Array(self.recommendationTasks.values) { _ = await task.result }
      for task in Array(self.redirectTasks.values) { _ = await task.result }
      for task in Array(self.destinationTasks.values) { _ = await task.result }
      for task in Array(self.pushTasks.values) { _ = await task.result }
      for task in Array(self.observers.values) { await task.value }
    }
  }

  /// Output adapter only. Tasks above own sharing, cancellation and ordering.
  /// Disposing one observer leaves shared reads and admitted writes intact.
  public func result<Value>(_ operation: @escaping @MainActor () async throws -> Value)
    -> SignalProducer<Value, ErrorEnvelope>
  {
    let session = self.session
    return SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        let id = UUID()
        let task = Task { [self] in
          defer { self.observers[id] = nil }
          do {
            try self.requireCurrent(session)
            let value = try await operation()
            try self.requireCurrent(session)
            observer.send(value: value)
            observer.sendCompleted()
          } catch {
            guard !Task.isCancelled, !(error is CancellationError), self.session == session else {
              observer.sendInterrupted()
              return
            }
            observer.send(error: (error as? ErrorEnvelope) ?? .couldNotParseJSON)
          }
        }
        self.observers[id] = task
        lifetime.observeEnded { task.cancel() }
      }
    }
  }
}

/// The SDK requires a delegate to stop redirects. It has no mutable state or UI
/// callbacks; native URLSession async transport owns completion and cancellation.
public final class FirstRedirectResolver: NSObject, URLSessionTaskDelegate {
  public static func resolve(_ url: URL) async throws -> URL? {
    let session = URLSession(configuration: .default)
    defer { session.invalidateAndCancel() }
    let (_, response) = try await session.data(for: URLRequest(url: url), delegate: FirstRedirectResolver())
    try Task.checkCancellation()
    return self.destination(in: response)
  }
  static func destination(in response: URLResponse) -> URL? {
    guard let response = response as? HTTPURLResponse,
      [301, 302, 303, 307, 308].contains(response.statusCode),
      let location = response.value(forHTTPHeaderField: "Location"), !location.isEmpty,
      let base = response.url else { return nil }
    return URL(string: location, relativeTo: base)?.absoluteURL
  }
  public func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
