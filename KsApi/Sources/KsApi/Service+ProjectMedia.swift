import GraphAPI

extension Service {
  @MainActor public func projectVideoFeed() async throws -> GraphAPI.VideoFeedQuery.Data {
    try await self.cancellableQuery(GraphAPI.VideoFeedQuery(first: 30, after: .none, categoryId: .none))
  }

  @MainActor public func setProjectWatched(
    id: String, watched: Bool
  ) async throws -> WatchProjectResponseEnvelope {
    let envelope: WatchProjectResponseEnvelope?
    if watched {
      let data: GraphAPI.WatchProjectMutation.Data = try await CancellableGraphQLRequest.fetch { completion in
        GraphQL.shared.client.perform(
          mutation: GraphAPI.WatchProjectMutation(input: GraphAPI.WatchProjectInput.from(.init(id: id))),
          queue: .global(qos: .userInitiated), resultHandler: completion
        )
      }
      envelope = WatchProjectResponseEnvelope.from(data)
    } else {
      let data: GraphAPI.UnwatchProjectMutation.Data = try await CancellableGraphQLRequest
        .fetch { completion in
          GraphQL.shared.client.perform(
            mutation: GraphAPI
              .UnwatchProjectMutation(input: GraphAPI.UnwatchProjectInput.from(.init(id: id))),
            queue: .global(qos: .userInitiated), resultHandler: completion
          )
        }
      envelope = WatchProjectResponseEnvelope.from(data)
    }
    guard let envelope else { throw ErrorEnvelope.couldNotParseJSON }
    return envelope
  }
}
