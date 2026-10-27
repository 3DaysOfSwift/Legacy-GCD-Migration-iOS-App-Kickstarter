import Experimentation
import Foundation
import KsApi
import ReactiveSwift

/// The API substitution boundary; one instance captures the service for a whole load.
@MainActor
public protocol ProjectDetailsProvider {
  func enroll(token: String, param: Param) async throws
  func project(param: Param, richText: Bool) async throws -> Project.ProjectPamphletData
  func backing(id: Int) async throws -> ProjectAndBackingEnvelope
  func rewards(projectID: Int) async throws -> [Reward]
  func base(param: Param) async throws -> Project
  func extras(param: Param, richText: Bool) async throws -> ProjectPageExtraProperties
}

@MainActor
public struct AsyncProjectDetailsProvider: ProjectDetailsProvider {
  private let service: any ServiceType

  public init(service: any ServiceType) { self.service = service }
  public func enroll(token: String, param: Param) async throws {
    try await self.service.enrollProjectSecretReward(token: token, param: param)
  }

  public func project(param: Param, richText: Bool) async throws -> Project.ProjectPamphletData {
    try await self.service.projectDetails(param: param, includeStoryRichText: richText)
  }

  public func backing(id: Int) async throws -> ProjectAndBackingEnvelope {
    try await self.service.projectDetailsBacking(id: id)
  }

  public func rewards(projectID: Int) async throws -> [Reward] {
    try await self.service.projectDetailsRewards(projectID: projectID)
  }

  public func base(param: Param) async throws -> Project {
    try await self.service.projectDetailsBase(param: param)
  }

  public func extras(param: Param, richText: Bool) async throws -> ProjectPageExtraProperties {
    try await self.service.projectDetailsExtras(param: param, includeStoryRichText: richText)
  }
}

/// Owns complete project-detail loading, including enrollment, backing and rewards.
/// Routes are independent (a related project may open above an existing page).
/// Within a route, equivalent loads share work; refresh after a mutation replaces
/// it. Cancellation invalidates publication even if a provider completes late.
@MainActor
public final class ProjectDetailsFeature {
  public struct Snapshot {
    public fileprivate(set) var project: Project?
    public fileprivate(set) var isLoading = false
    public fileprivate(set) var error: ErrorEnvelope?
  }

  private struct Identity: Equatable {
    let param: Param
    let token: String?
    let userID: Int?
    let fast: Bool
    let richText: Bool
  }

  private final class Page {
    var snapshot = Snapshot()
    var request: (id: UUID, identity: Identity, task: Task<Void, Never>)?
  }

  private enum ProjectPart {
    case base(Project)
    case extras(ProjectPageExtraProperties)
  }

  private var pages: [UUID: Page] = [:]
  private let makeProvider: @MainActor () -> any ProjectDetailsProvider
  private let useFastLoading: @MainActor () -> Bool
  private let includeRichText: @MainActor () -> Bool
  private let sleep: @MainActor (TimeInterval) async throws -> Void
  private let completionPipe = Signal<(UUID, Result<Project, ErrorEnvelope>), Never>.pipe()
  private let loadingPipe = Signal<(UUID, Bool), Never>.pipe()
  public var completions: Signal<(UUID, Result<Project, ErrorEnvelope>), Never> { self.completionPipe.output }
  public var loading: Signal<(UUID, Bool), Never> { self.loadingPipe.output }

  public init(
    makeProvider: @escaping @MainActor () -> any ProjectDetailsProvider,
    useFastLoading: @escaping @MainActor () -> Bool = {
      InstantPledgeButtonExperiment().boolValue(forKey: .instant_pledge_enabled) == true
    },
    includeRichText: @escaping @MainActor () -> Bool = { featureProjectStoryRichTextEnabled() },
    sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { seconds in
      if seconds.isInfinite { try await Task.sleep(nanoseconds: UInt64.max) }
      else if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
      try Task.checkCancellation()
    }
  ) {
    self.makeProvider = makeProvider
    self.useFastLoading = useFastLoading
    self.includeRichText = includeRichText
    self.sleep = sleep
  }

  public func snapshot(for route: UUID) -> Snapshot { self.pages[route]?.snapshot ?? Snapshot() }

  public func load(route: UUID, param: Param, secretRewardToken: String? = nil, force: Bool = false) async {
    guard !Task.isCancelled else { return }
    await self.requestLoad(route: route, param: param, secretRewardToken: secretRewardToken, force: force)
      .value
  }

  @discardableResult
  public func requestLoad(
    route: UUID, param: Param, secretRewardToken: String? = nil, force: Bool = false
  ) -> Task<Void, Never> {
    let identity = Identity(
      param: param, token: secretRewardToken, userID: AppEnvironment.current.currentUser?.id,
      fast: self.useFastLoading(), richText: self.includeRichText()
    )
    let page = self.pages[route] ?? Page()
    self.pages[route] = page
    if !force, let request = page.request, request.identity == identity { return request.task }
    page.request?.task.cancel()
    let requestID = UUID()
    let provider = self.makeProvider()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let sleep = self.sleep
    page.snapshot.isLoading = true
    page.snapshot.error = nil
    let task = Task { [weak self] in
      defer {
        if let self, self.pages[route]?.request?.id == requestID {
          page.request = nil
          page.snapshot.isLoading = false
          self.loadingPipe.input.send(value: (route, false))
        }
      }
      do {
        try Self.checkSession(identity.userID)
        // Keep enrollment before reads, including its existing configured delay.
        if identity.userID != nil, let token = identity.token, !token.isEmpty {
          try await provider.enroll(token: token, param: param)
          try await sleep(delay)
          try Self.checkSession(identity.userID)
        }
        let project: Project
        if identity.fast {
          // Observe whichever dependency finishes first, so either failure
          // cancels its sibling rather than waiting in a fixed await order.
          project = try await withThrowingTaskGroup(of: ProjectPart.self) { group in
            group.addTask { .base(try await provider.base(param: param)) }
            group.addTask { .extras(try await provider.extras(param: param, richText: identity.richText)) }
            var base: Project?
            var extras: ProjectPageExtraProperties?
            for try await part in group {
              switch part {
              case let .base(project): base = project
              case let .extras(properties): extras = properties
              }
            }
            guard let base, let extras else { throw ErrorEnvelope.couldNotParseJSON }
            return extras.addExtraProperties(toProject: base)
          }
        } else {
          let pamphlet = try await provider.project(param: param, richText: identity.richText)
          try Self.checkSession(identity.userID)
          var loaded = pamphlet.project
          if let backingID = pamphlet.backingId {
            let envelope = try await provider.backing(id: backingID)
            try Self.checkSession(identity.userID)
            loaded.personalization.backing = envelope.backing
            loaded.personalization.isBacking = true
          }
          let rewards = try await provider.rewards(projectID: loaded.id)
          try Self.checkSession(identity.userID)
          // Preserve the synthetic no-reward entry and shipping-rule data.
          loaded.rewardData.rewards = Array(loaded.rewardData.rewards.prefix(1)) + rewards
          project = loaded
        }
        try await sleep(delay)
        try Self.checkSession(identity.userID)
        guard let self, self.pages[route]?.request?.id == requestID else { return }
        page.snapshot.project = project
        self.completionPipe.input.send(value: (route, .success(project)))
      } catch is CancellationError {
        // Cancellation is not a product failure and never publishes stale data.
      } catch {
        guard !Task.isCancelled, identity.userID == AppEnvironment.current.currentUser?.id,
              let self, self.pages[route]?.request?.id == requestID else { return }
        let failure = (error as? ErrorEnvelope) ?? ErrorEnvelope.couldNotParseJSON
        page.snapshot.error = failure
        self.completionPipe.input.send(value: (route, .failure(failure)))
      }
    }
    page.request = (requestID, identity, task)
    self.loadingPipe.input.send(value: (route, true))
    return task
  }

  public func cancel(route: UUID) {
    guard let page = self.pages[route] else { return }
    let task = page.request?.task
    page.request = nil
    page.snapshot.isLoading = false
    task?.cancel()
    self.loadingPipe.input.send(value: (route, false))
  }

  public func release(route: UUID) {
    self.cancel(route: route)
    self.pages.removeValue(forKey: route)
  }

  private static func checkSession(_ userID: Int?) throws {
    try Task.checkCancellation()
    guard userID == AppEnvironment.current.currentUser?.id else { throw CancellationError() }
  }
}
