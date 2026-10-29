import Apollo
import ApolloAPI
import GraphAPI
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
}

private final class SnapshotRequest: Cancellable {
  func cancel() {}
}
