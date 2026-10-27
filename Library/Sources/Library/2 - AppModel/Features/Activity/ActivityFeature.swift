import Foundation
import KsApi
import Prelude
import ReactiveSwift

@MainActor
public protocol ActivityProvider {
  func page(cursor: String?) async throws -> ActivityEnvelope
  func surveys() async throws -> [SurveyResponse]
}

@MainActor
public struct AsyncActivityProvider: ActivityProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func page(cursor: String?) async throws -> ActivityEnvelope { try await self.service
    .activityPage(cursor: cursor)
  }

  public func surveys() async throws -> [SurveyResponse] { try await self.service.unansweredSurveys() }
}

/// Owns the Activity tab's ordered, deduplicated history and survey requests.
/// Refresh retains accumulated history unless the first returned page is empty.
@MainActor
public final class ActivityFeature {
  public let sessionFeature: SessionFeature
  public private(set) var activities: [Activity] = []
  public private(set) var surveys: [SurveyResponse] = []
  public private(set) var error: Error?
  public private(set) var surveyError: Error?
  public private(set) var isLoading = false
  private let makeProvider: () -> any ActivityProvider
  private let sleep: (TimeInterval) async throws -> Void
  private var accountID: Int?
  private var generation: Int?
  private var cursor: String?
  private var pageItems: [Activity] = []
  private var request: (token: UUID, cursor: String?, task: Task<Void, Never>)?
  private var surveyRequest: (token: UUID, task: Task<Void, Never>)?
  private let activityPipe = Signal<[Activity], Never>.pipe()
  private let loadingPipe = Signal<Bool, Never>.pipe()
  private let surveyPipe = Signal<[SurveyResponse], Never>.pipe()
  public var activityValues: Signal<[Activity], Never> { self.activityPipe.output }
  public var loadingValues: Signal<Bool, Never> { self.loadingPipe.output }
  public var surveyValues: Signal<[SurveyResponse], Never> { self.surveyPipe.output }

  public init(
    sessionFeature: SessionFeature, makeProvider: @escaping () -> any ActivityProvider,
    sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
      if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    }
  ) {
    self.sessionFeature = sessionFeature
    self.makeProvider = makeProvider
    self.sleep = sleep
  }

  private func synchronizeAccount() {
    let id = self.sessionFeature.currentUser?.id
    let revision = self.sessionFeature.generation
    guard self.accountID != id || self.generation != revision else { return }
    self.reset()
    self.accountID = id
    self.generation = revision
  }

  public func reset() {
    self.request?.task.cancel()
    self.surveyRequest?.task.cancel()
    self.request = nil
    self.surveyRequest = nil
    self.activities = []
    self.pageItems = []
    self.surveys = []
    self.cursor = nil
    self.error = nil
    self.surveyError = nil
    if self.isLoading { self.isLoading = false; self.loadingPipe.input.send(value: false) }
  }

  public func refresh() async { await self.requestPage()?.value }
  public func loadNextPage() async { await self.requestPage(next: true)?.value }

  @discardableResult
  public func requestPage(next: Bool = false) -> Task<Void, Never>? {
    self.synchronizeAccount()
    guard self.accountID != nil else { return nil }
    if let request = self.request, next || request.cursor == nil { return request.task }
    guard !next || self.cursor != nil else { return nil }
    self.request?.task.cancel()
    let cursor = next ? self.cursor : nil
    if !next { self.pageItems = []; self.cursor = nil }
    let token = UUID()
    let userID = self.accountID
    let generation = self.sessionFeature.generation
    let provider = self.makeProvider()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.isLoading = true
    self.error = nil
    let task = Task { [weak self, sleep] in
      guard let self else { return }
      defer {
        if self.request?.token == token {
          self.request = nil
          self.isLoading = false
          self.loadingPipe.input.send(value: false)
        }
      }
      do {
        try Task.checkCancellation()
        guard self.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        let envelope = try await provider.page(cursor: cursor)
        try await sleep(delay)
        try Task.checkCancellation()
        guard self.request?.token == token,
              self.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        self.cursor = envelope.activities.isEmpty ? nil : envelope.urls.api.moreActivities
        self.pageItems += envelope.activities
        self.activities = self.pageItems.isEmpty ? [] : (self.activities + self.pageItems).distincts()
          .sorted { $0.id > $1.id }
        self.activityPipe.input.send(value: self.activities)
      } catch {
        guard !Task.isCancelled, !(error is CancellationError), self.request?.token == token,
              self.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        self.error = error
      }
    }
    self.request = (token, cursor, task)
    self.loadingPipe.input.send(value: true)
    return task
  }

  @discardableResult
  public func requestSurveys() -> Task<Void, Never>? {
    self.synchronizeAccount()
    guard let userID = self.accountID else { return nil }
    if let request = self.surveyRequest { return request.task }
    let generation = self.sessionFeature.generation
    let token = UUID()
    let provider = self.makeProvider()
    self.surveyError = nil
    let task = Task { [weak self] in
      guard let self else { return }
      defer { if self.surveyRequest?.token == token { self.surveyRequest = nil } }
      do {
        try Task.checkCancellation()
        guard self.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        let surveys = try await provider.surveys()
        try Task.checkCancellation()
        guard self.surveyRequest?.token == token,
              self.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        self.surveys = surveys
        self.surveyPipe.input.send(value: surveys)
      } catch {
        guard !Task.isCancelled, !(error is CancellationError), self.surveyRequest?.token == token,
              self.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        self.surveyError = error
      }
    }
    self.surveyRequest = (token, task)
    return task
  }
}
