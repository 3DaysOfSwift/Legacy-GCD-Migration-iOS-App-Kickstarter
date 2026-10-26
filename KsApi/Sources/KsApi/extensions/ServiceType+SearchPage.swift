import GraphAPI

extension ServiceType {
  /// Local/mock services use their existing async fixtures. Production Service
  /// overrides this protocol requirement with the cancellable Apollo bridge.
  @MainActor public func fetchSearchPage(query: GraphAPI.SearchQuery) async throws -> GraphAPI.SearchQuery.Data {
    try Task.checkCancellation()
    let response = try await self.fetch(query: query)
    try Task.checkCancellation()
    guard let response else { throw ErrorEnvelope.couldNotParseJSON }
    return response
  }
}
