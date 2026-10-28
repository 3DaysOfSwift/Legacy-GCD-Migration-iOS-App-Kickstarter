import Combine
import Foundation
import KsApi
import Library
import ReactiveSwift
import UIKit

typealias PPOStripeConfiguration = (publishableKey: String, merchantIdentifier: String)

@MainActor
protocol PPOContainerViewModelInputs {
  func viewWillAppear()
  func projectAlertsCountChanged(_ count: Int?)
  func handle(preparedEvent: PPOPreparedEvent)
  func process3DSAuthentication(state: PPOActionState)
  func actionFinishedPerforming()
}

@MainActor
protocol PPOContainerViewModelOutputs {
  var projectAlertsBadge: AnyPublisher<TabBarBadge, Never> { get }
  var activityBadge: AnyPublisher<TabBarBadge, Never> { get }
  var preparedEvents: AnyPublisher<PPOPreparedEvent, Never> { get }
  var showBanner: AnyPublisher<MessageBannerConfiguration, Never> { get }
  var stripeConfiguration: AnyPublisher<PPOStripeConfiguration, Never> { get }
  var shouldRefresh: AnyPublisher<Void, Never> { get }
}

@MainActor
final class PPOContainerViewModel: PPOContainerViewModelInputs, PPOContainerViewModelOutputs {
  init(feature injectedFeature: PledgeFeature? = nil) {
    let feature = injectedFeature ?? AppModel.shared.pledgeFeature
    self.feature = feature
    let sessionStarted = NotificationCenter.default
      .publisher(for: .ksr_sessionStarted)
      .withEmptyValues()

    let sessionEnded = NotificationCenter.default
      .publisher(for: .ksr_sessionEnded)
      .withEmptyValues()

    let userUpdated = NotificationCenter.default
      .publisher(for: .ksr_userUpdated)
      .withEmptyValues()

    let currentUser = Publishers.Merge4(
      self.viewWillAppearSubject.withEmptyValues(),
      userUpdated,
      sessionStarted,
      sessionEnded
    )
    .map { _ in AppEnvironment.current.currentUser }

    self.viewWillAppearSubject
      .map { _ -> PPOStripeConfiguration in
        (
          publishableKey: AppEnvironment.current.environmentType.stripePublishableKey,
          merchantIdentifier: Secrets.ApplePay.merchantIdentifier
        )
      }
      .subscribe(self.stripeConfigurationSubject)
      .store(in: &self.cancellables)

    // Update the activity tab bar badge from the user object when it changes
    currentUser
      .map { user in TabBarBadge(count: user?.unseenActivityCount) }
      .subscribe(self.activityBadgeSubject)
      .store(in: &self.cancellables)

    // Update the project alerts tab bar badge from the supplied count when it changes
    self.projectAlertsCountSubject
      .map { count in TabBarBadge(count: count) }
      .subscribe(self.projectAlertsBadgeSubject)
      .store(in: &self.cancellables)

    // Handle 3DS authentication event banners
    self.process3DSAuthenticationState
      .compactMap { state -> MessageBannerConfiguration? in
        switch state {
        case .succeeded:
          return (
            .success,
            Strings.Youve_been_authenticated_successfully_pull_to_refresh()
          )
        case .failed:
          return (.error, Strings.Something_went_wrong_please_try_again())
        case .processing, .cancelled, .confirmed:
          return nil
        }
      }
      .sink { [weak self] configuration in
        self?.showBannerSubject.send(configuration)
      }
      .store(in: &self.cancellables)

    // Force the view to refresh
    Publishers.Merge4(
      self.actionFinishedPerformingSubject,
      self.process3DSAuthenticationState
        .filter { $0 == .succeeded }
        .withEmptyValues(),
      self.showBannerSubject
        .filter { $0.type == .success }
        .withEmptyValues(),
      self.receiptFailureSubject
    )
    .sink { [weak self] () in
      self?.shouldRefreshSubject.send(())
    }
    .store(in: &self.cancellables)
  }

  // MARK: - Inputs

  func viewWillAppear() {
    self.viewWillAppearSubject.send()
  }

  func projectAlertsCountChanged(_ count: Int?) {
    self.projectAlertsCountSubject.send(count)
  }

  func handle(preparedEvent: PPOPreparedEvent) {
    self.handlePreparedEventSubject.send(preparedEvent)
  }

  func process3DSAuthentication(state: PPOActionState) {
    self.process3DSAuthenticationState.send(state)
  }

  func confirmAddress(
    addressId: String, backingId: String, onProgress: @escaping (PPOActionState) -> Void
  ) {
    onProgress(.confirmed)
    self.observations += self.feature.confirmAddressResult(
      backingID: backingId, addressID: addressId
    )
    .startWithResult { [weak self] result in
      guard let self else { return }
      let success: Bool
      switch result {
      case .success(let acknowledged):
        onProgress(.succeeded)
        success = acknowledged
      case .failure: success = false
      }
      self.showBannerSubject.send(
        success
          ? (.success, Strings.Address_confirmed_need_to_change_your_address_before_it_locks())
          : (.error, Strings.Something_went_wrong_please_try_again()))
    }
  }

  func updateRewardReceived(backingId: String, rewardReceived: Bool) {
    self.observations += self.feature.receiptResult(backingID: backingId, received: rewardReceived)
      .startWithResult { [weak self] result in
        guard let self else { return }
        if case .success(true) = result { return }
        self.showBannerSubject.send((.error, Strings.Something_went_wrong_please_try_again()))
        self.receiptFailureSubject.send(())
      }
  }

  func actionFinishedPerforming() {
    self.actionFinishedPerformingSubject.send(())
  }

  // MARK: - Outputs

  var projectAlertsBadge: AnyPublisher<TabBarBadge, Never> {
    self.projectAlertsBadgeSubject.eraseToAnyPublisher()
  }

  var activityBadge: AnyPublisher<TabBarBadge, Never> {
    self.activityBadgeSubject.eraseToAnyPublisher()
  }

  var preparedEvents: AnyPublisher<PPOPreparedEvent, Never> {
    self.handlePreparedEventSubject.eraseToAnyPublisher()
  }

  var showBanner: AnyPublisher<MessageBannerConfiguration, Never> {
    self.showBannerSubject.eraseToAnyPublisher()
  }

  var stripeConfiguration: AnyPublisher<PPOStripeConfiguration, Never> {
    self.stripeConfigurationSubject.eraseToAnyPublisher()
  }

  var shouldRefresh: AnyPublisher<Void, Never> {
    self.shouldRefreshSubject.eraseToAnyPublisher()
  }

  // MARK: - Private

  private var viewWillAppearSubject = PassthroughSubject<Void, Never>()
  private var projectAlertsCountSubject = CurrentValueSubject<Int?, Never>(nil)
  private var projectAlertsBadgeSubject = CurrentValueSubject<TabBarBadge, Never>(.none)
  private var activityBadgeSubject = CurrentValueSubject<TabBarBadge, Never>(.none)
  private var handlePreparedEventSubject = PassthroughSubject<PPOPreparedEvent, Never>()
  private let showBannerSubject = PassthroughSubject<MessageBannerConfiguration, Never>()
  private let process3DSAuthenticationState = PassthroughSubject<PPOActionState, Never>()
  private let stripeConfigurationSubject = PassthroughSubject<PPOStripeConfiguration, Never>()
  private let feature: PledgeFeature
  private let observations = CompositeDisposable()
  private let receiptFailureSubject = PassthroughSubject<Void, Never>()
  deinit { self.observations.dispose() }
  private let actionFinishedPerformingSubject = PassthroughSubject<Void, Never>()
  private let shouldRefreshSubject = PassthroughSubject<Void, Never>()

  private var cancellables: Set<AnyCancellable> = []
}
