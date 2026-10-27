/// Composition root for migrated features. Other tabs remain on their legacy
/// owners until their own migration checkpoint.
@MainActor
public final class AppModel {
  public static let shared = AppModel.live()

  public let searchFeature: SearchFeature
  public let discoveryFeature: DiscoveryFeature
  public let projectDetailsFeature: ProjectDetailsFeature

  public init(searchFeature: SearchFeature, discoveryFeature: DiscoveryFeature, projectDetailsFeature: ProjectDetailsFeature) {
    self.searchFeature = searchFeature
    self.discoveryFeature = discoveryFeature
    self.projectDetailsFeature = projectDetailsFeature
  }

  public static func live() -> AppModel {
    let searchProvider = AsyncSearchProjectsProvider()
    return AppModel(
      searchFeature: SearchFeature(provider: searchProvider, lookupProvider: AsyncSearchLookupProvider()),
      discoveryFeature: DiscoveryFeature(provider: AsyncDiscoveryProvider()),
      projectDetailsFeature: ProjectDetailsFeature(makeProvider: {
        AsyncProjectDetailsProvider(service: AppEnvironment.current.apiService)
      })
    )
  }
}
