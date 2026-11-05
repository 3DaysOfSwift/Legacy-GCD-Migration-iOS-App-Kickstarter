import Foundation
import KsApi
import Prelude

public typealias PledgeCTAPrelaunchState = (
  prelaunch: Bool,
  saved: Bool,
  watchesCount: Int
)

/// The Pledge CTA can be in three states:
/// - It can be loading
/// - It can have a loaded project
/// - It can have a loading error
public enum PledgeCTAContainerViewData {
  case loading
  case project(Project)
  case error(ErrorEnvelope)
}

@MainActor
public protocol PledgeCTAContainerViewViewModelInputs {
  func configureWith(value: PledgeCTAContainerViewData)
  func pledgeCTAButtonTapped()
  func savedProjectFromNotification(project: Project?)
}

public enum PledgeCTAEvent {
  case activityHidden(Bool)
  case buttonStyle(ButtonStyleType)
  case buttonTitle(String)
  case tapped(PledgeStateCTAType)
  case buttonHidden(Bool)
  case watchesHidden(Bool)
  case prelaunch(PledgeCTAPrelaunchState)
  case retryHidden(Bool)
  case contentHidden(Bool)
  case subtitle(String)
  case title(String)
  case watchesCount(String)
}

@MainActor
public protocol PledgeCTAContainerViewViewModelOutputs: AnyObject {
  var onEvent: ((PledgeCTAEvent) -> Void)? { get set }
}

@MainActor
public protocol PledgeCTAContainerViewViewModelType {
  var inputs: PledgeCTAContainerViewViewModelInputs { get }
  var outputs: PledgeCTAContainerViewViewModelOutputs { get }
}

@MainActor
public final class PledgeCTAContainerViewViewModel: PledgeCTAContainerViewViewModelType,
  PledgeCTAContainerViewViewModelInputs, PledgeCTAContainerViewViewModelOutputs {
  public var onEvent: ((PledgeCTAEvent) -> Void)?
  private let sleep: @MainActor () async throws -> Void
  private var savedProjectTask: Task<Void, Never>?
  private var latestProject: Project?
  private var pledgeState: PledgeStateCTAType?
  private var buttonHidden: Bool?
  private var retryHidden: Bool?

  public init(sleep: @escaping @MainActor () async throws -> Void = {
    try await Task.sleep(for: .milliseconds(100))
  }) { self.sleep = sleep }

  public func configureWith(value: PledgeCTAContainerViewData) {
    switch value {
    case .loading:
      self.onEvent?(.activityHidden(false))
      self.setButtonHidden(true)
      self.setRetryHidden(true)
    case .error:
      self.onEvent?(.activityHidden(true))
      self.setButtonHidden(true)
      self.setRetryHidden(false)
    case let .project(project):
      self.onEvent?(.activityHidden(true))
      self.updatePledgeState(project: project, backing: project.personalization.backing)
      self.latestProject = project
      self.publishWatchesCount(project.watchesCount ?? 0)
      if let state = self.pledgeState { self.onEvent?(.subtitle(subtitle(project: project, pledgeState: state))) }
      let backing = project.personalization.backing
      let error = backing?.status == .authenticationRequired && backing?.paymentIncrements.isEmpty == true
      self.setButtonHidden(error)
      self.setRetryHidden(!error)
    }
  }

  public func pledgeCTAButtonTapped() {
    guard let state = self.pledgeState else { return }
    self.onEvent?(.tapped(state))
    if let project = self.latestProject {
      AppEnvironment.current.ksrAnalytics.trackPledgeCTAButtonClicked(stateType: state, project: project)
    }
  }

  public func savedProjectFromNotification(project: Project?) {
    guard let project else { return }
    self.savedProjectTask?.cancel()
    let sleep = self.sleep
    self.savedProjectTask = Task { [weak self] in
      do { try await sleep(); try Task.checkCancellation() } catch { return }
      self?.updatePledgeState(project: project, backing: project.personalization.backing)
    }
  }

  private func updatePledgeState(project: Project, backing: Backing?) {
    let next = pledgeCTA(project: project, backing: backing)
    guard self.pledgeState != next else { return }
    self.pledgeState = next
    let prelaunch: PledgeCTAPrelaunchState
    if case let .prelaunch(saved, count) = next {
      prelaunch = (true, saved, count)
    } else {
      prelaunch = (false, false, 0)
    }
    self.onEvent?(.prelaunch(prelaunch))
    self.onEvent?(.watchesHidden(!prelaunch.prelaunch))
    if self.latestProject != nil { self.publishWatchesCount(prelaunch.watchesCount) }
    self.onEvent?(.buttonStyle(next.buttonStyle))
    self.onEvent?(.buttonTitle(next.buttonTitle))
    self.onEvent?(.contentHidden(next.stackViewAndSpacerAreHidden))
    if let title = next.titleLabel { self.onEvent?(.title(title)) }
    if let project = self.latestProject { self.onEvent?(.subtitle(subtitle(project: project, pledgeState: next))) }
  }

  private func setButtonHidden(_ hidden: Bool) {
    guard self.buttonHidden != hidden else { return }
    self.buttonHidden = hidden
    self.onEvent?(.buttonHidden(hidden))
    if hidden { self.onEvent?(.contentHidden(true)) }
  }

  private func setRetryHidden(_ hidden: Bool) {
    guard self.retryHidden != hidden else { return }
    self.retryHidden = hidden
    self.onEvent?(.retryHidden(hidden))
  }

  private func publishWatchesCount(_ count: Int) {
    self.onEvent?(.watchesCount(Strings.activity_followers(number_of_followers: "\(count)")))
  }

  func waitForSavedProject() async { await self.savedProjectTask?.value }
  deinit { self.savedProjectTask?.cancel() }
  public var inputs: PledgeCTAContainerViewViewModelInputs { self }
  public var outputs: PledgeCTAContainerViewViewModelOutputs { self }
}

// MARK: - Functions

@MainActor
private func pledgeCTA(project: Project, backing: Backing?) -> PledgeStateCTAType {
  guard project.displayPrelaunch != .some(true) else {
    let projectIsSaved = project.personalization.isStarred ?? false

    return .prelaunch(saved: projectIsSaved, watchCount: project.watchesCount ?? 0)
  }

  if backing?.status == .dummy || project.pledgeManagementAvailable {
    return PledgeStateCTAType.pledgeManager
  }

  let isInPostCampaign = project.isInPostCampaignPledgingPhase

  guard let projectBacking = backing, project.personalization.isBacking == .some(true) else {
    if currentUserIsCreator(of: project) {
      return PledgeStateCTAType.viewYourRewards
    }

    if isInPostCampaign {
      return PledgeStateCTAType.pledge
    }

    return project.state == .live ? PledgeStateCTAType.pledge : PledgeStateCTAType.viewRewards
  }

  // NB: Add error case back once correctly returned
  switch (project.state, projectBacking.status, isInPostCampaign) {
  case (.live, _, _):
    return .manage
  case (.successful, _, true):
    return .viewBacking
  case (.successful, .errored, _):
    return .fix
  case (_, _, _):
    return .viewBacking
  }
}

@MainActor
private func subtitle(project: Project, pledgeState: PledgeStateCTAType) -> String {
  guard let backing = project.personalization.backing else { return "" }

  switch pledgeState {
  case .fix:
    return pledgeState.subtitleLabel ?? ""
  default:
    break
  }

  let amount = formattedPledge(amount: backing.amount, project: project)

  let reward = backing.reward
    ?? project.rewards.first { $0.id == backing.rewardId }
    ?? Reward.noReward

  guard let rewardTitle = reward.title else { return "\(amount)" }
  return "\(amount) • \(rewardTitle)"
}

@MainActor
private func formattedPledge(amount: Double, project: Project) -> String {
  let numberOfDecimalPlaces = amount.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
  let formattedAmount = String(format: "%.\(numberOfDecimalPlaces)f", amount)

  return Format.formattedCurrency(
    formattedAmount,
    currencyCode: project.statsCurrency,
    omitCurrencyCode: project.stats.omitUSCurrencyCode
  )
}

/// PledgeCTAContainerViewData was originally a tuple like
/// `(projectOrError: Either<Project, ErrorEnvelope>, isLoading: Bool)`
///
/// These are some convenience methods that bridge the original interface
/// with the new `enum` interface for this type.
extension PledgeCTAContainerViewData {
  var projectOrError: Either<Project, ErrorEnvelope>? {
    switch self {
    case .loading:
      return nil
    case let .project(project):
      return Either.left(project)
    case let .error(error):
      return Either.right(error)
    }
  }

  var isLoading: Bool {
    switch self {
    case .loading:
      return true
    default:
      return false
    }
  }
}

extension PledgeCTAContainerViewData: Equatable {
  public static func == (lhs: PledgeCTAContainerViewData, rhs: PledgeCTAContainerViewData) -> Bool {
    switch (lhs, rhs) {
    case (.loading, .loading):
      return true
    case let (.project(lProject), .project(rProject)):
      return lProject == rProject
    case let (.error(lError), .error(rError)):
      return lError.errorMessages == rError.errorMessages
    default:
      return false
    }
  }
}
