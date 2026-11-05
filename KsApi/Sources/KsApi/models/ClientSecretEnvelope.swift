import Foundation
import GraphAPI

public struct ClientSecretEnvelope: Decodable, Sendable {
  public let clientSecret: String
}
