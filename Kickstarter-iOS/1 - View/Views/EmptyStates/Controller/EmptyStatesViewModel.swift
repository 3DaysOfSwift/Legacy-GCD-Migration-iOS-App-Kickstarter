import KsApi
import Prelude
import UIKit

public enum EmptyState: String {
  case activity
  case recommended
  case socialNoPledges = "social_no_pledges"
  case socialDisabled = "social_disabled"
  case starred
}

@MainActor
struct EmptyStatePresentation {
  let title: String
  let subtitle: String
  let buttonTitle: String
  let bottomInset: CGFloat

  init(state: EmptyState) {
    self.title = textForTitle(emptyState: state)
    self.subtitle = textForSubtitle(emptyState: state)
    self.buttonTitle = buttonText(emptyState: state)
    self.bottomInset = Styles.grid(5)
  }
}

enum EmptyStateDestination {
  case discovery(DiscoveryParams?)
  case friends
}

@MainActor
final class EmptyStatesViewModel {
  private var emptyState: EmptyState?
  private var hasAppeared = false

  func configureWith(emptyState: EmptyState?) {
    if let emptyState { self.emptyState = emptyState }
  }

  func setEmptyState(_ emptyState: EmptyState) -> EmptyStatePresentation? {
    self.emptyState = emptyState
    return self.presentation
  }

  func viewWillAppear() -> EmptyStatePresentation? {
    guard !self.hasAppeared else { return nil }
    self.hasAppeared = true
    return self.presentation
  }

  func mainButtonTapped() -> EmptyStateDestination? {
    AppEnvironment.current.ksrAnalytics.trackExploreButtonClicked()
    guard self.hasAppeared, let emptyState = self.emptyState else { return nil }
    switch emptyState {
    case .socialDisabled, .socialNoPledges:
      return .friends
    case .activity:
      return .discovery(nil)
    case .recommended, .starred:
      return .discovery(DiscoveryParams.defaults |> DiscoveryParams.lens.sort .~ .magic)
    }
  }

  private var presentation: EmptyStatePresentation? {
    guard self.hasAppeared, let emptyState = self.emptyState else { return nil }
    return EmptyStatePresentation(state: emptyState)
  }
}

private func textForSubtitle(emptyState: EmptyState) -> String {
  switch emptyState {
  case .activity:
    return Strings.Find_projects_youll_love_in_art_design_film()
  case .socialDisabled:
    return Strings.Follow_your_Facebook_friends_and_keep_up_with_the_projects()
  case .socialNoPledges:
    return Strings.Your_friends_havent_backed_any_projects_yet()
  case .recommended:
    return Strings.Once_you_back_a_project_well_share()
  case .starred:
    return Strings.Tap_the_star_on_each_project_page_to_save_it()
  }
}

private func textForTitle(emptyState: EmptyState) -> String {
  switch emptyState {
  case .activity:
    return Strings.Bring_creative_projects_to_life()
  case .socialDisabled:
    return Strings.Its_better_with_friends()
  case .socialNoPledges:
    return Strings.No_pledges_from_friends_yet()
  case .recommended:
    return Strings.Just_for_you()
  case .starred:
    return Strings.Something_catch_your_eye()
  }
}

private func buttonText(emptyState: EmptyState) -> String {
  switch emptyState {
  case .socialDisabled:
    return Strings.Find_and_follow_friends()
  case .socialNoPledges:
    return Strings.Follow_more_friends()
  case .activity, .recommended, .starred:
    return Strings.Explore_projects()
  }
}
