/// Composition root for migrated features. Other tabs remain on their legacy
/// owners until their own migration checkpoint.
@MainActor
public final class AppModel {
  public static let shared = AppModel.live()

  public let friendsFeature: FriendsFeature
  public let pledgedProjectsFeature: PledgedProjectsFeature
  public let pledgeFeature: PledgeFeature
  public let paymentsFeature: PaymentsFeature
  public let messagingFeature: MessagingFeature
  public let sessionFeature: SessionFeature
  public let authenticationFeature: AuthenticationFeature
  public let settingsFeature: SettingsFeature
  public let activityFeature: ActivityFeature
  public let profileFeature: ProfileFeature
  public let searchFeature: SearchFeature
  public let discoveryFeature: DiscoveryFeature
  public let projectDetailsFeature: ProjectDetailsFeature
  public let rewardsFeature: RewardsFeature
  public let discussionFeature: DiscussionFeature
  public let projectMediaFeature: ProjectMediaFeature

  public init(
    friendsFeature: FriendsFeature,
    pledgedProjectsFeature: PledgedProjectsFeature,
    pledgeFeature: PledgeFeature,
    paymentsFeature: PaymentsFeature,
    messagingFeature: MessagingFeature,
    sessionFeature: SessionFeature,
    authenticationFeature: AuthenticationFeature,
    settingsFeature: SettingsFeature,
    activityFeature: ActivityFeature,
    profileFeature: ProfileFeature,
    searchFeature: SearchFeature,
    discoveryFeature: DiscoveryFeature,
    projectDetailsFeature: ProjectDetailsFeature,
    rewardsFeature: RewardsFeature,
    discussionFeature: DiscussionFeature,
    projectMediaFeature: ProjectMediaFeature
  ) {
    self.friendsFeature = friendsFeature
    self.pledgedProjectsFeature = pledgedProjectsFeature
    self.pledgeFeature = pledgeFeature
    self.paymentsFeature = paymentsFeature
    self.messagingFeature = messagingFeature
    self.sessionFeature = sessionFeature
    self.authenticationFeature = authenticationFeature
    self.settingsFeature = settingsFeature
    self.activityFeature = activityFeature
    self.profileFeature = profileFeature
    self.searchFeature = searchFeature
    self.discoveryFeature = discoveryFeature
    self.projectDetailsFeature = projectDetailsFeature
    self.rewardsFeature = rewardsFeature
    self.discussionFeature = discussionFeature
    self.projectMediaFeature = projectMediaFeature
  }

  public func sessionChanged() {
    self.sessionFeature.sessionChanged()
    self.friendsFeature.reset()
    self.activityFeature.reset()
    self.profileFeature.reset()
    self.messagingFeature.reset()
    self.paymentsFeature.reset()
    self.pledgeFeature.reset()
    self.pledgedProjectsFeature.reset()
  }

  public static func live() -> AppModel {
    let searchProvider = AsyncSearchProjectsProvider()
    let sessionFeature =
      SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) })
    let activityFeature = ActivityFeature(
      sessionFeature: sessionFeature,
      makeProvider: { AsyncActivityProvider(service: AppEnvironment.current.apiService) }
    )
    let profileFeature = ProfileFeature(
      sessionFeature: sessionFeature,
      makeProvider: { AsyncProfileProvider(service: AppEnvironment.current.apiService) }
    )
    return AppModel(
      friendsFeature: FriendsFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncFriendsProvider(service: AppEnvironment.current.apiService)
      }),
      pledgedProjectsFeature: PledgedProjectsFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncPledgedProjectsProvider(service: AppEnvironment.current.apiService)
      }),
      pledgeFeature: PledgeFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncPledgeProvider(service: AppEnvironment.current.apiService)
      }),
      paymentsFeature: PaymentsFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncPaymentsProvider(service: AppEnvironment.current.apiService)
      }),
      messagingFeature: MessagingFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncMessagingProvider(service: AppEnvironment.current.apiService)
      }),
      sessionFeature: sessionFeature,
      authenticationFeature: AuthenticationFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncAuthenticationProvider(service: AppEnvironment.current.apiService)
      }),
      settingsFeature: SettingsFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService)
      }),
      activityFeature: activityFeature,
      profileFeature: profileFeature,
      searchFeature: SearchFeature(provider: searchProvider, lookupProvider: AsyncSearchLookupProvider()),
      discoveryFeature: DiscoveryFeature(provider: AsyncDiscoveryProvider()),
      projectDetailsFeature: ProjectDetailsFeature(makeProvider: {
        AsyncProjectDetailsProvider(service: AppEnvironment.current.apiService)
      }),
      rewardsFeature: RewardsFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncRewardsProvider(service: AppEnvironment.current.apiService)
      }),
      discussionFeature: DiscussionFeature(makeProvider: {
        AsyncDiscussionProvider(service: AppEnvironment.current.apiService)
      }),
      projectMediaFeature: ProjectMediaFeature(makeProvider: {
        AsyncProjectMediaProvider(service: AppEnvironment.current.apiService)
      })
    )
  }
}
