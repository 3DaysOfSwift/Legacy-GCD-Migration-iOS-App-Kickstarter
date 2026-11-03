import Foundation
import KsApi
import Prelude
import ReactiveExtensions
import ReactiveSwift

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

@MainActor public protocol PledgeShippingLocationViewModelInputs {
  func configureWith(data: PledgeShippingLocationViewData)
  func shippingLocationButtonTapped()
  func shippingLocationCancelButtonTapped()
  func shippingLocationUpdated(to rule: Location)
  func viewDidLoad()
}

@MainActor public protocol PledgeShippingLocationViewModelOutputs {
  var adaptableStackViewIsHidden: Signal<Bool, Never> { get }
  var dismissShippingLocations: Signal<Void, Never> { get }
  var presentShippingLocations: Signal<([Location], Location), Never> { get }
  var notifyDelegateOfSelectedShippingLocation: Signal<Location?, Never> { get }
  var shimmerLoadingViewIsHidden: Signal<Bool, Never> { get }
  var shippingLocationButtonTitle: Signal<String, Never> { get }
  var shippingRulesError: Signal<String, Never> { get }
  var shippingLocationViewHidden: Signal<Bool, Never> { get }
}

@MainActor public protocol PledgeShippingLocationViewModelType {
  var inputs: PledgeShippingLocationViewModelInputs { get }
  var outputs: PledgeShippingLocationViewModelOutputs { get }
}

@MainActor public final class PledgeShippingLocationViewModel: PledgeShippingLocationViewModelType,
  PledgeShippingLocationViewModelInputs,
  PledgeShippingLocationViewModelOutputs {
  private let rewardsFeature: RewardsFeature
  private let route = UUID()
  private let disposables = CompositeDisposable()
  internal private(set) var loadingTask: Task<Void, Never>?

  public init(rewardsFeature: RewardsFeature? = nil) {
    let rewardsFeature = rewardsFeature ?? AppModel.shared.rewardsFeature
    self.rewardsFeature = rewardsFeature
    let route = self.route
    let configData = Signal.combineLatest(
      self.configDataProperty.signal.skipNil(),
      self.viewDidLoadProperty.signal
    )
    .map(first)

    // Hide the selector if the project has no shippable rewards.
    self.shippingLocationViewHidden = configData.map { data in
      !data.hasShippableRewards
    }

    let isLoading = MutableProperty(false)

    let completions = rewardsFeature.shippingCompletions.filter { $0.0 == route }.map { $0.1 }
    let loadedLocations = completions.compactMap { result -> [Location]? in
      guard case let .success(locations) = result else { return nil }
      return locations
    }
    let erroredLocations = completions.compactMap { result -> ErrorEnvelope? in
      guard case let .failure(error) = result else { return nil }
      return error
    }

    self.adaptableStackViewIsHidden = isLoading.signal
    self.shimmerLoadingViewIsHidden = isLoading.signal.negate()

    self.shippingRulesError = erroredLocations
      .mapConst(Strings.We_were_unable_to_load_the_shipping_destinations())

    let selectedShippingLocation = rewardsFeature.shippingSelections
      .filter { $0.0 == route }.map { $0.1 }

    self.notifyDelegateOfSelectedShippingLocation = selectedShippingLocation

    self.presentShippingLocations = Signal.combineLatest(
      loadedLocations,
      selectedShippingLocation.skipNil()
    )
    .takeWhen(self.shippingLocationButtonTappedSignal)

    self.shippingLocationButtonTitle = selectedShippingLocation
      .skipNil()
      .map { $0.localizedName }

    self.dismissShippingLocations = Signal.merge(
      self.shippingLocationCancelButtonTappedProperty.signal,
      self.shippingLocationUpdatedSignal.signal
        .ignoreValues()
        .ksr_debounce(.milliseconds(300), on: AppEnvironment.current.scheduler)
    )

    self.disposables += rewardsFeature.shippingLoading.filter { $0.0 == route }
      .observeValues { [weak self] _, loading in
        isLoading.value = loading
        if !loading { self?.loadingTask = nil }
      }
    self.disposables += configData.observeValues { [weak self] data in
      self?.loadingTask = rewardsFeature.requestShippingLocations(
        route: route, projectID: data.pid, selectedLocationID: data.selectedLocationId,
        hasShippableRewards: data.hasShippableRewards
      )
    }
  }

  deinit {
    self.loadingTask?.cancel()
    self.disposables.dispose()
    let rewardsFeature = self.rewardsFeature
    let route = self.route
    Task { @MainActor in rewardsFeature.releaseShippingLocations(route: route) }
  }

  private let configDataProperty = MutableProperty<PledgeShippingLocationViewData?>(nil)
  public func configureWith(data: PledgeShippingLocationViewData) {
    self.configDataProperty.value = data
  }

  private let (shippingLocationButtonTappedSignal, shippingLocationButtonTappedObserver)
    = Signal<Void, Never>.pipe()
  public func shippingLocationButtonTapped() {
    self.shippingLocationButtonTappedObserver.send(value: ())
  }

  private let shippingLocationCancelButtonTappedProperty = MutableProperty(())
  public func shippingLocationCancelButtonTapped() {
    self.shippingLocationCancelButtonTappedProperty.value = ()
  }

  private let (shippingLocationUpdatedSignal, shippingLocationUpdatedObserver) = Signal<Location, Never>
    .pipe()
  public func shippingLocationUpdated(to location: Location) {
    self.rewardsFeature.selectShippingLocation(location, route: self.route)
    self.shippingLocationUpdatedObserver.send(value: location)
  }

  private let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
  }

  public let adaptableStackViewIsHidden: Signal<Bool, Never>
  public let dismissShippingLocations: Signal<Void, Never>
  public let presentShippingLocations: Signal<([Location], Location), Never>
  public let notifyDelegateOfSelectedShippingLocation: Signal<Location?, Never>
  public let shimmerLoadingViewIsHidden: Signal<Bool, Never>
  public let shippingLocationButtonTitle: Signal<String, Never>
  public let shippingRulesError: Signal<String, Never>
  public let shippingLocationViewHidden: Signal<Bool, Never>

  public var inputs: PledgeShippingLocationViewModelInputs { return self }
  public var outputs: PledgeShippingLocationViewModelOutputs { return self }
}
