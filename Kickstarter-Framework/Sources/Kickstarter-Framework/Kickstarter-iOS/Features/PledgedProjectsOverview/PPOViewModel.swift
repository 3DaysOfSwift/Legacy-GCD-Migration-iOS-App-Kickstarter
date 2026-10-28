import Combine
import Foundation
import GraphAPI
import KsApi
import Library
import UIKit

typealias PPOViewModelPaginator = Paginator<
  GraphAPI.FetchPledgedProjectsQuery.Data,
  PPOProjectCardViewModel,
  String,
  ErrorEnvelope,
  Void
>

@MainActor
protocol PPOViewModelInputs {
  func viewDidAppear()
  func refresh() async
  func loadMore() async

  func handleCardEvent(_: PPOCardEvent, from: PPOProjectCardModel)
}

@MainActor
protocol PPOViewModelOutputs {
  var results: PPOViewModelPaginator.Results { get }
  var preparedEvents: AnyPublisher<PPOPreparedEvent, Never> { get }
}

enum PPOPreparedEvent: Equatable {
  case backedProjects
  case exploreProjects
  case fixPaymentMethod(projectId: Int, backingId: Int)
  case fix3DSChallenge(clientSecret: String, onProgress: (PPOActionState) -> Void)
  case survey(url: String)
  case openPledgeManager(url: String)
  case projectDetails(param: ProjectPageParam)
  case editAddress(url: String)
  case confirmAddress(
    backingId: String,
    addressId: String,
    address: String,
    onProgress: (PPOActionState) -> Void
  )
  case contactCreator(messageSubject: MessageSubject)
  case updateRewardReceived(backingId: String, rewardReceived: Bool)
  case manageLivePledge(projectId: Int, backingId: Int)

  // swiftlint:disable:next cyclomatic_complexity
  static func == (lhs: PPOPreparedEvent, rhs: PPOPreparedEvent) -> Bool {
    switch (lhs, rhs) {
    case (.survey(let lhsUrl), .survey(let rhsUrl)):
      return lhsUrl == rhsUrl
    case (.openPledgeManager(let lhsUrl), .openPledgeManager(let rhsUrl)):
      return lhsUrl == rhsUrl
    case (.projectDetails(let lhsParam), .projectDetails(let rhsParam)):
      return lhsParam.param == rhsParam.param
    case (.editAddress(let lhsUrl), .editAddress(let rhsUrl)):
      return lhsUrl == rhsUrl
    case (.contactCreator(let lhsSubject), .contactCreator(let rhsSubject)):
      return lhsSubject == rhsSubject
    case (
      .fix3DSChallenge(clientSecret: let lhsSecret, onProgress: _),
      .fix3DSChallenge(clientSecret: let rhsSecret, onProgress: _)
    ):
      return lhsSecret == rhsSecret
    case (
      .confirmAddress(let lhsBackingId, let lhsAddressId, let lhsAddress, _),
      .confirmAddress(let rhsBackingId, let rhsAddressId, let rhsAddress, _)
    ):
      return lhsBackingId == rhsBackingId && lhsAddressId == rhsAddressId
        && lhsAddress == rhsAddress
    case (
      .fixPaymentMethod(let lhsProjectId, let lhsBackingId),
      .fixPaymentMethod(let rhsProjectId, let rhsBackingId)
    ):
      return lhsProjectId == rhsProjectId && lhsBackingId == rhsBackingId
    case (.backedProjects, .backedProjects):
      return true
    case (.exploreProjects, .exploreProjects):
      return true
    case (
      .updateRewardReceived(let lhsBackingId, let lhsRewardReceived),
      .updateRewardReceived(let rhsBackingId, let rhsRewardReceived)
    ):
      return lhsBackingId == rhsBackingId && lhsRewardReceived == rhsRewardReceived
    default:
      return false
    }
  }
}

@MainActor
final class PPOViewModel: ObservableObject, PPOViewModelInputs, PPOViewModelOutputs {
  init(feature injectedFeature: PledgedProjectsFeature? = nil) {
    let feature = injectedFeature ?? AppModel.shared.pledgedProjectsFeature
    self.feature = feature
    feature.snapshots(route: self.route)
      .map(Self.present)
      .subscribe(self.snapshots)
      .store(in: &self.cancellables)

    self.snapshots
      .drop(while: { results in
        if case .unloaded = results {
          return true
        } else {
          return false
        }
      })
      // SwiftUI List jumps around if reloading frequently. This code path prevents
      // unnecessary reloads if the data has loaded. If the values are the same and
      // both states have been loaded, then we can drop this change.
      .removeDuplicates(by: { left, right in
        left.hasLoaded && right.hasLoaded && left.values == right.values
      })
      .sink(receiveValue: { [weak self] results in
        self?.results = results
      })
      .store(in: &self.cancellables)

    // Prepare and route events
    self.handleCardEventSubject
      .compactMap { [weak self] event, card in
        self?.preparedEvent(for: event, cardModel: card)
      }
      .eraseToAnyPublisher()
      .subscribe(self.preparedEventSubject)
      .store(in: &self.cancellables)

    let latestLoadedResults = self.snapshots
      .compactMap { results in
        results.hasLoaded
          ? results.values
            .ppoAnalyticsProperties(page: results.page) : nil
      }

    // Analytics: When view appears, the next time it loads, send a PPO dashboard open
    self.viewDidAppearSubject
      .withFirst(from: latestLoadedResults)
      .sink { _, properties in
        AppEnvironment.current.ksrAnalytics.trackPPODashboardOpens(properties: properties)
      }
      .store(in: &self.cancellables)

    // Analytics: Card event
    self.handleCardEventSubject
      .withFirst(from: latestLoadedResults)
      .map { eventAndCardModel, overallProperties in
        (eventAndCardModel.0, eventAndCardModel.1, overallProperties)
      }
      .sink { [weak self] event, card, overallProperties in
        self?.trackCardEvent(event, cardModel: card, overallProperties: overallProperties)
      }
      .store(in: &self.cancellables)

    // Analytics: Finish confirming address
    self.confirmAddressProgressSubject
      .filter { $0.1 == .confirmed }
      .map { $0.0 }  // we just need the card
      .withFirst(from: latestLoadedResults)
      .sink { card, overallProperties in
        AppEnvironment.current.ksrAnalytics.trackPPOSubmitAddressConfirmation(
          project: card.projectAnalytics,
          properties: overallProperties
        )
      }
      .store(in: &self.cancellables)
  }

  // MARK: Helpers

  func trackCardEvent(
    _ event: PPOCardEvent,
    cardModel: PPOProjectCardModel,
    overallProperties: KSRAnalytics.PledgedProjectOverviewProperties
  ) {
    switch event {
    case .sendMessage:
      AppEnvironment.current.ksrAnalytics.trackPPOMessagingCreator(
        from: cardModel.projectAnalytics,
        properties: overallProperties
      )
    case .editAddress:
      AppEnvironment.current.ksrAnalytics.trackPPOEditAddress(
        project: cardModel.projectAnalytics,
        properties: overallProperties
      )
    case .fixPayment:
      AppEnvironment.current.ksrAnalytics.trackPPOFixingPaymentFailure(
        project: cardModel.projectAnalytics,
        properties: overallProperties
      )
    case .completeSurvey:
      AppEnvironment.current.ksrAnalytics.trackPPOOpeningSurvey(
        project: cardModel.projectAnalytics,
        properties: overallProperties
      )
    case .openPledgeManager:
      AppEnvironment.current.ksrAnalytics.trackPPOOpenPledgeManager(
        project: cardModel.projectAnalytics,
        properties: overallProperties
      )
    case .confirmAddress:
      AppEnvironment.current.ksrAnalytics.trackPPOInitiateConfirmingAddress(
        project: cardModel.projectAnalytics,
        properties: overallProperties
      )
    case .authenticateCard:
      AppEnvironment.current.ksrAnalytics.trackPPOAuthenticateCard(
        project: cardModel.projectAnalytics,
        properties: overallProperties
      )
    case .viewProjectDetails:
      AppEnvironment.current.ksrAnalytics.trackPPOViewProjectDetails(
        project: cardModel.projectAnalytics,
        properties: overallProperties
      )
    case .updateRewardReceived(let rewardReceived):
      AppEnvironment.current.ksrAnalytics.trackPPOUpdateRewardReceived(
        toggleOn: rewardReceived,
        project: cardModel.projectAnalytics,
        properties: overallProperties
      )
    case .manageLivePledge:
      AppEnvironment.current.ksrAnalytics.trackPPOManageLivePledge(
        project: cardModel.projectAnalytics,
        properties: overallProperties
      )
    }
  }

  func preparedEvent(
    for event: PPOCardEvent,
    cardModel: PPOProjectCardModel
  ) -> PPOPreparedEvent {
    switch event {
    case .editAddress(let url):
      return PPOPreparedEvent.editAddress(url: url)
    case .viewProjectDetails(let projectPageParam):
      return PPOPreparedEvent.projectDetails(param: projectPageParam)
    case .sendMessage:
      let messageSubject = MessageSubject.project(
        id: cardModel.projectId,
        name: cardModel.projectName
      )
      return PPOPreparedEvent.contactCreator(messageSubject: messageSubject)
    case .updateRewardReceived(rewardReceived: let rewardReceived):
      return PPOPreparedEvent.updateRewardReceived(
        backingId: cardModel.backingGraphId,
        rewardReceived: rewardReceived
      )
    case .completeSurvey(let url):
      return PPOPreparedEvent.survey(url: url)
    case .fixPayment:
      return PPOPreparedEvent.fixPaymentMethod(
        projectId: cardModel.projectId,
        backingId: cardModel.backingId
      )
    case .openPledgeManager(let url):
      return PPOPreparedEvent.openPledgeManager(url: url)
    case .confirmAddress(let address, let addressId):
      return PPOPreparedEvent.confirmAddress(
        backingId: cardModel.backingGraphId,
        addressId: addressId,
        address: address,
        onProgress: { [weak self] state in
          self?.confirmAddressProgressSubject.send((cardModel, state))
        }
      )
    case .authenticateCard(let clientSecret, let onProgress):
      return PPOPreparedEvent.fix3DSChallenge(
        clientSecret: clientSecret,
        onProgress: onProgress
      )
    case .manageLivePledge:
      return PPOPreparedEvent.manageLivePledge(
        projectId: cardModel.projectId,
        backingId: cardModel.backingId
      )
    }
  }

  private static func present(_ snapshot: PledgedProjectsFeature.Snapshot)
    -> PPOViewModelPaginator.Results
  {
    switch snapshot {
    case .unloaded: return .unloaded
    case .empty: return .empty
    case .error(let error): return .error(error)
    case .loading(let previous): return .loading(previous: Self.present(previous))
    case .allLoaded(let cards, let page):
      return .allLoaded(values: cards.map { PPOProjectCardViewModel(card: $0) }, page: page)
    case .someLoaded(let cards, let cursor, let total, let page):
      return .someLoaded(
        values: cards.map { PPOProjectCardViewModel(card: $0) }, cursor: cursor, total: total,
        page: page)
    }
  }

  // MARK: - Inputs

  func viewDidAppear() {
    self.feature.requestFirstPage(route: self.route)
    self.viewDidAppearSubject.send()
  }

  func loadMore() async {
    await self.feature.loadMore(route: self.route)
  }

  func refresh() async {
    await self.feature.refresh(route: self.route)
  }

  func handleCardEvent(_ cardAction: PPOCardEvent, from cardModel: PPOProjectCardModel) {
    self.handleCardEventSubject.send((cardAction, cardModel))
  }

  // MARK: - Outputs

  @Published var results = PPOViewModelPaginator.Results.unloaded

  var preparedEvents: AnyPublisher<PPOPreparedEvent, Never> {
    self.preparedEventSubject.eraseToAnyPublisher()
  }

  // MARK: - Private

  private let feature: PledgedProjectsFeature
  private let route = UUID()
  private let snapshots = CurrentValueSubject<PPOViewModelPaginator.Results, Never>(.unloaded)
  deinit {
    let feature = self.feature
    let route = self.route
    Task { @MainActor in feature.release(route: route) }
  }

  private let viewDidAppearSubject = PassthroughSubject<Void, Never>()
  private let confirmAddressProgressSubject = PassthroughSubject<
    (PPOProjectCardModel, PPOActionState),
    Never
  >()

  private let handleCardEventSubject = PassthroughSubject<
    (PPOCardEvent, PPOProjectCardModel),
    Never
  >()

  private var preparedEventSubject = PassthroughSubject<PPOPreparedEvent, Never>()

  private var cancellables: Set<AnyCancellable> = []

}

extension Sequence where Element == PPOProjectCardViewModel {
  func ppoAnalyticsProperties(page: Int?) -> KSRAnalytics.PledgedProjectOverviewProperties {
    var paymentFailedCount: Int = 0
    var cardAuthRequiredCount: Int = 0
    var surveyAvailableCount: Int = 0
    var addressLocksSoonCount: Int = 0
    var pledgeManagementCount: Int = 0

    var fundedProjectCount: Int = 0
    var liveProjectCount: Int = 0
    var unsuccessfulPledgeCount: Int = 0

    for viewModel in self {
      switch viewModel.card.tierType {
      case .fixPayment:
        paymentFailedCount += 1
      case .authenticateCard:
        cardAuthRequiredCount += 1
      case .openSurvey:
        surveyAvailableCount += 1
      case .confirmAddress:
        addressLocksSoonCount += 1
      case .pledgeManagement:
        pledgeManagementCount += 1
      case .surveySubmitted, .pledgeCollected, .addressConfirmed, .awaitingReward, .rewardReceived:
        fundedProjectCount += 1
      case .campaignLive, .campaignFunded, .campaignEnded:
        liveProjectCount += 1
      case .campaignFailed, .pledgeDropped, .pledgeCanceled:
        unsuccessfulPledgeCount += 1
      }
    }

    return KSRAnalytics.PledgedProjectOverviewProperties(
      addressLocksSoonCount: addressLocksSoonCount,
      surveyAvailableCount: surveyAvailableCount,
      pledgeManagementCount: pledgeManagementCount,
      paymentFailedCount: paymentFailedCount,
      cardAuthRequiredCount: cardAuthRequiredCount,
      fundedProjectCount: fundedProjectCount,
      liveProjectCount: liveProjectCount,
      unsuccessfulPledgeCount: unsuccessfulPledgeCount,
      page: page
    )
  }
}

extension Publisher {
  /// Combines this publisher with the first value emitted by another publisher.
  /// - Warning: This is not a direct replacement for `withLatestFrom` from other ReactiveX libraries.
  /// - Parameter other: The publisher to grab the first value from
  /// - Returns: A publisher that emits tuples of values from this publisher paired with the first value from the other publisher
  func withFirst<B>(from other: B) -> AnyPublisher<(Self.Output, B.Output), Self.Failure>
  where
    B: Publisher,
    B.Failure == Self.Failure
  {
    return self.flatMap { foo in
      other.first().map { (foo, $0) }
    }.eraseToAnyPublisher()
  }
}
