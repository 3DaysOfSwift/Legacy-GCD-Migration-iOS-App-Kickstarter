/// Composition root for migrated features. Other tabs remain on their legacy
/// owners until their own migration checkpoint.
@MainActor
public final class AppModel {
  public static let shared = AppModel.live()

  public let searchFeature: SearchFeature
  public let discoveryFeature: DiscoveryFeature
  public let projectDetailsFeature: ProjectDetailsFeature
  public let rewardsFeature: RewardsFeature
  public let discussionFeature: DiscussionFeature
  public let projectMediaFeature: ProjectMediaFeature

  public init(
    searchFeature: SearchFeature,
    discoveryFeature: DiscoveryFeature,
    projectDetailsFeature: ProjectDetailsFeature,
    rewardsFeature: RewardsFeature,
    discussionFeature: DiscussionFeature,
    projectMediaFeature: ProjectMediaFeature
  ) {
    self.searchFeature = searchFeature
    self.discoveryFeature = discoveryFeature
    self.projectDetailsFeature = projectDetailsFeature
    self.rewardsFeature = rewardsFeature
    self.discussionFeature = discussionFeature
    self.projectMediaFeature = projectMediaFeature
  }

  public static func live() -> AppModel {
    let searchProvider = AsyncSearchProjectsProvider()
    return AppModel(
      searchFeature: SearchFeature(provider: searchProvider, lookupProvider: AsyncSearchLookupProvider()),
      discoveryFeature: DiscoveryFeature(provider: AsyncDiscoveryProvider()),
      projectDetailsFeature: ProjectDetailsFeature(makeProvider: {
        AsyncProjectDetailsProvider(service: AppEnvironment.current.apiService)
      }),
      rewardsFeature: RewardsFeature(makeProvider: {
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
