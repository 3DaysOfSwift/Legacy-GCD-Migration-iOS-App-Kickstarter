import Apollo
import GraphAPI

extension Service {
  @MainActor public func submitPledge(_ input: CreateBackingInput) async throws -> CreateBackingEnvelope {
    let data: GraphAPI.CreateBackingMutation.Data = try await CancellableGraphQLRequest.fetch { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CreateBackingMutation(input: GraphAPI.CreateBackingInput.from(input)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }
    guard let envelope = CreateBackingEnvelope.from(data) else { throw ErrorEnvelope.couldNotParseJSON }
    return envelope
  }

  @MainActor public func revisePledge(_ input: UpdateBackingInput) async throws -> UpdateBackingEnvelope {
    let data: GraphAPI.UpdateBackingMutation.Data = try await CancellableGraphQLRequest.fetch { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.UpdateBackingMutation(input: GraphAPI.UpdateBackingInput.from(input)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }
    guard let envelope = UpdateBackingEnvelope.from(data) else { throw ErrorEnvelope.couldNotParseJSON }
    return envelope
  }

  @MainActor public func cancelPledge(_ input: CancelBackingInput) async throws {
    // Preserve the current GraphQL contract: only the backing ID is transmitted.
    // The legacy client does not transmit its optional cancellation note.
    let _: GraphAPI.CancelBackingMutation.Data = try await CancellableGraphQLRequest.fetch { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CancelBackingMutation(input: GraphAPI.CancelBackingInput(id: input.backingId)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }
  }
}
