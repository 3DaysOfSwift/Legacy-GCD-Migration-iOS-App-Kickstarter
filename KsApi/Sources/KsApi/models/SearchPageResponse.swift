import GraphAPI

public struct SearchPageResponse: Sendable {
  public let projects: [SearchProjectResponse]
  public let hasNextPage: Bool
  public let endCursor: String?
  public let totalCount: Int

  public init(_ data: GraphAPI.SearchQuery.Data) {
    self.projects = data.projects?.nodes?.compactMap { $0 }.map(SearchProjectResponse.init) ?? []
    self.hasNextPage = data.projects?.pageInfo.hasNextPage == true
    self.endCursor = data.projects?.pageInfo.endCursor
    self.totalCount = data.projects?.totalCount ?? 0
  }
}

/// Preserve the existing ID-only equality used to suppress duplicate Search deliveries.
public struct SearchProjectResponse: Sendable, Equatable {
  public let id: String
  public let card: ProjectCardResponse
  public let analytics: ProjectAnalyticsSnapshot

  public init(_ node: GraphAPI.SearchQuery.Data.Projects.Node) {
    self.id = node.fragments.backerDashboardProjectCellFragment.projectId
    self.card = ProjectCardResponse(node.fragments.projectCardFragment)
    self.analytics = ProjectAnalyticsSnapshot(node.fragments.projectAnalyticsFragment)
  }

  public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
