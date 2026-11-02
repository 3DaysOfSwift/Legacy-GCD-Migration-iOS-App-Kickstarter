import Foundation

/// Session setup transfers feature names, never generated GraphQL enum storage.
public struct GraphUserSetup: Decodable, Equatable, Sendable {
  public var email: String?
  private var enabledFeatureNames: Set<String>
  public var enabledFeatures: Set<ServerFeature> {
    get { Set(self.enabledFeatureNames.compactMap(ServerFeature.init(rawValue:))) }
    set { self.enabledFeatureNames = Set(newValue.map(\.rawValue)) }
  }
  public var ppoHasAction: Bool?
  public var backingActionCount: Int?

  public init(
    email: String?, enabledFeatures: Set<ServerFeature>, ppoHasAction: Bool?, backingActionCount: Int?
  ) {
    self.email = email
    self.enabledFeatureNames = Set(enabledFeatures.map(\.rawValue))
    self.ppoHasAction = ppoHasAction
    self.backingActionCount = backingActionCount
  }

  private enum CodingKeys: String, CodingKey {
    case email, enabledFeatures, ppoHasAction, backingActionCount
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      email: try values.decodeIfPresent(String.self, forKey: .email),
      enabledFeatures: try values.decode(Set<ServerFeature>.self, forKey: .enabledFeatures),
      ppoHasAction: try values.decodeIfPresent(Bool.self, forKey: .ppoHasAction),
      backingActionCount: try values.decodeIfPresent(Int.self, forKey: .backingActionCount)
    )
  }
}
