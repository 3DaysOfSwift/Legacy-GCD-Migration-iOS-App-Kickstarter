
import Foundation

public struct ProjectNotification: Sendable {
  public let email: Bool
  public let id: Int
  public let mobile: Bool
  public let project: Project

  public struct Project: Sendable {
    public let id: Int
    public let name: String
  }
}

extension ProjectNotification: Decodable {}

extension ProjectNotification.Project: Decodable {}

extension ProjectNotification: Equatable {}
public func == (lhs: ProjectNotification, rhs: ProjectNotification) -> Bool {
  return lhs.id == rhs.id
}

extension ProjectNotification.Project: Equatable {}
public func == (lhs: ProjectNotification.Project, rhs: ProjectNotification.Project) -> Bool {
  return lhs.id == rhs.id
}
