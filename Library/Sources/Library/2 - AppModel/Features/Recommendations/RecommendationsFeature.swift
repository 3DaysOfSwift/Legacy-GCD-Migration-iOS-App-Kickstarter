import Foundation
import KsApi
import Prelude
import ReactiveSwift

@MainActor
public protocol RecommendationsProvider {
  func projects(parameters: DiscoveryParams) async throws -> [Project]
  func category(id: String) async throws -> KsApi.Category
}

@MainActor
public struct AsyncRecommendationsProvider: RecommendationsProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func projects(parameters: DiscoveryParams) async throws -> [Project] {
    try await self.service.discoveryPage(params: parameters).projects
  }
  public func category(id: String) async throws -> KsApi.Category {
    try await self.service.recommendationCategory(id: id)
  }
}

/// Owns onboarding curation and post-backing alternatives. Each screen has its
/// own route; replacing or releasing a route makes its old responses obsolete.
@MainActor
public final class RecommendationsFeature {
  public enum Request: Equatable {
    case curated([KsApi.Category])
    case afterBacking(Project)
  }
  public struct Selection {
    public let projects: [Project]
    public let category: KsApi.Category?
  }
  private struct Session: Equatable {
    let userID: Int?
    let generation: Int
  }
  private struct Pending {
    let id: UUID
    let request: Request
    let session: Session
    let task: Task<Void, Never>
  }
  public let settingsFeature: SettingsFeature
  public let sessionFeature: SessionFeature
  private let makeProvider: () -> any RecommendationsProvider
  private let sleep: (TimeInterval) async throws -> Void
  private var pending: [UUID: Pending] = [:]
  private var operations: [UUID: Task<Void, Never>] = [:]
  private let selectionPipe = Signal<(UUID, Selection), Never>.pipe()
  public var selections: Signal<(UUID, Selection), Never> { self.selectionPipe.output }

  public init(
    settingsFeature: SettingsFeature,
    makeProvider: @escaping () -> any RecommendationsProvider,
    sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
      if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    }
  ) {
    self.settingsFeature = settingsFeature
    self.sessionFeature = settingsFeature.sessionFeature
    self.makeProvider = makeProvider
    self.sleep = sleep
  }

  private var session: Session {
    Session(userID: self.sessionFeature.currentUser?.id, generation: self.sessionFeature.generation)
  }
  private func requireCurrent(_ session: Session) throws {
    try Task.checkCancellation()
    guard self.session == session else { throw CancellationError() }
  }
  public func release(route: UUID) {
    self.pending.removeValue(forKey: route)?.task.cancel()
  }
  public func reset() {
    for route in Array(self.pending.keys) { self.release(route: route) }
  }
  public func load(_ request: Request, route: UUID) async {
    await self.request(request, route: route).value
  }

  /// Equivalent pending work on one screen shares a task. A different input
  /// cancels that screen's previous read, without affecting another screen.
  @discardableResult
  public func request(_ request: Request, route: UUID) -> Task<Void, Never> {
    let session = self.session
    if let pending = self.pending[route], pending.request == request, pending.session == session {
      return pending.task
    }
    self.release(route: route)
    let id = UUID()
    let provider = self.makeProvider()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let task = Task { [self] in
      defer {
        self.operations[id] = nil
        if self.pending[route]?.id == id { self.pending[route] = nil }
      }
      do {
        try Task.checkCancellation()
        guard self.session == session else { return }
        let selection: Selection?
        switch request {
        case .curated(let categories):
          selection = try await self.curated(categories, provider: provider, delay: delay)
        case .afterBacking(let project):
          selection = try await self.alternatives(project, provider: provider, delay: delay, session: session)
        }
        try Task.checkCancellation()
        guard self.session == session, self.pending[route]?.id == id, let selection else { return }
        self.selectionPipe.input.send(value: (route, selection))
      } catch {
        // These screens historically suppress category lookup errors. Individual
        // discovery failures are handled below so successful fallbacks survive.
      }
    }
    self.pending[route] = Pending(id: id, request: request, session: session, task: task)
    self.operations[id] = task
    return task
  }

  private func curated(
    _ categories: [KsApi.Category], provider: any RecommendationsProvider, delay: TimeInterval
  ) async throws -> Selection? {
    guard !categories.isEmpty else { return nil }
    let perPage = 30 / categories.count
    let sleep = self.sleep
    let projects = try await withThrowingTaskGroup(of: [Project].self) { group in
      for category in categories {
        let parameters = DiscoveryParams.defaults
          |> DiscoveryParams.lens.category .~ category
          |> DiscoveryParams.lens.state .~ .live
          |> DiscoveryParams.lens.perPage .~ perPage
        group.addTask { @MainActor in
          let projects: [Project]
          do { projects = try await provider.projects(parameters: parameters) }
          catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            return []
          }
          try await sleep(delay)
          try Task.checkCancellation()
          return projects
        }
      }
      var projects: [Project] = []
      for try await page in group { projects += page }
      return projects
    }
    // Preserve onboarding's duplicate entries and random ordering.
    return Selection(projects: projects.shuffled(), category: nil)
  }

  private func alternatives(
    _ project: Project, provider: any RecommendationsProvider, delay: TimeInterval, session: Session
  ) async throws -> Selection? {
    guard let projectCategory = project.category else { return nil }
    let id = Category.decode(id: "\(projectCategory.parentId ?? projectCategory.id)").toBase64()
    let fetched = try await provider.category(id: id)
    try await self.sleep(delay)
    try self.requireCurrent(session)
    let category = fetched.parent ?? fetched
    let base = DiscoveryParams.lens.perPage .~ 3 <> DiscoveryParams.lens.backed .~ false
    let similar = DiscoveryParams.defaults |> base |> DiscoveryParams.lens.similarTo .~ project
    let staff = DiscoveryParams.defaults |> base
      |> DiscoveryParams.lens.staffPicks .~ true |> DiscoveryParams.lens.category .~ category
    var projects: [Project] = []
    var seen = Set<Int>()
    for (index, parameters) in [Self.recommendedParameters, similar, staff].enumerated() {
      try self.requireCurrent(session)
      let page: [Project]
      do { page = try await provider.projects(parameters: parameters) }
      catch {
        try self.requireCurrent(session)
        if error is CancellationError { throw error }
        continue
      }
      try self.requireCurrent(session)
      for candidate in index == 0 ? Self.shuffleRecommendations(page) : page {
        guard candidate.id != project.id, seen.insert(candidate.id).inserted else { continue }
        projects.append(candidate)
        if projects.count == 3 { return Selection(projects: projects, category: category) }
      }
    }
    return projects.isEmpty ? nil : Selection(projects: projects, category: category)
  }

  public static let recommendedParameters = DiscoveryParams.defaults
    |> DiscoveryParams.lens.backed .~ false
    |> DiscoveryParams.lens.perPage .~ 6
    |> DiscoveryParams.lens.recommended .~ true

  // Retain the existing post-backing ordering algorithm during migration.
  private static func shuffleRecommendations(_ projects: [Project]) -> [Project] {
    guard projects.count > 1 else { return projects }
    var result = projects
    for index in result.indices {
      result.swapAt(index, Int(arc4random_uniform(UInt32(result.count - 1))))
    }
    return result
  }

  public func waitForOperations() async {
    while !self.operations.isEmpty {
      for task in Array(self.operations.values) { await task.value }
    }
  }
}
