@testable import KsApi
@testable import KsApiTestHelpers
import XCTest

// FIXME: DISABLED_SPM - This file isn't included in the old test target, and it fails to run.
/*
 final class CreateBackingEnvelope_CreateBackingMutationTests: XCTestCase {
   func test_SCA() {
     let env = CreateBackingEnvelope.from(CreateBackingMutationTemplate.valid(checkoutState: .authorizing, sca: true).data)

     XCTAssertEqual(env?.createBacking.checkout.id, "id")
     XCTAssertEqual(env?.createBacking.checkout.backing.clientSecret, "client-secret")
     XCTAssertEqual(env?.createBacking.checkout.backing.requiresAction, true)
     XCTAssertEqual(env?.createBacking.checkout.state, .authorizing)
   }

   func test_NonSCA_Successful() {
     let env = CreateBackingEnvelope.from(CreateBackingMutationTemplate.valid(checkoutState: .successful, sca: false).data)

     XCTAssertEqual(env?.createBacking.checkout.id, "id")
     XCTAssertEqual(env?.createBacking.checkout.backing.clientSecret, nil)
     XCTAssertEqual(env?.createBacking.checkout.backing.requiresAction, false)
     XCTAssertEqual(env?.createBacking.checkout.state, .successful)
   }

   func test_NonSCA_Failed() {
     let env = CreateBackingEnvelope.from(CreateBackingMutationTemplate.valid(checkoutState: .failed, sca: false).data)

     XCTAssertEqual(env?.createBacking.checkout.id, "id")
     XCTAssertEqual(env?.createBacking.checkout.backing.clientSecret, nil)
     XCTAssertEqual(env?.createBacking.checkout.backing.requiresAction, false)
     XCTAssertEqual(env?.createBacking.checkout.state, .failed)
   }

   func test_BadResponse_Error() {
     XCTAssertNil(CreateBackingEnvelope.from(CreateBackingMutationTemplate.errored.data))
   }
 }
 */
