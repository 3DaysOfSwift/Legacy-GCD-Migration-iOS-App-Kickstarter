import GraphAPI

/// Pagination values detached from generated GraphQL storage.
public struct ProfileProjectsResponse: Sendable {
  public let projects: [ProjectCardResponse]
  public let cursor: String?

  public init(_ data: GraphAPI.FetchMyBackedProjectsQuery.Data) {
    self.projects = data.projects?.nodes?.compactMap { $0?.fragments.projectCardFragment }
      .map(ProjectCardResponse.init) ?? []
    self.cursor = data.projects?.pageInfo.hasNextPage == true ? data.projects?.pageInfo.endCursor : nil
  }

  public init(_ data: GraphAPI.FetchMySavedProjectsQuery.Data) {
    self.projects = data.projects?.nodes?.compactMap { $0?.fragments.projectCardFragment }
      .map(ProjectCardResponse.init) ?? []
    self.cursor = data.projects?.pageInfo.hasNextPage == true ? data.projects?.pageInfo.endCursor : nil
  }
}
