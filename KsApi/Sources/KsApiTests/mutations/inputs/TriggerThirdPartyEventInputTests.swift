import GraphAPI
@testable import KsApi
@testable import KsApiTestHelpers
import XCTest

final class TriggerThirdPartyEventInputTests: XCTestCase {
  @MainActor
  func testPreparedEventRunsOnlyWhenAwaited() async {
    let input = TriggerThirdPartyEventInput(
      deviceId: "device", eventName: "event", projectId: "project", pledgeAmount: nil,
      shipping: nil, transactionId: nil, userId: "user",
      appData: GraphAPI.AppDataInput(advertiserTrackingEnabled: true, applicationTrackingEnabled: true, extinfo: []),
      clientMutationId: ""
    )
    let service = MockService(apolloClient: MockGraphQLClient.shared, triggerThirdPartyEventResult: .failure(.couldNotParseJSON))
    let operation = service.prepareThirdPartyEvent(input: input)
    do {
      try await operation()
      XCTFail("The deferred operation should surface its service error")
    } catch let error as ErrorEnvelope {
      XCTAssertEqual(error.ksrCode, ErrorEnvelope.couldNotParseJSON.ksrCode)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testTriggerThirdPartyEventInputTestsDictionary_WithValue_Success() {
    let triggerThirdPartyEventInput =
      TriggerThirdPartyEventInput(
        deviceId: "deviceId",
        eventName: "eventName",
        projectId: "projectId",
        pledgeAmount: 1.0,
        shipping: 2.0,
        transactionId: "transactionId",
        userId: "userId",
        appData: GraphAPI.AppDataInput(
          advertiserTrackingEnabled: true,
          applicationTrackingEnabled: true,
          extinfo: ["appData"]
        ),
        clientMutationId: ""
      )

    let input = triggerThirdPartyEventInput.toInputDictionary()

    XCTAssertEqual(input["deviceId"] as? String, "deviceId")
    XCTAssertEqual(input["eventName"] as? String, "eventName")
    XCTAssertEqual(input["projectId"] as? String, "projectId")
    XCTAssertEqual(input["pledgeAmount"] as? Double, 1.0)
    XCTAssertEqual(input["shipping"] as? Double, 2.0)
    XCTAssertEqual(input["transactionId"] as? String, "transactionId")
    XCTAssertEqual(input["userId"] as? String, "userId")
    XCTAssertNotNil(input["appData"])
    XCTAssertEqual(input["clientMutationId"] as? String, "")
  }
}
