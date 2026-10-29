import Apollo
import ApolloAPI
import ApolloTestSupport
import GraphAPI
import GraphAPITestMocks
@testable import KsApiTestHelpers
@testable import KsApi
import XCTest

@MainActor
final class PledgeTransportSnapshotTests: XCTestCase {
  func testCreateBackingReturnsCheckedAuthenticationSnapshot() async throws {
    let data = GraphAPI.CreateBackingMutation.Data(createBacking: .init(checkout: .init(
      backing: .init(clientSecret: "test_secret", requiresAction: true),
      id: "checkout", state: .case(.verifying)
    )))
    let envelope: CreateBackingEnvelope = try await CancellableGraphQLRequest.fetch(start: { callback in
      callback(.success(GraphQLResult(data: data, extensions: nil, errors: nil, source: .server, dependentKeys: nil)))
      return SnapshotRequest()
    }, map: { data in
      guard let envelope = CreateBackingEnvelope.from(data) else { throw ErrorEnvelope.couldNotParseJSON }
      return envelope
    })
    XCTAssertEqual(envelope.createBacking.checkout.id, "checkout")
    XCTAssertEqual(envelope.createBacking.checkout.state, .verifying)
    XCTAssertTrue(envelope.createBacking.checkout.backing.requiresAction)
    XCTAssertEqual(envelope.createBacking.checkout.backing.clientSecret, "test_secret")
  }

  func testUpdateBackingPreservesNullableAuthenticationSecret() async throws {
    let data = GraphAPI.UpdateBackingMutation.Data(updateBacking: .init(checkout: .init(
      backing: .init(clientSecret: nil, requiresAction: false), id: "updated", state: .case(.successful)
    )))
    let envelope: UpdateBackingEnvelope = try await CancellableGraphQLRequest.fetch(start: { callback in
      callback(.success(GraphQLResult(data: data, extensions: nil, errors: nil, source: .server, dependentKeys: nil)))
      return SnapshotRequest()
    }, map: { data in
      guard let envelope = UpdateBackingEnvelope.from(data) else { throw ErrorEnvelope.couldNotParseJSON }
      return envelope
    })
    XCTAssertEqual(envelope.updateBacking.checkout.state, .successful)
    XCTAssertNil(envelope.updateBacking.checkout.backing.clientSecret)
    XCTAssertFalse(envelope.updateBacking.checkout.backing.requiresAction)
  }

  func testCheckoutReturnsIdentifiersAndPaymentURL() async throws {
    let data = GraphAPI.CreateCheckoutMutation.Data(createCheckout: .init(checkout: .init(
      id: "checkout", paymentUrl: "https://example.test/pay", backing: .init(id: "backing")
    )))
    let envelope: CreateCheckoutEnvelope = try await CancellableGraphQLRequest.fetch(start: { callback in
      callback(.success(GraphQLResult(data: data, extensions: nil, errors: nil, source: .server, dependentKeys: nil)))
      return SnapshotRequest()
    }, map: { data in
      guard let envelope = CreateCheckoutEnvelope.from(data) else { throw ErrorEnvelope.couldNotParseJSON }
      return envelope
    })
    XCTAssertEqual(envelope.checkout.id, "checkout")
    XCTAssertEqual(envelope.checkout.backingId, "backing")
    XCTAssertEqual(envelope.checkout.paymentUrl, "https://example.test/pay")
  }

  func testMissingCheckoutDoesNotBecomeSuccessfulBacking() async throws {
    let data = GraphAPI.CreateBackingMutation.Data(createBacking: .init(checkout: nil))
    do {
      let _: CreateBackingEnvelope = try await CancellableGraphQLRequest.fetch(start: { callback in
        callback(.success(GraphQLResult(data: data, extensions: nil, errors: nil, source: .server, dependentKeys: nil)))
        return SnapshotRequest()
      }, map: { data in
        guard let envelope = CreateBackingEnvelope.from(data) else { throw ErrorEnvelope.couldNotParseJSON }
        return envelope
      })
      XCTFail("Missing checkout cannot report success")
    } catch let error as ErrorEnvelope {
      XCTAssertEqual(error.ksrCode, ErrorEnvelope.couldNotParseJSON.ksrCode)
      XCTAssertEqual(error.errorMessages, ErrorEnvelope.couldNotParseJSON.errorMessages)
    }
  }

  func testCheckoutValidationPreservesMessages() async throws {
    let data = GraphAPI.ValidateCheckoutQuery.Data(checkout: .init(
      isValidForOnSessionCheckout: .init(valid: true, messages: ["Ready"])))
    let envelope = try await self.mapped(data) { try ValidateCheckoutEnvelope.validated(from: $0) }
    XCTAssertEqual(envelope.messages, ["Ready"])
  }

  func testInvalidCheckoutReturnsValidationErrorWithServerMessages() async throws {
    let data = GraphAPI.ValidateCheckoutQuery.Data(checkout: .init(
      isValidForOnSessionCheckout: .init(valid: false, messages: ["Card expired", "Try another card"])))
    do {
      _ = try await self.mapped(data) { try ValidateCheckoutEnvelope.validated(from: $0) }
      XCTFail("Invalid checkout accepted")
    } catch let error as ErrorEnvelope {
      XCTAssertEqual(error.ksrCode, .ValidateCheckoutError)
      XCTAssertEqual(error.errorMessages, ["Card expired", "Try another card"])
    }
  }

  func testMissingCheckoutValidationReturnsParseError() async throws {
    do {
      _ = try await self.mapped(GraphAPI.ValidateCheckoutQuery.Data()) {
        try ValidateCheckoutEnvelope.validated(from: $0)
      }
      XCTFail("Missing checkout accepted")
    } catch let error as ErrorEnvelope {
      XCTAssertEqual(error.ksrCode, ErrorEnvelope.couldNotParseJSON.ksrCode)
    }
  }

  func testPaymentPlanPreservesEligibilityAmountCurrencyAndInstallmentOrder() async throws {
    typealias Increment = GraphAPI.BuildPaymentPlanQuery.Data.Project.PaymentPlan.PaymentIncrement
    let data = GraphAPI.BuildPaymentPlanQuery.Data(project: .init(paymentPlan: .init(
      amountIsPledgeOverTimeEligible: true,
      paymentIncrements: [
        Increment(amount: .init(amountFormattedInProjectNativeCurrency: "$25.00", currency: "USD"),
                  scheduledCollection: "2030-01-01T00:00:00Z"),
        Increment(amount: .init(amountFormattedInProjectNativeCurrency: "$99.00", currency: "USD"),
                  scheduledCollection: "invalid-date"),
        Increment(amount: .init(amountFormattedInProjectNativeCurrency: "$75.00", currency: "USD"),
                  scheduledCollection: "2030-02-01T00:00:00Z")
      ])))
    let snapshot = try await self.mapped(data) { PledgePaymentPlan.from($0) }
    let plan = try XCTUnwrap(snapshot)
    XCTAssertTrue(plan.amountIsPledgeOverTimeEligible)
    XCTAssertEqual(plan.paymentIncrements.map { $0.amount.amountFormattedInProjectNativeCurrency },
                   ["$25.00", "$75.00"])
    XCTAssertEqual(plan.paymentIncrements.map { $0.amount.currency }, ["USD", "USD"])
    XCTAssertEqual(plan.paymentIncrements.map { $0.scheduledCollection }, [1_893_456_000, 1_896_134_400])
    XCTAssertEqual(plan.paymentIncrements.map { $0.refundStatus }, [.unknown, .unknown])
    XCTAssertTrue(plan.paymentIncrements.allSatisfy { $0.badge == nil })
  }

  func testMissingProjectOrPlanIsSuccessfulAbsentPlan() async throws {
    for data in [GraphAPI.BuildPaymentPlanQuery.Data(), .init(project: .init())] {
      let plan = try await self.mapped(data) { PledgePaymentPlan.from($0) }
      XCTAssertNil(plan)
    }
  }

  func testIneligiblePlanWithAbsentIncrementsRemainsAPlan() async throws {
    let data = GraphAPI.BuildPaymentPlanQuery.Data(project: .init(paymentPlan: .init(
      amountIsPledgeOverTimeEligible: false)))
    let plan = try await self.mapped(data) { PledgePaymentPlan.from($0) }
    XCTAssertEqual(plan, KsApi.PledgePaymentPlan(amountIsPledgeOverTimeEligible: false, paymentIncrements: []))
  }

  func testCheckoutCompletionAcknowledgesRootDataWithoutNestedPayload() async throws {
    let _: Void = try await self.mapped(GraphAPI.CompleteOnSessionCheckoutMutation.Data()) { _ in () }
  }

  func testCheckoutCompletionRejectsMissingRootData() async throws {
    let data: GraphAPI.CompleteOnSessionCheckoutMutation.Data? = nil
    do {
      let _: Void = try await self.mapped(data) { _ in () }
      XCTFail("Missing root data accepted")
    } catch let error as ErrorEnvelope {
      XCTAssertEqual(error.ksrCode, ErrorEnvelope.couldNotParseJSON.ksrCode)
    }
  }

  func testCheckoutCompletionDoesNotHideGraphQLErrorAlongsideData() async throws {
    do {
      let _: Void = try await self.mapped(
        GraphAPI.CompleteOnSessionCheckoutMutation.Data(),
        errors: [GraphQLError(["message": "Checkout declined"])]) { _ in () }
      XCTFail("GraphQL failure acknowledged as success")
    } catch let error as ErrorEnvelope {
      XCTAssertEqual(error.errorMessages, ErrorEnvelope.graphError("Checkout declined").errorMessages)
    }
  }

  func testManagedBackingPreservesRefundAmountsAndBadgesAcrossTransfer() async throws {
    let mock = Mock<GraphAPITestMocks.Query>()
    mock.backing = GraphAPITestMocks.Backing.mock
    mock.backing?.paymentIncrements = [
      GraphAPITestMocks.PaymentIncrement.collectedMock,
      GraphAPITestMocks.PaymentIncrement.collectedAdjustedMock,
      GraphAPITestMocks.PaymentIncrement.refundedMock
    ]
    let data = GraphAPI.FetchBackingWithIncrementsRefundedQuery.Data.from(mock)
    let backing = try await self.mapped(data) { data in
      guard let backing = KsApi.Backing.managedBacking(from: data) else {
        throw ErrorEnvelope.couldNotParseJSON
      }
      return backing
    }
    XCTAssertEqual(backing.id, 1)
    XCTAssertEqual(backing.projectId, 987)
    XCTAssertEqual(backing.status, .pledged)
    XCTAssertEqual(backing.paymentIncrements.map { $0.badge?.copy },
                   ["Collected", "Collected (adjusted)", "Refunded"])
    XCTAssertEqual(backing.paymentIncrements[0].refundStatus, .notRefunded)
    guard case let .partialRefund(amount) = backing.paymentIncrements[1].refundStatus else {
      return XCTFail("Partial refund lost")
    }
    XCTAssertEqual(amount.amountFormattedInProjectNativeCurrency, "$23.00")
    XCTAssertEqual(backing.paymentIncrements[2].refundStatus, .fullRefund)
  }

  func testMissingManagedBackingCannotBecomeSuccessfulSnapshot() async throws {
    do {
      _ = try await self.mapped(GraphAPI.FetchBackingWithIncrementsRefundedQuery.Data()) { data in
        guard let backing = KsApi.Backing.managedBacking(from: data) else {
          throw ErrorEnvelope.couldNotParseJSON
        }
        return backing
      }
      XCTFail("Missing backing accepted")
    } catch let error as ErrorEnvelope {
      XCTAssertEqual(error.ksrCode, ErrorEnvelope.couldNotParseJSON.ksrCode)
    }
  }

  func testManagedRewardsPreserveExpandedShippingAndLocalPickup() async throws {
    let data = FetchProjectRewardsByIdQueryTemplate.validRewardWithAllFields.data
    let envelope = try await self.mapped(data) { KsApi.Project.projectRewardsAndPledgeOverTimeData(from: $0) }
    let reward = try XCTUnwrap(envelope.rewards.first)
    XCTAssertEqual(reward.minimum, 400.0)
    XCTAssertEqual(reward.convertedMinimum, 599.0)
    XCTAssertEqual(reward.shippingRulesExpanded?.count, 29)
    XCTAssertEqual(reward.shipping.preference, .restricted)
    XCTAssertEqual(reward.localPickup?.name, "San Jose")
  }

  func testMissingManagedRewardsProjectPreservesEmptyFallback() async throws {
    let envelope = try await self.mapped(GraphAPI.FetchProjectRewardsByIdQuery.Data()) {
      KsApi.Project.projectRewardsAndPledgeOverTimeData(from: $0)
    }
    XCTAssertTrue(envelope.rewards.isEmpty)
    XCTAssertFalse(envelope.isPledgeOverTimeAllowed)
    XCTAssertNil(envelope.pledgeOverTimeCollectionPlanChargeExplanation)
    XCTAssertNil(envelope.pledgeOverTimeCollectionPlanChargedAsNPayments)
    XCTAssertNil(envelope.pledgeOverTimeCollectionPlanShortPitch)
    XCTAssertNil(envelope.pledgeOverTimeMinimumExplanation)
  }

  private func mapped<Data: RootSelectionSet, Value: Sendable>(
    _ data: Data?, errors: [GraphQLError]? = nil,
    map: @escaping @Sendable (Data) throws -> Value
  ) async throws -> Value {
    try await CancellableGraphQLRequest.fetch(start: { callback in
      callback(.success(GraphQLResult(data: data, extensions: nil, errors: errors,
                                     source: .server, dependentKeys: nil)))
      return SnapshotRequest()
    }, map: map)
  }

}

private final class SnapshotRequest: Cancellable {
  func cancel() {}
}
