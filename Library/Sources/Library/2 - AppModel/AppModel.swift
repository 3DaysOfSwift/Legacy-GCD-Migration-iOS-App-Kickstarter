/// Composition root for migrated features. Other tabs remain on their legacy
/// owners until their own migration checkpoint.
@MainActor
public final class AppModel {
  public static let shared = AppModel.live()

  public let searchFeature: SearchFeature

  public init(searchFeature: SearchFeature) {
    self.searchFeature = searchFeature
  }

  public static func live() -> AppModel {
    let searchProvider = AsyncSearchProjectsProvider()
    return AppModel(searchFeature: SearchFeature(provider: searchProvider))
  }
}
