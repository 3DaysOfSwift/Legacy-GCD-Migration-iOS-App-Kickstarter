import Experimentation
import Foundation
import KsApi
import ReactiveSwift

/// A substitution boundary for the shipping-sorted rewards API.
@MainActor
public protocol RewardsProvider {
  func addOns(slug: String, locationID: String?) async throws -> [Reward]?
  func fastAddOns(baseRewardID: Int, country: String) async throws -> [Reward]
  func shippingLocations(projectID: Int) async throws -> [Location]
  func rewards(projectID: Int, country: String?, inserter: any NoRewardInserter) async throws
    -> [Reward]
}

@MainActor
public struct AsyncRewardsProvider: RewardsProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func addOns(slug: String, locationID: String?) async throws -> [Reward]? {
    try await self.service.rewardAddOns(slug: slug, locationID: locationID)
  }
  public func fastAddOns(baseRewardID: Int, country: String) async throws -> [Reward] {
    try await self.service.fastRewardAddOns(baseRewardID: baseRewardID, country: country)
  }
  public func shippingLocations(projectID: Int) async throws -> [Location] {
    try await self.service.shippingLocations(projectID: projectID)
  }

  public func rewards(
    projectID: Int,
    country: String?,
    inserter: any NoRewardInserter
  ) async throws -> [Reward] {
    try await self.service.sortedProjectRewards(
      projectID: projectID, country: country, inserter: inserter)
  }
}

/// Owns shipping-sorted reward loading and visibility/insertion policy.
/// The API returns one complete list, not cursor pages. Each screen has an
/// independent route; a changed country supersedes that route's previous read.
@MainActor
public final class RewardsFeature {
  public struct ShippingSnapshot {
    public fileprivate(set) var locations: [Location] = []
    public fileprivate(set) var selectedLocation: Location?
    public fileprivate(set) var isLoading = false
    public fileprivate(set) var error: ErrorEnvelope?
  }

  private struct ShippingIdentity: Equatable {
    let projectID: Int
    let selectedLocationID: Int?
    let hasShippableRewards: Bool
    let userID: Int?
  }

  private final class ShippingRoute {
    var snapshot = ShippingSnapshot()
    var request: (id: UUID, identity: ShippingIdentity, task: Task<Void, Never>)?
  }

  private var shippingRoutes: [UUID: ShippingRoute] = [:]
  private let shippingCompletionPipe = Signal<(UUID, Result<[Location], ErrorEnvelope>), Never>
    .pipe()
  private let shippingLoadingPipe = Signal<(UUID, Bool), Never>.pipe()
  private let shippingSelectionPipe = Signal<(UUID, Location?), Never>.pipe()
  public var shippingCompletions: Signal<(UUID, Result<[Location], ErrorEnvelope>), Never> {
    self.shippingCompletionPipe.output
  }

  public var shippingLoading: Signal<(UUID, Bool), Never> { self.shippingLoadingPipe.output }
  public var shippingSelections: Signal<(UUID, Location?), Never> {
    self.shippingSelectionPipe.output
  }

  public func shippingSnapshot(for route: UUID) -> ShippingSnapshot {
    self.shippingRoutes[route]?.snapshot ?? ShippingSnapshot()
  }

  public func loadShippingLocations(
    route: UUID, projectID: Int, selectedLocationID: Int?, hasShippableRewards: Bool
  ) async {
    guard !Task.isCancelled else { return }
    await self.requestShippingLocations(
      route: route, projectID: projectID, selectedLocationID: selectedLocationID,
      hasShippableRewards: hasShippableRewards
    ).value
  }

  /// A selector owns its route. Equivalent reads share execution; reconfiguration
  /// replaces only that selector's request, just as the former switchMap did.
  @discardableResult
  public func requestShippingLocations(
    route: UUID, projectID: Int, selectedLocationID: Int?, hasShippableRewards: Bool
  ) -> Task<Void, Never> {
    let identity = ShippingIdentity(
      projectID: projectID, selectedLocationID: selectedLocationID,
      hasShippableRewards: hasShippableRewards, userID: AppEnvironment.current.currentUser?.id
    )
    let entry = self.shippingRoutes[route] ?? ShippingRoute()
    self.shippingRoutes[route] = entry
    if let request = entry.request, request.identity == identity { return request.task }
    entry.request?.task.cancel()
    let requestID = UUID()
    let provider = self.makeProvider()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let sleep = self.sleep
    entry.snapshot.isLoading = true
    entry.snapshot.error = nil
    let task = Task { [weak self] in
      defer {
        if let self, entry.request?.id == requestID {
          entry.request = nil
          entry.snapshot.isLoading = false
          self.shippingLoadingPipe.input.send(value: (route, false))
        }
      }
      do {
        try Task.checkCancellation()
        guard identity.userID == AppEnvironment.current.currentUser?.id else {
          throw CancellationError()
        }
        let locations =
          hasShippableRewards ? try await provider.shippingLocations(projectID: projectID) : []
        try await sleep(delay)
        try Task.checkCancellation()
        guard identity.userID == AppEnvironment.current.currentUser?.id,
          let self, self.shippingRoutes[route]?.request?.id == requestID
        else { return }
        entry.snapshot.locations = locations
        entry.snapshot.selectedLocation =
          locations.first { $0.id == selectedLocationID }
          ?? defaultShippingLocation(fromLocations: locations)
        self.shippingCompletionPipe.input.send(value: (route, .success(locations)))
        self.shippingSelectionPipe.input.send(value: (route, entry.snapshot.selectedLocation))
      } catch is CancellationError {
        // Obsolete reads do not notify the delegate or display an error.
      } catch {
        // Legacy materialization delayed errors as well as successful data.
        do { try await sleep(delay) } catch { return }
        guard !Task.isCancelled, identity.userID == AppEnvironment.current.currentUser?.id,
          let self, self.shippingRoutes[route]?.request?.id == requestID
        else { return }
        let failure = (error as? ErrorEnvelope) ?? ErrorEnvelope.couldNotParseJSON
        entry.snapshot.error = failure
        self.shippingCompletionPipe.input.send(value: (route, .failure(failure)))
      }
    }
    entry.request = (requestID, identity, task)
    self.shippingLoadingPipe.input.send(value: (route, true))
    return task
  }

  public func selectShippingLocation(_ location: Location, route: UUID) {
    guard let entry = self.shippingRoutes[route] else { return }
    entry.snapshot.selectedLocation = location
    self.shippingSelectionPipe.input.send(value: (route, location))
  }

  public func releaseShippingLocations(route: UUID) {
    guard let entry = self.shippingRoutes.removeValue(forKey: route) else { return }
    let task = entry.request?.task
    entry.request = nil
    task?.cancel()
  }

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
  public let sessionFeature: SessionFeature
  private let makeProvider: @MainActor () -> any RewardsProvider
  private let fastCheckout: @MainActor () -> Bool
  private let moveNoReward: @MainActor () -> Bool
  private let sleep: @MainActor (TimeInterval) async throws -> Void
  private let completionPipe = Signal<(UUID, [Reward]), Never>.pipe()
  private let loadingPipe = Signal<(UUID, Bool), Never>.pipe()
  public var completions: Signal<(UUID, [Reward]), Never> { self.completionPipe.output }
  public var loading: Signal<(UUID, Bool), Never> { self.loadingPipe.output }

  public init(
    sessionFeature: SessionFeature,
    makeProvider: @escaping @MainActor () -> any RewardsProvider,
    fastCheckout: @escaping @MainActor () -> Bool = {
      SpeedyCheckoutExperiment().boolValue(forKey: .speedy_checkout_enabled) == true
    },
    moveNoReward: @escaping @MainActor () -> Bool = {
      MoveNoRewardOptionExperiment().boolValue(forKey: .show_no_reward_after_available_rewards)
        == true
    },
    sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { seconds in
      if seconds.isInfinite {
        try await Task.sleep(nanoseconds: UInt64.max)
      } else if seconds > 0 {
        try await Task.sleep(for: .seconds(seconds))
      }
      try Task.checkCancellation()
    }
  ) {
    self.sessionFeature = sessionFeature
    self.makeProvider = makeProvider
    self.fastCheckout = fastCheckout
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
    let inserter: any NoRewardInserter =
      identity.moveNoReward
      ? NoRewardAfterLastAvailableReward(shippingLocation: location, project: project)
      : NoRewardFirst()
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
        guard identity.userID == AppEnvironment.current.currentUser?.id else {
          throw CancellationError()
        }
        let rewards = try await provider.rewards(
          projectID: project.id,
          country: location?.country,
          inserter: inserter
        )
        try await sleep(delay)
        try Task.checkCancellation()
        guard identity.userID == AppEnvironment.current.currentUser?.id,
          let self, self.routes[route]?.request?.id == requestID
        else { return }
        let visibleRewards = rewards.filter { isStartDateBeforeToday(for: $0) }
        entry.snapshot.rewards = visibleRewards
        self.completionPipe.input.send(value: (route, visibleRewards))
      } catch is CancellationError {
        // Superseded reads do not produce product errors or empty success.
      } catch {
        guard !Task.isCancelled, identity.userID == AppEnvironment.current.currentUser?.id,
          let self, self.routes[route]?.request?.id == requestID
        else { return }
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

  private enum AddOnsQuery: Equatable {
    case none
    case standard(String, String?)
    case fast(Int, String)
  }
  private struct AddOnsIdentity: Equatable {
    let query: AddOnsQuery
    let userID: Int?
    let generation: Int
  }
  private struct AddOnsRequest {
    let id: UUID
    let identity: AddOnsIdentity
    let task: Task<[Reward]?, Error>
  }
  private var addOnsRequests: [UUID: AddOnsRequest] = [:]
  private var addOnsVersions: [UUID: UUID] = [:]
  private var addOnsTasks: [UUID: Task<[Reward]?, Error>] = [:]
  private var addOnsObservers: [UUID: Task<Void, Never>] = [:]

  private func requireCurrentAddOns(_ identity: AddOnsIdentity, route: UUID, version: UUID) throws {
    try Task.checkCancellation()
    guard self.addOnsVersions[route] == version,
      self.sessionFeature.isCurrent(userID: identity.userID, generation: identity.generation)
    else { throw CancellationError() }
  }

  private func requestAddOns(
    route: UUID, slug: String, baseReward: Reward?, shippingRule: ShippingRule?
  ) -> AddOnsRequest {
    let query: AddOnsQuery
    if let baseReward, !baseReward.isNoReward, baseReward.hasAddOns {
      if self.fastCheckout() {
        query = .fast(
          baseReward.id, shippingRule?.location.country ?? AppEnvironment.current.countryCode)
      } else {
        query = .standard(slug, shippingRule?.location.graphID)
      }
    } else {
      query = .none
    }
    let identity = AddOnsIdentity(
      query: query, userID: self.sessionFeature.currentUser?.id,
      generation: self.sessionFeature.generation)
    if let pending = self.addOnsRequests[route], pending.identity == identity { return pending }
    self.addOnsRequests[route]?.task.cancel()
    let id = UUID()
    self.addOnsVersions[route] = id
    let provider = self.makeProvider()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let task = Task { [self] () throws -> [Reward]? in
      defer {
        self.addOnsTasks[id] = nil
        if self.addOnsRequests[route]?.id == id { self.addOnsRequests[route] = nil }
      }
      try self.requireCurrentAddOns(identity, route: route, version: id)
      do {
        let rewards: [Reward]?
        switch query {
        case .none: rewards = nil
        case .standard(let slug, let location):
          rewards = try await provider.addOns(slug: slug, locationID: location)
        case .fast(let rewardID, let country):
          rewards = try await provider.fastAddOns(baseRewardID: rewardID, country: country)
        }
        try await self.sleep(delay)
        try self.requireCurrentAddOns(identity, route: route, version: id)
        return rewards
      } catch {
        try self.requireCurrentAddOns(identity, route: route, version: id)
        try await self.sleep(delay)
        try self.requireCurrentAddOns(identity, route: route, version: id)
        throw error
      }
    }
    let request = AddOnsRequest(id: id, identity: identity, task: task)
    self.addOnsRequests[route] = request
    self.addOnsTasks[id] = task
    return request
  }

  public func addOns(route: UUID, slug: String, baseReward: Reward?, shippingRule: ShippingRule?)
    async throws -> [Reward]?
  {
    try Task.checkCancellation()
    let request = self.requestAddOns(
      route: route, slug: slug, baseReward: baseReward, shippingRule: shippingRule)
    do {
      let value = try await request.task.value
      try self.requireCurrentAddOns(request.identity, route: route, version: request.id)
      return value
    } catch {
      try self.requireCurrentAddOns(request.identity, route: route, version: request.id)
      throw error
    }
  }

  /// Compatibility for the existing presentation graph; request execution is owned above.
  public func addOnsResult(
    route: UUID, slug: String, baseReward: Reward?, shippingRule: ShippingRule?
  )
    -> SignalProducer<[Reward]?, ErrorEnvelope>
  {
    let userID = self.sessionFeature.currentUser?.id
    let generation = self.sessionFeature.generation
    return SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        guard self.sessionFeature.isCurrent(userID: userID, generation: generation) else {
          observer.sendInterrupted()
          return
        }
        let request = self.requestAddOns(
          route: route, slug: slug, baseReward: baseReward, shippingRule: shippingRule)
        let id = UUID()
        let task = Task { [self] in
          defer { self.addOnsObservers[id] = nil }
          do {
            let value = try await request.task.value
            try self.requireCurrentAddOns(request.identity, route: route, version: request.id)
            observer.send(value: value)
            observer.sendCompleted()
          } catch {
            guard !Task.isCancelled, !(error is CancellationError),
              self.addOnsVersions[route] == request.id,
              self.sessionFeature.isCurrent(userID: userID, generation: generation) else {
              observer.sendInterrupted()
              return
            }
            observer.send(error: (error as? ErrorEnvelope) ?? .couldNotParseJSON)
          }
        }
        self.addOnsObservers[id] = task
        lifetime.observeEnded { task.cancel() }
      }
    }
  }

  public func releaseAddOns(route: UUID) {
    self.addOnsVersions[route] = nil
    self.addOnsRequests.removeValue(forKey: route)?.task.cancel()
  }
  public func waitForAddOns() async {
    while !self.addOnsTasks.isEmpty || !self.addOnsObservers.isEmpty {
      for task in Array(self.addOnsTasks.values) { _ = await task.result }
      for task in Array(self.addOnsObservers.values) { await task.value }
    }
  }

  nonisolated public static func availableAddOns(
    _ addOns: [Reward], project: Project, baseReward: Reward, shippingRule: ShippingRule?
  ) -> [Reward] {
    filteredAddOns(
      addOns.filter { addOnIsAvailable($0, in: project) },
      filteredBy: shippingRule, baseReward: baseReward)
  }

}

private func addOnIsAvailable(_ addOn: Reward, in project: Project) -> Bool {
  // If the user is backing this addOn, it's available for editing
  if let backedAddOns = project.personalization.backing?.addOns,
    backedAddOns.map(\.id).contains(addOn.id)
  {
    return true
  }

  return addOn.isAvailable ?? false
}

private func filteredAddOns(
  _ addOns: [Reward],
  filteredBy shippingRule: ShippingRule?,
  baseReward: Reward
) -> [Reward] {
  let isBaseRewardDigital = isRewardDigital(baseReward)
  let isBaseRewardLocalPickup = isRewardLocalPickup(baseReward)

  return addOns.filter { addOn in
    var isValidAddonToDisplay = false
    let isAddOnDigital = isRewardDigital(addOn)
    let isAddOnLocalPickup = isRewardLocalPickup(addOn)
    let isAddOnLocalOrDigital = isAddOnDigital || isAddOnLocalPickup
    // For digital-only base rewards only return add-ons that are also digital-only.
    if isBaseRewardDigital, isAddOnDigital {
      isValidAddonToDisplay = true
    } else if isBaseRewardLocalPickup, isAddOnLocalOrDigital {
      isValidAddonToDisplay = true  // return all addons that are digital for local base reward

      if isAddOnLocalPickup {
        if let addOnLocationId = addOn.localPickup?.id,
          let baseRewardLocationId = baseReward.localPickup?.id,
          addOnLocationId == baseRewardLocationId
        {
          // if add on is local for local base, ensure locations are equal before displaying
          isValidAddonToDisplay = true
        } else {
          isValidAddonToDisplay = false
        }
      }
    } else if !isBaseRewardDigital, !isBaseRewardLocalPickup {
      /**
       For restricted or unrestricted shipping base rewards, unrestricted shipping
       or digital-only add-ons are available.
       */
      isValidAddonToDisplay =
        isAddOnDigital || addOnReward(addOn, shipsTo: shippingRule?.location.id)
    }

    return isValidAddonToDisplay
  }
}

/// For base rewards that have restricted or unrestricted shipping, only return
/// add-ons that can ship to the selected shipping location.
private func addOnReward(
  _ addOn: Reward,
  shipsTo locationId: Int?
) -> Bool {
  guard let selectedLocationId = locationId else { return false }

  let addOnShippingLocationIds: Set<Int> = Set(
    addOn.shippingRulesExpanded?.map(\.location).map(\.id) ?? []
  )

  return addOnShippingLocationIds.contains(selectedLocationId)
}
