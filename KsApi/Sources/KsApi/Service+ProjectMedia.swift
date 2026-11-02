import GraphAPI

extension Service {
  @MainActor public func projectVideoFeed() async throws -> [VideoFeedResponse] {
    try await self.cancellableQuery(
      GraphAPI.VideoFeedQuery(first: 30, after: .none, categoryId: .none),
      map: { $0.videoFeed?.nodes?.compactMap { $0 }.map(VideoFeedResponse.init) ?? [] })
  }

  @MainActor public func setProjectWatched(
    id: String, watched: Bool
  ) async throws -> WatchProjectResponseEnvelope {
    let envelope: WatchProjectResponseEnvelope?
    if watched {
      envelope = try await CancellableGraphQLRequest.fetch(start: { completion in
        GraphQL.shared.client.perform(
          mutation: GraphAPI.WatchProjectMutation(input: GraphAPI.WatchProjectInput.from(.init(id: id))),
          queue: .global(qos: .userInitiated), resultHandler: completion
        )
      }, map: { WatchProjectResponseEnvelope.from($0) })
    } else {
      envelope = try await CancellableGraphQLRequest
        .fetch(start: { completion in
          GraphQL.shared.client.perform(
            mutation: GraphAPI
              .UnwatchProjectMutation(input: GraphAPI.UnwatchProjectInput.from(.init(id: id))),
            queue: .global(qos: .userInitiated), resultHandler: completion
          )
        }, map: { WatchProjectResponseEnvelope.from($0) })
    }
    guard let envelope else { throw ErrorEnvelope.couldNotParseJSON }
    return envelope
  }
}
