import GraphAPI

extension Service {
  @MainActor public func reportingEmail() async throws -> String? {
    try await self.cancellableQuery(GraphAPI.FetchUserEmailQuery(), map: { data in
      guard let envelope = UserEnvelope<GraphUserEmail>.userEnvelope(from: data) else {
        throw ErrorEnvelope.couldNotParseJSON
      }
      return envelope.me.email
    })
  }

  @MainActor public func submitProjectReport(input: CreateFlaggingInput) async throws {
    let _: Void = try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CreateFlaggingMutation(input: GraphAPI.CreateFlaggingInput.from(input)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: { _ in () })
  }
}
