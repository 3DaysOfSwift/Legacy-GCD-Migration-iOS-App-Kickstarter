import Apollo
import GraphAPI

extension Service {
  @MainActor public func shippingLocations(projectID: Int) async throws -> [Location] {
    let data = try await self.cancellableQuery(GraphAPI.ShippableLocationsForProjectQuery(id: projectID))
    return Location.locations(from: data)
  }

  @MainActor public func sortedProjectRewards(
    projectID: Int, country: String?, inserter: any NoRewardInserter
  ) async throws -> [Reward] {
    let data = try await self.cancellableQuery(GraphAPI.FetchSortedProjectRewardsByIdQuery(
      projectId: projectID,
      location: GraphQLEnum.caseOrNil(country.flatMap(GraphAPI.CountryCode.init(rawValue:)))
    ))
    return Project.projectRewards(from: data, withNoReward: inserter)
  }

  @MainActor public func relatedProjects(projectID: String) async throws -> GraphAPI.FetchSimilarProjectsQuery
    .Data {
    try await self.cancellableQuery(GraphAPI.FetchSimilarProjectsQuery(projectID: projectID))
  }

  @MainActor public func projectDetails(param: Param, includeStoryRichText: Bool) async throws -> Project
    .ProjectPamphletData {
    let data = try await self.cancellableQuery(GraphAPI.FetchProjectByParamQuery(
      projectId: .someOrNil(param.id), slug: .someOrNil(param.slug), storyRichText: includeStoryRichText
    ))
    let (project, backingID) = Project.project(from: data)
    guard let project else { throw ErrorEnvelope.couldNotParseJSON }
    return Project.ProjectPamphletData(project: project, backingId: backingID)
  }

  @MainActor public func projectDetailsBacking(id: Int) async throws -> ProjectAndBackingEnvelope {
    let data = try await self.cancellableQuery(GraphAPI.FetchBackingQuery(id: "\(id)"))
    guard let envelope = ProjectAndBackingEnvelope.envelope(from: data)
    else { throw ErrorEnvelope.couldNotParseJSON }
    return envelope
  }

  @MainActor public func projectDetailsRewards(projectID: Int) async throws -> [Reward] {
    let data = try await self.cancellableQuery(GraphAPI.FetchProjectRewardsByIdQuery(
      projectId: projectID, includeShippingRules: true, includePledgeOverTime: false
    ))
    return Project.projectRewards(from: data)
  }

  @MainActor public func projectDetailsBase(param: Param) async throws -> Project {
    let data = try await self.cancellableQuery(GraphAPI.FastFetchProjectPageBaseQuery(
      projectId: .someOrNil(param.id), slug: .someOrNil(param.slug)
    ))
    guard let project = Project.project(from: data) else { throw ErrorEnvelope.couldNotParseJSON }
    return project
  }

  @MainActor public func projectDetailsExtras(
    param: Param,
    includeStoryRichText: Bool
  ) async throws -> ProjectPageExtraProperties {
    let data = try await self.cancellableQuery(GraphAPI.FastFetchProjectPageExtendedPropertiesQuery(
      projectId: .someOrNil(param.id), slug: .someOrNil(param.slug), storyRichText: includeStoryRichText
    ))
    guard let extras = ProjectPageExtraProperties.extraProperties(from: data)
    else { throw ErrorEnvelope.couldNotParseJSON }
    return extras
  }

  @MainActor public func enrollProjectSecretReward(token: String, param: Param) async throws {
    let input = GraphAPI.AddUserToSecretRewardGroupInput.from(token: token, forProject: param)
    let _: GraphAPI.AddUserToSecretRewardGroupMutation.Data = try await CancellableGraphQLRequest
      .fetch { completion in
        GraphQL.shared.client.perform(
          mutation: GraphAPI.AddUserToSecretRewardGroupMutation(input: input),
          queue: .global(qos: .userInitiated), resultHandler: completion
        )
      }
  }

  @MainActor func cancellableQuery<Query: GraphQLQuery>(_ query: Query) async throws -> Query
    .Data {
    try await CancellableGraphQLRequest.fetch { completion in
      GraphQL.shared.client.fetch(
        query: query, cachePolicy: .fetchIgnoringCacheCompletely,
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }
  }
}
