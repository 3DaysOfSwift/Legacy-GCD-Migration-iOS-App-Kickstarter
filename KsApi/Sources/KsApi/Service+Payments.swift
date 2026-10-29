import Apollo
import GraphAPI

extension Service {
  @MainActor public func paymentCards() async throws -> UserEnvelope<GraphUser> {
    try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.fetch(
        query: GraphAPI.FetchUserQuery(withStoredCards: true), cachePolicy: .fetchIgnoringCacheCompletely,
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: { data in
      guard let envelope = UserEnvelope<GraphUser>.userEnvelope(from: data) else {
        throw ErrorEnvelope.couldNotParseJSON
      }
      return envelope
    })
  }

  @MainActor public func removePaymentMethod(id: String) async throws -> DeletePaymentMethodEnvelope {
    try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.DeletePaymentSourceMutation(input: GraphAPI.PaymentSourceDeleteInput.from(
          PaymentSourceDeleteInput(paymentSourceId: id)
        )), queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: { data in
      guard let envelope = DeletePaymentMethodEnvelope.from(data) else { throw ErrorEnvelope.couldNotParseJSON }
      return envelope
    })
  }

  @MainActor public func storePaymentMethod(secret: String) async throws -> CreatePaymentSourceEnvelope {
    try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CreatePaymentSourceMutation(input: GraphAPI.CreatePaymentSourceInput.from(
          CreatePaymentSourceSetupIntentInput(intentClientSecret: secret, reuseable: true)
        )), queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: { data in
      guard let envelope = CreatePaymentSourceEnvelope.from(data) else { throw ErrorEnvelope.couldNotParseJSON }
      return envelope
    })
  }

  @MainActor public func paymentSetupIntent(input: CreateSetupIntentInput) async throws -> ClientSecretEnvelope {
    try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CreateSetupIntentMutation(input: GraphAPI.CreateSetupIntentInput.from(input)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: { data in
      guard let envelope = ClientSecretEnvelope.clientSecretEnvelope(from: data) else {
        throw ErrorEnvelope.couldNotParseJSON
      }
      return envelope
    })
  }

  @MainActor public func paymentIntent(input: CreatePaymentIntentInput) async throws -> PaymentIntentEnvelope {
    try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CreatePaymentIntentMutation(input: GraphAPI.CreatePaymentIntentInput(
          projectId: input.projectId,
          amount: input.amountDollars,
          paymentIntentContext: GraphQLEnum.caseOrNil(input.paymentIntentContext),
          digitalMarketingAttributed: GraphQLNullable.someOrNil(input.digitalMarketingAttributed),
          checkoutId: GraphQLNullable.someOrNil(input.checkoutId)
        )), queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: { data in
      guard let envelope = PaymentIntentEnvelope.clientSecretEnvelope(from: data) else {
        throw ErrorEnvelope.couldNotParseJSON
      }
      return envelope
    })
  }
}
