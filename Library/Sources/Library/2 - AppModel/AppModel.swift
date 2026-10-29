/// Composition root for migrated features. Other tabs remain on their legacy
/// owners until their own migration checkpoint.
@MainActor
public final class AppModel {
  public static let shared = AppModel.live()

  public let developerExamplesFeature: DeveloperExamplesFeature
  public let appLifecycleFeature: AppLifecycleFeature
  public let creatorDraftsFeature: CreatorDraftsFeature
  public let recommendationsFeature: RecommendationsFeature
  public let projectReportingFeature: ProjectReportingFeature
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
    developerExamplesFeature: DeveloperExamplesFeature,
    appLifecycleFeature: AppLifecycleFeature,
    creatorDraftsFeature: CreatorDraftsFeature,
    recommendationsFeature: RecommendationsFeature,
    projectReportingFeature: ProjectReportingFeature,
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
    self.developerExamplesFeature = developerExamplesFeature
    self.appLifecycleFeature = appLifecycleFeature
    self.creatorDraftsFeature = creatorDraftsFeature
    self.recommendationsFeature = recommendationsFeature
    self.projectReportingFeature = projectReportingFeature
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
    self.developerExamplesFeature.reset()
    self.appLifecycleFeature.reset()
    self.creatorDraftsFeature.reset()
    self.recommendationsFeature.reset()
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
    let settingsFeature = SettingsFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService)
      })
    let messagingFeature = MessagingFeature(sessionFeature: sessionFeature, makeProvider: {
      AsyncMessagingProvider(service: AppEnvironment.current.apiService)
    })
    let discussionFeature = DiscussionFeature(sessionFeature: sessionFeature, makeProvider: {
      AsyncDiscussionProvider(service: AppEnvironment.current.apiService)
    })
    return AppModel(
      developerExamplesFeature: DeveloperExamplesFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncDeveloperExamplesProvider(service: AppEnvironment.current.apiService)
      }),
      appLifecycleFeature: AppLifecycleFeature(sessionFeature: sessionFeature, settingsFeature: settingsFeature,
        messagingFeature: messagingFeature, makeProvider: { AsyncAppLifecycleProvider(service: AppEnvironment.current.apiService) }),
      creatorDraftsFeature: CreatorDraftsFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncCreatorDraftsProvider(service: AppEnvironment.current.apiService)
      }),
      recommendationsFeature: RecommendationsFeature(settingsFeature: settingsFeature, makeProvider: {
        AsyncRecommendationsProvider(service: AppEnvironment.current.apiService)
      }),
      projectReportingFeature: ProjectReportingFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncProjectReportingProvider(service: AppEnvironment.current.apiService)
      }),
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
      messagingFeature: messagingFeature,
      sessionFeature: sessionFeature,
      authenticationFeature: AuthenticationFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncAuthenticationProvider(service: AppEnvironment.current.apiService)
      }),
      settingsFeature: settingsFeature,
      activityFeature: activityFeature,
      profileFeature: profileFeature,
      searchFeature: SearchFeature(provider: searchProvider, lookupProvider: AsyncSearchLookupProvider()),
      discoveryFeature: DiscoveryFeature(provider: AsyncDiscoveryProvider()),
      projectDetailsFeature: ProjectDetailsFeature(sessionFeature: sessionFeature, discussionFeature: discussionFeature, makeProvider: {
        AsyncProjectDetailsProvider(service: AppEnvironment.current.apiService)
      }),
      rewardsFeature: RewardsFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncRewardsProvider(service: AppEnvironment.current.apiService)
      }),
      discussionFeature: discussionFeature,
      projectMediaFeature: ProjectMediaFeature(sessionFeature: sessionFeature, makeProvider: {
        AsyncProjectMediaProvider(service: AppEnvironment.current.apiService)
      })
    )
  }
}
