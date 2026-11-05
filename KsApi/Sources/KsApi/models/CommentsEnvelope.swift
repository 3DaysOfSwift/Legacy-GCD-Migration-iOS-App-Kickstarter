import Foundation
import GraphAPI

public struct CommentsEnvelope: Decodable, Sendable {
  public var comments: [Comment]
  public var cursor: String?
  public var hasNextPage: Bool
  public var slug: String?
  public var totalCount: Int
  public var updateID: String?
}
