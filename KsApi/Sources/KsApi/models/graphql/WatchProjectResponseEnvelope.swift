import Foundation

public struct WatchProjectResponseEnvelope: Decodable, Sendable {
  public var watchProject: WatchProject

  public struct WatchProject: Decodable, Sendable {
    public var project: Project

    public struct Project: Decodable, Sendable {
      public var id: String
      public var isWatched: Bool
      public var watchesCount: Int
    }
  }
}
