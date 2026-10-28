import GraphAPI

extension Service {
  @MainActor public func reportingEmail() async throws -> String? {
    let data = try await self.cancellableQuery(GraphAPI.FetchUserEmailQuery())
    guard let envelope = UserEnvelope<GraphUserEmail>.userEnvelope(from: data) else {
      throw ErrorEnvelope.couldNotParseJSON
    }
    return envelope.me.email
  }

  @MainActor public func submitProjectReport(input: CreateFlaggingInput) async throws {
    let _: GraphAPI.CreateFlaggingMutation.Data = try await CancellableGraphQLRequest.fetch { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CreateFlaggingMutation(input: GraphAPI.CreateFlaggingInput.from(input)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }
  }
}
