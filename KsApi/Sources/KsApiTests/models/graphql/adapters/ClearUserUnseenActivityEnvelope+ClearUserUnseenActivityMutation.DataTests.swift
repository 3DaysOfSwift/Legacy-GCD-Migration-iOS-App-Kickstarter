@testable import KsApi
@testable import KsApiTestHelpers
import XCTest

final class ClearUserUnseenActivityEnvelope_ClearUserUnseenActivityMutationTests: XCTestCase {
  func testClearUserUnseenActivity_Success() {
    guard let env = ClearUserUnseenActivityEnvelope.from(ClearUserUnseenActivityMutationTemplate.valid.data)
    else {
      XCTFail("ClearUserUnseenActivityEnvelope should exist.")

      return
    }

    XCTAssertEqual(env.activityIndicatorCount, 3)
  }

  func testClearUserUnseenActivity_Failure() {
    let env = ClearUserUnseenActivityEnvelope.from(ClearUserUnseenActivityMutationTemplate.errored.data)

    XCTAssertNil(env?.activityIndicatorCount)
  }
}
