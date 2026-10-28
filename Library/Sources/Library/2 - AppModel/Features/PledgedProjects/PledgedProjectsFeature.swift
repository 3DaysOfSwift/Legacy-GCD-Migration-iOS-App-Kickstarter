import Combine
import Foundation
import GraphAPI
import KsApi

@MainActor
public protocol PledgedProjectsProvider {
  func page(tiers: [PledgeProjectsOverviewSort], cursor: String?, limit: Int) async throws
    -> GraphAPI.FetchPledgedProjectsQuery.Data
}

@MainActor
public struct AsyncPledgedProjectsProvider: PledgedProjectsProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func page(tiers: [PledgeProjectsOverviewSort], cursor: String?, limit: Int) async throws
    -> GraphAPI.FetchPledgedProjectsQuery.Data
  {
    try await self.service.pledgedProjects(tiers: tiers, cursor: cursor, limit: limit)
  }
}

/// Owns overview requests, pagination and account isolation. Combine carries snapshots only.
@MainActor
public final class PledgedProjectsFeature {
  public typealias Snapshot = Paginator<
    GraphAPI.FetchPledgedProjectsQuery.Data, PPOProjectCardModel, String, ErrorEnvelope, Void
  >.Results
  private let sessionFeature: SessionFeature
  private let makeProvider: () -> any PledgedProjectsProvider
  private let tiers: () -> [PledgeProjectsOverviewSort]

  public init(
    sessionFeature: SessionFeature, makeProvider: @escaping () -> any PledgedProjectsProvider,
    tiers: @escaping () -> [PledgeProjectsOverviewSort] = PledgedProjectsFeature.enabledTiers
  ) {
    self.sessionFeature = sessionFeature
    self.makeProvider = makeProvider
    self.tiers = tiers
  }

  public static func enabledTiers() -> [PledgeProjectsOverviewSort] {
    if featurePledgedProjectsOverviewV4Enabled() { return PPOTierType.allGraphQLTypes() }
    if featurePledgedProjectsOverviewV2Enabled() { return PPOTierType.fundedProjectGraphQLTypes() }
    return PPOTierType.projectAlertGraphQLTypes()
  }

  private struct Session: Equatable {
    let userID: Int?
    let generation: Int
  }
  private var session: Session {
    Session(userID: self.sessionFeature.currentUser?.id, generation: self.sessionFeature.generation)
  }
  private struct Pending {
    let id: UUID
    let cursor: String?
    let tiers: [PledgeProjectsOverviewSort]
    let session: Session
    let task: Task<Void, Never>
  }
  private final class Route {
    let snapshots = CurrentValueSubject<Snapshot, Never>(.unloaded)
    var pending: Pending?
    var session: Session?
    var tiers: [PledgeProjectsOverviewSort] = []
  }
  private var routes: [UUID: Route] = [:]
  private var tasks: [UUID: Task<Void, Never>] = [:]

  private func route(_ id: UUID) -> Route {
    if let route = self.routes[id] { return route }
    let route = Route()
    self.routes[id] = route
    return route
  }
  public func snapshots(route: UUID) -> AnyPublisher<Snapshot, Never> {
    self.route(route).snapshots.eraseToAnyPublisher()
  }

  @discardableResult
  public func requestFirstPage(route: UUID) -> Task<Void, Never> {
    self.request(route: route, cursor: nil)
  }
  public func refresh(route: UUID) async {
    guard !Task.isCancelled else { return }
    await self.requestFirstPage(route: route).value
  }
  public func loadMore(route id: UUID) async {
    guard !Task.isCancelled else { return }
    let route = self.route(id)
    if route.session != self.session || route.tiers != self.tiers() {
      await self.refresh(route: id)
    } else if let pending = route.pending {
      await pending.task.value
    } else if let cursor = route.snapshots.value.cursor {
      await self.request(route: id, cursor: cursor).value
    }
    // A terminal page is already complete; it must never wait for another publication.
  }

  private func request(route id: UUID, cursor: String?) -> Task<Void, Never> {
    let route = self.route(id)
    let session = self.session
    let tiers = self.tiers()
    if let pending = route.pending, pending.cursor == cursor, pending.session == session,
      pending.tiers == tiers
    {
      return pending.task
    }
    route.pending?.task.cancel()
    let previous: Snapshot
    if route.session != session {
      previous = .unloaded
    } else if case .loading(let loaded) = route.snapshots.value {
      previous = loaded
    } else {
      previous = route.snapshots.value
    }
    let provider = self.makeProvider()
    let requestID = UUID()
    let task = Task { [self] in
      defer {
        self.tasks[requestID] = nil
        if route.pending?.id == requestID { route.pending = nil }
      }
      do {
        try Task.checkCancellation()
        let data = try await provider.page(tiers: tiers, cursor: cursor, limit: 10)
        try Task.checkCancellation()
        guard route.pending?.id == requestID, self.session == session else { return }
        let pledges = data.pledgeProjectsOverview?.pledges
        let newCards =
          pledges?.edges?.compactMap { $0?.node }.compactMap { PPOProjectCardModel(node: $0) } ?? []
        let cards = (cursor == nil ? [] : previous.values) + newCards
        let page =
          newCards.isEmpty
          ? (cursor == nil ? nil : previous.page) : (cursor == nil ? 1 : (previous.page ?? 0) + 1)
        let snapshot: Snapshot
        if cards.isEmpty {
          snapshot = .empty
        } else if let next = pledges?.pageInfo.endCursor, !newCards.isEmpty {
          snapshot = .someLoaded(
            values: cards, cursor: next, total: pledges?.totalCount, page: page)
        } else {
          snapshot = .allLoaded(values: cards, page: page)
        }
        route.snapshots.send(snapshot)
      } catch {
        guard !Task.isCancelled, !(error is CancellationError), route.pending?.id == requestID,
          self.session == session
        else { return }
        route.snapshots.send(.error((error as? ErrorEnvelope) ?? .couldNotParseJSON))
      }
    }
    route.session = session
    route.tiers = tiers
    route.pending = Pending(
      id: requestID, cursor: cursor, tiers: tiers, session: session, task: task)
    self.tasks[requestID] = task
    route.snapshots.send(.loading(previous: previous))
    return task
  }
  public func release(route: UUID) {
    self.routes.removeValue(forKey: route)?.pending?.task.cancel()
  }
  public func reset() {
    for route in self.routes.values {
      route.pending?.task.cancel()
      route.pending = nil
      route.session = nil
      route.snapshots.send(.unloaded)
    }
  }
  public func waitForOperations() async {
    while !self.tasks.isEmpty {
      for task in Array(self.tasks.values) { await task.value }
    }
  }
}
