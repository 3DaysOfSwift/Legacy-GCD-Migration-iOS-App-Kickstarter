import Apollo
import GraphAPI

extension Service {
  @MainActor public func recordProjectAttribution(input: GraphAPI.CreateAttributionEventInput) async throws {
    let _: Void = try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CreateAttributionEventMutation(input: input),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: { _ in () })
  }

  @MainActor public func rewardAddOns(slug: String, locationID: String?) async throws -> [Reward]? {
    try await self.cancellableQuery(GraphAPI.FetchAddOnsQuery(
      projectSlug: slug, shippingEnabled: locationID != nil, locationId: .someOrNil(locationID)), map: { data in
        guard let project = Project.project(from: data) else { throw ErrorEnvelope.couldNotParseJSON }
        return project.rewardData.addOns
      })
  }
  @MainActor public func fastRewardAddOns(baseRewardID: Int, country: String) async throws -> [Reward] {
    guard let code = GraphAPI.CountryCode(rawValue: country) else {
      throw ErrorEnvelope.graphError("Invalid country code")
    }
    return try await self.cancellableQuery(GraphAPI.FastFetchAddOnsQuery(
      baseRewardId: "\(baseRewardID)", country: .case(code)), map: { data in
        guard let rewards = Reward.addOns(from: data) else { throw ErrorEnvelope.couldNotParseJSON }
        return rewards
      })
  }

  @MainActor public func shippingLocations(projectID: Int) async throws -> [Location] {
    try await self.cancellableQuery(GraphAPI.ShippableLocationsForProjectQuery(id: projectID),
      map: { Location.locations(from: $0) })
  }

  @MainActor public func sortedProjectRewards(
    projectID: Int, country: String?, inserter: any NoRewardInserter
  ) async throws -> [Reward] {
    let rewards = try await self.cancellableQuery(GraphAPI.FetchSortedProjectRewardsByIdQuery(
      projectId: projectID,
      location: GraphQLEnum.caseOrNil(country.flatMap(GraphAPI.CountryCode.init(rawValue:)))
    ), map: { SortedProjectRewardsResponse($0) })
    // The insertion policy belongs to the caller's actor, not the network callback.
    guard let noReward = rewards.noReward else { return [] }
    return inserter.insert(noReward: noReward, intoRewards: rewards.rewards)
  }

  @MainActor public func relatedProjects(projectID: String) async throws -> [ProjectCardResponse] {
    try await self.cancellableQuery(GraphAPI.FetchSimilarProjectsQuery(projectID: projectID), map: { data in
      (data.projects?.nodes ?? []).compactMap { $0 }.map { ProjectCardResponse($0.fragments.projectCardFragment) }
    })
  }

  @MainActor public func projectDetails(param: Param, includeStoryRichText: Bool) async throws -> Project
    .ProjectPamphletData {
    try await self.cancellableQuery(GraphAPI.FetchProjectByParamQuery(
      projectId: .someOrNil(param.id), slug: .someOrNil(param.slug), storyRichText: includeStoryRichText
    ), map: { data in
      let (project, backingID) = Project.project(from: data)
      guard let project else { throw ErrorEnvelope.couldNotParseJSON }
      return Project.ProjectPamphletData(project: project, backingId: backingID)
    })
  }

  @MainActor public func projectDetailsBacking(id: Int) async throws -> ProjectAndBackingEnvelope {
    try await self.cancellableQuery(GraphAPI.FetchBackingQuery(id: "\(id)"), map: { data in
      guard let envelope = ProjectAndBackingEnvelope.envelope(from: data)
      else { throw ErrorEnvelope.couldNotParseJSON }
      return envelope
    })
  }

  @MainActor public func projectDetailsRewards(projectID: Int) async throws -> [Reward] {
    try await self.cancellableQuery(GraphAPI.FetchProjectRewardsByIdQuery(
      projectId: projectID, includeShippingRules: true, includePledgeOverTime: false
    ), map: { Project.projectRewards(from: $0) })
  }

  @MainActor public func projectDetailsBase(param: Param) async throws -> Project {
    try await self.cancellableQuery(GraphAPI.FastFetchProjectPageBaseQuery(
      projectId: .someOrNil(param.id), slug: .someOrNil(param.slug)
    ), map: { data in
      guard let project = Project.project(from: data) else { throw ErrorEnvelope.couldNotParseJSON }
      return project
    })
  }

  @MainActor public func projectDetailsExtras(
    param: Param,
    includeStoryRichText: Bool
  ) async throws -> ProjectPageExtraProperties {
    try await self.cancellableQuery(GraphAPI.FastFetchProjectPageExtendedPropertiesQuery(
      projectId: .someOrNil(param.id), slug: .someOrNil(param.slug), storyRichText: includeStoryRichText
    ), map: { data in
      guard let extras = ProjectPageExtraProperties.extraProperties(from: data)
      else { throw ErrorEnvelope.couldNotParseJSON }
      return extras
    })
  }

  @MainActor public func enrollProjectSecretReward(token: String, param: Param) async throws {
    let input = GraphAPI.AddUserToSecretRewardGroupInput.from(token: token, forProject: param)
    let _: Void = try await CancellableGraphQLRequest
      .fetch(start: { completion in
        GraphQL.shared.client.perform(
          mutation: GraphAPI.AddUserToSecretRewardGroupMutation(input: input),
          queue: .global(qos: .userInitiated), resultHandler: completion
        )
      }, map: { _ in () })
  }

  @MainActor func cancellableQuery<Query: GraphQLQuery, Value: Sendable>(
    _ query: Query, map: @escaping @Sendable (Query.Data) throws -> Value
  ) async throws -> Value {
    try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.fetch(
        query: query, cachePolicy: .fetchIgnoringCacheCompletely,
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: map)
  }

}
