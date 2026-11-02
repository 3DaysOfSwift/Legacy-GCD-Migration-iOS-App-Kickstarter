import GraphAPI

extension Service {
  @MainActor public func recommendationCategory(id: String) async throws -> Category {
    try await self.cancellableQuery(GraphAPI.FetchCategoryQuery(id: id), map: { data in
      guard let envelope = CategoryEnvelope.envelope(from: data) else {
        throw ErrorEnvelope.couldNotParseJSON
      }
      return envelope.node
    })
  }
}
