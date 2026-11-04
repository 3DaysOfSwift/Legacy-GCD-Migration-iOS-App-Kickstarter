import Observation

@MainActor @Observable
public final class ProjectRisksCellViewModel {
  public init() {}
  public private(set) var descriptionLabelText: String?

  public func configureWith(value: String) {
    self.descriptionLabelText = value
  }
}
