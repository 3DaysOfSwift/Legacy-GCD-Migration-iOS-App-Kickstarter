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
  @MainActor public func fetchSearchCategories() async throws -> RootCategoriesEnvelope {
    try Task.checkCancellation()
    let response = try await self.fetch(query: GraphAPI.FetchRootCategoriesQuery())
    try Task.checkCancellation()
    guard let response else { throw ErrorEnvelope.couldNotParseJSON }
    return RootCategoriesEnvelope.envelope(from: response)
  }

  @MainActor public func fetchSearchDefaultLocations() async throws -> [Location] {
    try Task.checkCancellation()
    let response = try await self.fetch(query: GraphAPI.DefaultLocationsQuery(first: 5))
    try Task.checkCancellation()
    guard let response else { throw ErrorEnvelope.couldNotParseJSON }
    return Location.locations(from: response)
  }

  @MainActor public func fetchSearchLocations(term: String) async throws -> [Location] {
    try Task.checkCancellation()
    let response = try await self.fetch(query: GraphAPI.LocationsByTermQuery(term: .some(term), first: 10))
    try Task.checkCancellation()
    guard let response else { throw ErrorEnvelope.couldNotParseJSON }
    return Location.locations(from: response)
  }
}
