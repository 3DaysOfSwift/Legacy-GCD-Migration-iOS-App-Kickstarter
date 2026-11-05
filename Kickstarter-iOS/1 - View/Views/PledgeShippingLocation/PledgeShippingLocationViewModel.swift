import Foundation
import KsApi
import Prelude

public struct PledgeShippingLocationViewData {
  /// Project ID
  let pid: Int
  /// Initial selected location
  let selectedLocationId: Int?
  /// Whether or not the project has any rewards that require shipping.
  let hasShippableRewards: Bool

  public init(withProject project: Project) {
    self.pid = project.id
    self.selectedLocationId = project.personalization.backing?.locationId

    guard project.rewards.count > 0 else {
      assert(
        false,
        "Project has no rewards attached, so we don't know whether or not to show the shipping location."
      )

      self.hasShippableRewards = true
      return
    }

    // TODO: Clean up when a Project field for this is added (MBL-3150)
    self.hasShippableRewards = project.rewards
      .contains(where: { $0.shipping.enabled })
  }
}

@MainActor
final class PledgeShippingLocationViewModel {
  enum Event {
    case visibility(Bool)
    case loading(Bool)
    case selected(Location?)
    case present([Location], Location)
    case dismiss
    case error
  }

  var onEvent: ((Event) -> Void)?
  private let rewardsFeature: RewardsFeature
  private let route = UUID()
  private let dismissDelay: @MainActor () async throws -> Void
  private var data: PledgeShippingLocationViewData?
  private var hasLoaded = false
  private var loadID = UUID()
  internal private(set) var loadingTask: Task<Void, Never>?
  internal private(set) var dismissTask: Task<Void, Never>?

  init(
    rewardsFeature: RewardsFeature? = nil,
    dismissDelay: @escaping @MainActor () async throws -> Void = {
      try await Task.sleep(for: .milliseconds(300))
    }
  ) {
    self.rewardsFeature = rewardsFeature ?? AppModel.shared.rewardsFeature
    self.dismissDelay = dismissDelay
  }

  func configureWith(data: PledgeShippingLocationViewData) {
    self.data = data
    self.loadIfReady()
  }

  func viewDidLoad() {
    self.hasLoaded = true
    self.loadIfReady()
  }

  private func loadIfReady() {
    guard self.hasLoaded, let data = self.data else { return }
    self.loadingTask?.cancel()
    let id = UUID()
    self.loadID = id
    self.onEvent?(.visibility(!data.hasShippableRewards))
    self.onEvent?(.loading(true))
    let feature = self.rewardsFeature
    let route = self.route
    let request = feature.requestShippingLocations(
      route: route, projectID: data.pid, selectedLocationID: data.selectedLocationId,
      hasShippableRewards: data.hasShippableRewards
    )
    self.loadingTask = Task { [weak self] in
      await request.value
      guard !Task.isCancelled, let self, self.loadID == id else { return }
      let snapshot = feature.shippingSnapshot(for: route)
      if snapshot.hasResult {
        if snapshot.error != nil { self.onEvent?(.error) }
        else { self.onEvent?(.selected(snapshot.selectedLocation)) }
      }
      self.onEvent?(.loading(false))
    }
  }

  func shippingLocationButtonTapped() {
    let snapshot = self.rewardsFeature.shippingSnapshot(for: self.route)
    guard let location = snapshot.selectedLocation else { return }
    self.onEvent?(.present(snapshot.locations, location))
  }

  func shippingLocationCancelButtonTapped() { self.onEvent?(.dismiss) }

  func shippingLocationUpdated(to location: Location) {
    self.rewardsFeature.selectShippingLocation(location, route: self.route)
    self.onEvent?(.selected(location))
    self.dismissTask?.cancel()
    let delay = self.dismissDelay
    self.dismissTask = Task { [weak self] in
      do { try await delay() } catch { return }
      guard !Task.isCancelled else { return }
      self?.onEvent?(.dismiss)
    }
  }

  deinit {
    self.loadingTask?.cancel()
    self.dismissTask?.cancel()
    let feature = self.rewardsFeature
    let route = self.route
    Task { @MainActor in feature.releaseShippingLocations(route: route) }
  }
}
