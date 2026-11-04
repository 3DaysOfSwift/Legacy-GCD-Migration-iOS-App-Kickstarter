import Observation

@MainActor @Observable
public final class DiscoveryProjectCategoryViewModel {
  public init() {}
  public private(set) var categoryNameText: String?
  public private(set) var categoryImageName: String?

  public func configureWith(name: String, imageNameString: String) {
    self.categoryNameText = name
    self.categoryImageName = imageNameString
  }
}
