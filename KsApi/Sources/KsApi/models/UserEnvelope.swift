import Foundation
import GraphAPI

public struct UserEnvelope<T: Decodable>: Decodable {
  public let me: T
}

// Only reviewed transferable payloads may cross task boundaries.
extension UserEnvelope: Sendable where T: Sendable {}

// MARK: - GraphQL Adapters
