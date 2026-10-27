import Experimentation
import Foundation
import KsApi
import ReactiveSwift

/// A substitution boundary for the shipping-sorted rewards API.
@MainActor
public protocol RewardsProvider {
  func rewards(projectID: Int, country: String?, inserter: any NoRewardInserter) async throws -> [Reward]
}

@MainActor
public struct AsyncRewardsProvider: RewardsProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func rewards(
    projectID: Int,
    country: String?,
    inserter: any NoRewardInserter
  ) async throws -> [Reward] {
    try await self.service.sortedProjectRewards(projectID: projectID, country: country, inserter: inserter)
  }
}

/// Owns shipping-sorted reward loading and visibility/insertion policy.
/// The API returns one complete list, not cursor pages. Each screen has an
/// independent route; a changed country supersedes that route's previous read.
@MainActor
public final class RewardsFeature {
  public struct Snapshot {
    public fileprivate(set) var rewards: [Reward] = []
    public fileprivate(set) var isLoading = false
    public fileprivate(set) var error: ErrorEnvelope?
  }

  private struct Identity: Equatable {
    let projectID: Int
    let country: String?
    let locationID: Int?
    let userID: Int?
    let moveNoReward: Bool
    let state: Project.State
    let postCampaign: Bool
    let creatorID: Int
    let backedRewardID: Int?
  }

  private final class Route {
    var snapshot = Snapshot()
    var request: (id: UUID, identity: Identity, task: Task<Void, Never>)?
  }

  private var routes: [UUID: Route] = [:]
  private let makeProvider: @MainActor () -> any RewardsProvider
  private let moveNoReward: @MainActor () -> Bool
  private let sleep: @MainActor (TimeInterval) async throws -> Void
  private let completionPipe = Signal<(UUID, [Reward]), Never>.pipe()
  private let loadingPipe = Signal<(UUID, Bool), Never>.pipe()
  public var completions: Signal<(UUID, [Reward]), Never> { self.completionPipe.output }
  public var loading: Signal<(UUID, Bool), Never> { self.loadingPipe.output }

  public init(
    makeProvider: @escaping @MainActor () -> any RewardsProvider,
    moveNoReward: @escaping @MainActor () -> Bool = {
      MoveNoRewardOptionExperiment().boolValue(forKey: .show_no_reward_after_available_rewards) == true
    },
    sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { seconds in
      if seconds.isInfinite { try await Task.sleep(nanoseconds: UInt64.max) }
      else if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
      try Task.checkCancellation()
    }
  ) {
    self.makeProvider = makeProvider
    self.moveNoReward = moveNoReward
    self.sleep = sleep
  }

  public func snapshot(for route: UUID) -> Snapshot { self.routes[route]?.snapshot ?? Snapshot() }

  public func load(route: UUID, project: Project, location: Location?) async {
    guard !Task.isCancelled else { return }
    await self.requestLoad(route: route, project: project, location: location).value
  }

  @discardableResult
  public func requestLoad(route: UUID, project: Project, location: Location?) -> Task<Void, Never> {
    let identity = Identity(
      projectID: project.id, country: location?.country, locationID: location?.id,
      userID: AppEnvironment.current.currentUser?.id, moveNoReward: self.moveNoReward(),
      state: project.state, postCampaign: project.isInPostCampaignPledgingPhase,
      creatorID: project.creator.id, backedRewardID: project.personalization.backing?.rewardId
    )
    let entry = self.routes[route] ?? Route()
    self.routes[route] = entry
    if let request = entry.request, request.identity == identity { return request.task }
    entry.request?.task.cancel()
    let requestID = UUID()
    let provider = self.makeProvider()
    let inserter: any NoRewardInserter = identity.moveNoReward
      ? NoRewardAfterLastAvailableReward(shippingLocation: location, project: project) : NoRewardFirst()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let sleep = self.sleep
    entry.snapshot.isLoading = true
    entry.snapshot.error = nil
    let task = Task { [weak self] in
      defer {
        if let self, entry.request?.id == requestID {
          entry.request = nil
          entry.snapshot.isLoading = false
          self.loadingPipe.input.send(value: (route, false))
        }
      }
      do {
        try Task.checkCancellation()
        guard identity.userID == AppEnvironment.current.currentUser?.id else { throw CancellationError() }
        let rewards = try await provider.rewards(
          projectID: project.id,
          country: location?.country,
          inserter: inserter
        )
        try await sleep(delay)
        try Task.checkCancellation()
        guard identity.userID == AppEnvironment.current.currentUser?.id,
              let self, self.routes[route]?.request?.id == requestID else { return }
        let visibleRewards = rewards.filter { isStartDateBeforeToday(for: $0) }
        entry.snapshot.rewards = visibleRewards
        self.completionPipe.input.send(value: (route, visibleRewards))
      } catch is CancellationError {
        // Superseded reads do not produce product errors or empty success.
      } catch {
        guard !Task.isCancelled, identity.userID == AppEnvironment.current.currentUser?.id,
              let self, self.routes[route]?.request?.id == requestID else { return }
        entry.snapshot.error = (error as? ErrorEnvelope) ?? ErrorEnvelope.couldNotParseJSON
      }
    }
    entry.request = (requestID, identity, task)
    self.loadingPipe.input.send(value: (route, true))
    return task
  }

  public func cancel(route: UUID) {
    guard let entry = self.routes[route] else { return }
    let task = entry.request?.task
    entry.request = nil
    entry.snapshot.isLoading = false
    task?.cancel()
    self.loadingPipe.input.send(value: (route, false))
  }

  public func release(route: UUID) {
    self.cancel(route: route)
    self.routes.removeValue(forKey: route)
  }
}
