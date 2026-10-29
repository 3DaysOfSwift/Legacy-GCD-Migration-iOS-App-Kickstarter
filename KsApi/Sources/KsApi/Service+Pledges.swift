import Apollo
import GraphAPI

extension Service {
  @MainActor public func submitPledge(_ input: CreateBackingInput) async throws
    -> CreateBackingEnvelope
  {
    try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CreateBackingMutation(input: GraphAPI.CreateBackingInput.from(input)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: { data in
      guard let envelope = CreateBackingEnvelope.from(data) else {
        throw ErrorEnvelope.couldNotParseJSON
      }
      return envelope
    })
  }

  @MainActor public func revisePledge(_ input: UpdateBackingInput) async throws
    -> UpdateBackingEnvelope
  {
    try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.UpdateBackingMutation(input: GraphAPI.UpdateBackingInput.from(input)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: { data in
      guard let envelope = UpdateBackingEnvelope.from(data) else {
        throw ErrorEnvelope.couldNotParseJSON
      }
      return envelope
    })
  }

  @MainActor public func cancelPledge(_ input: CancelBackingInput) async throws {
    // Preserve the current GraphQL contract: only the backing ID is transmitted.
    // The legacy client does not transmit its optional cancellation note.
    let _: Void = try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CancelBackingMutation(
          input: GraphAPI.CancelBackingInput(id: input.backingId)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: { _ in () })
  }
}

extension Service {
  @MainActor public func openPledgeCheckout(_ input: CreateCheckoutInput) async throws
    -> CreateCheckoutEnvelope
  {
    try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CreateCheckoutMutation(
          input: .init(
            projectId: input.projectId, amount: .someOrNil(input.amount),
            locationId: .someOrNil(input.locationId), rewardIds: .someOrNil(input.rewardIds),
            refParam: .someOrNil(input.refParam)
          )), queue: .global(qos: .userInitiated), resultHandler: completion)
    }, map: { data in
      guard let envelope = CreateCheckoutEnvelope.from(data) else {
        throw ErrorEnvelope.couldNotParseJSON
      }
      return envelope
    })
  }

  @MainActor public func checkPledgeCheckout(
    checkoutID: String, sourceID: String, secret: String
  ) async throws -> ValidateCheckoutEnvelope {
    try await self.cancellableQuery(
      GraphAPI.ValidateCheckoutQuery(
        checkoutId: checkoutID, paymentSourceId: sourceID, paymentIntentClientSecret: secret
      ), map: { try ValidateCheckoutEnvelope.validated(from: $0) })
  }

  @MainActor public func finishPledgeCheckout(
    _ input: GraphAPI.CompleteOnSessionCheckoutInput
  ) async throws {
    // Completion is an acknowledgement. Preserve success for any root data;
    // the existing checkout screen never consumes the mutation's nested payload.
    let _: Void = try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CompleteOnSessionCheckoutMutation(input: input),
        queue: .global(qos: .userInitiated), resultHandler: completion)
    }, map: { _ in () })
  }

  @MainActor public func managedPledgeBacking(id: Int) async throws -> Backing {
    try await self.cancellableQuery(
      GraphAPI.FetchBackingWithIncrementsRefundedQuery(id: "\(id)"), map: { data in
        guard let backing = Backing.managedBacking(from: data) else {
          throw ErrorEnvelope.couldNotParseJSON
        }
        return backing
      })
  }

  @MainActor public func managedPledgeRewards(projectID: Int) async throws
    -> RewardsAndPledgeOverTimeEnvelope
  {
    try await self.cancellableQuery(
      GraphAPI.FetchProjectRewardsByIdQuery(
        projectId: projectID, includeShippingRules: true, includePledgeOverTime: true
      ), map: { Project.projectRewardsAndPledgeOverTimeData(from: $0) })
  }
}

extension Service {
  @MainActor public func pledgedProjects(
    tiers: [GraphAPI.PledgeProjectsOverviewSort], cursor: String?, limit: Int
  ) async throws -> GraphAPI.FetchPledgedProjectsQuery.Data {
    try await self.cancellableQuery(
      GraphAPI.FetchPledgedProjectsQuery(
        first: .some(limit), after: .someOrNil(cursor),
        tierTypes: .some(tiers.map { GraphQLEnum($0) })
      ))
  }
  @MainActor public func confirmPledgeAddress(backingID: String, addressID: String) async throws
    -> Bool
  {
    try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.CreateOrUpdateBackingAddressMutation(
          input: .init(backingId: backingID, addressId: addressID)),
        queue: .global(qos: .userInitiated), resultHandler: completion)
    }, map: { $0.createOrUpdateBackingAddress?.success ?? false })
  }
  @MainActor public func setPledgeReceipt(backingID: String, received: Bool) async throws -> Bool {
    try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.UpdateBackerCompletedMutation(
          input: .init(id: backingID, backerCompleted: received)),
        queue: .global(qos: .userInitiated), resultHandler: completion)
    }, map: { $0.updateBackerCompleted?.backing?.backerCompleted == received })
  }
  @MainActor public func pledgePaymentPlan(slug: String, amount: String) async throws
    -> PledgePaymentPlan?
  {
    try await self.cancellableQuery(
      GraphAPI.BuildPaymentPlanQuery(slug: slug, amount: amount),
      map: { PledgePaymentPlan.from($0) })
  }
}
