import Apollo
import GraphAPI

extension Service {
  @MainActor public func paymentCards() async throws -> UserEnvelope<GraphUser> {
    let data = try await self.cancellableQuery(GraphAPI.FetchUserQuery(withStoredCards: true))
    guard let envelope = UserEnvelope<GraphUser>.userEnvelope(from: data) else {
      throw ErrorEnvelope.couldNotParseJSON
    }
    return envelope
  }

  @MainActor public func removePaymentMethod(id: String) async throws -> DeletePaymentMethodEnvelope {
    let data: GraphAPI.DeletePaymentSourceMutation.Data = try await CancellableGraphQLRequest.fetch { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.DeletePaymentSourceMutation(input: GraphAPI.PaymentSourceDeleteInput.from(
          PaymentSourceDeleteInput(paymentSourceId: id)
        )), queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }
    guard let envelope = DeletePaymentMethodEnvelope.from(data) else { throw ErrorEnvelope.couldNotParseJSON }
    return envelope
  }

  @MainActor public func storePaymentMethod(secret: String) async throws -> CreatePaymentSourceEnvelope {
    let data: GraphAPI.CreatePaymentSourceMutation.Data = try await CancellableGraphQLRequest.fetch { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CreatePaymentSourceMutation(input: GraphAPI.CreatePaymentSourceInput.from(
          CreatePaymentSourceSetupIntentInput(intentClientSecret: secret, reuseable: true)
        )), queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }
    guard let envelope = CreatePaymentSourceEnvelope.from(data) else { throw ErrorEnvelope.couldNotParseJSON }
    return envelope
  }

  @MainActor public func paymentSetupIntent(input: CreateSetupIntentInput) async throws -> ClientSecretEnvelope {
    let data: GraphAPI.CreateSetupIntentMutation.Data = try await CancellableGraphQLRequest.fetch { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CreateSetupIntentMutation(input: GraphAPI.CreateSetupIntentInput.from(input)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }
    guard let envelope = ClientSecretEnvelope.clientSecretEnvelope(from: data) else {
      throw ErrorEnvelope.couldNotParseJSON
    }
    return envelope
  }

  @MainActor public func paymentIntent(input: CreatePaymentIntentInput) async throws -> PaymentIntentEnvelope {
    let data: GraphAPI.CreatePaymentIntentMutation.Data = try await CancellableGraphQLRequest.fetch { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CreatePaymentIntentMutation(input: GraphAPI.CreatePaymentIntentInput(
          projectId: input.projectId,
          amount: input.amountDollars,
          paymentIntentContext: GraphQLEnum.caseOrNil(input.paymentIntentContext),
          digitalMarketingAttributed: GraphQLNullable.someOrNil(input.digitalMarketingAttributed),
          checkoutId: GraphQLNullable.someOrNil(input.checkoutId)
        )), queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }
    guard let envelope = PaymentIntentEnvelope.clientSecretEnvelope(from: data) else {
      throw ErrorEnvelope.couldNotParseJSON
    }
    return envelope
  }
}
