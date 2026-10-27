@testable import KsApi
@testable import KsApiTestHelpers
import ReactiveExtensions
import ReactiveSwift
import XCTest

struct MySwiftModel: Decodable, Equatable {
  public let array: [String]
  public let bool: Bool
  public let dict: [String: String]
  public let id: Int
  public let name: String
}

final class ServiceTests: XCTestCase {
  func testNativeOAuthUsesExchangedTokenOnlyForUserRequest() throws {
    let service = Service(oauthToken: OauthToken(token: "old-fixture"))
    let request = try service.preparedRouteRequest(.userSelf, oauthToken: "new-fixture")
    XCTAssertEqual(request.url?.path, "/v1/users/self")
    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Auth"), "token new-fixture")
    XCTAssertEqual(service.oauthToken?.token, "old-fixture", "Uncommitted token must not mutate the service")
  }

  func testNativeSocialSignupPreservesBothNewsletterFields() throws {
    for optedIn in [false, true] {
      let request = try Service().preparedRouteRequest(.facebookSignup(
        facebookAccessToken: "fixture", sendNewsletters: optedIn
      ))
      XCTAssertEqual(request.url?.path, "/v1/facebook/access_token")
      XCTAssertEqual(request.httpMethod, "PUT")
      let body = try XCTUnwrap(
        JSONSerialization
          .jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
      )
      XCTAssertEqual(body["access_token"] as? String, "fixture")
      XCTAssertEqual(body["intent"] as? String, "register")
      XCTAssertEqual(body["send_newsletters"] as? Bool, optedIn)
      XCTAssertEqual(body["newsletter_opt_in"] as? Bool, optedIn)
    }
  }

  func testNativeOAuthExchangePreservesPKCEAndPasswordResetPreservesEmail() throws {
    let service = Service()
    let exchange = try service.preparedRouteRequest(.exchangeToken(params: .init(
      temporaryToken: "fixture-code", codeVerifier: "fixture-verifier"
    )))
    XCTAssertEqual(exchange.url?.path, "/v1/oauth/authorizations/exchange")
    XCTAssertEqual(exchange.httpMethod, "POST")
    let body = try XCTUnwrap(
      JSONSerialization
        .jsonObject(with: XCTUnwrap(exchange.httpBody)) as? [String: String]
    )
    XCTAssertEqual(body, ["code": "fixture-code", "code_verifier": "fixture-verifier"])
    let reset = try service.preparedRouteRequest(.resetPassword(email: "person@example.invalid"))
    XCTAssertEqual(reset.httpMethod, "POST")
    let resetBody = try XCTUnwrap(
      JSONSerialization
        .jsonObject(with: XCTUnwrap(reset.httpBody)) as? [String: String]
    )
    XCTAssertEqual(resetBody, ["email": "person@example.invalid"])
  }

  func testAsyncAuthenticationDecoderPreservesTokenAndUser() throws {
    let data = try JSONSerialization.data(withJSONObject: [
      "access_token": "fixture-token", "user": User.template.encode()
    ])
    let url = try XCTUnwrap(URL(string: "https://example.invalid/auth"))
    let response = try XCTUnwrap(HTTPURLResponse(
      url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]
    ))
    let envelope: AccessTokenEnvelope = try Service.decodeDiscoveryResponse(data, response: response)
    XCTAssertEqual(envelope.accessToken, "fixture-token")
    XCTAssertEqual(envelope.user.id, User.template.id)
  }

  func testAsyncAuthenticationDecoderPreservesTwoFactorErrorContract() throws {
    let data = try JSONSerialization.data(withJSONObject: [
      "error_messages": ["Verification required"], "ksr_code": "tfa_required", "http_code": 403
    ])
    let url = try XCTUnwrap(URL(string: "https://example.invalid/auth"))
    let response = try XCTUnwrap(HTTPURLResponse(
      url: url, statusCode: 403, httpVersion: nil, headerFields: ["Content-Type": "application/json"]
    ))
    do {
      let _: AccessTokenEnvelope = try Service.decodeDiscoveryResponse(data, response: response)
      XCTFail("Authentication error decoded as success")
    } catch let error as ErrorEnvelope {
      XCTAssertEqual(error.ksrCode, .TfaRequired)
      XCTAssertEqual(error.httpCode, 403)
      XCTAssertEqual(error.errorMessages, ["Verification required"])
    }
  }

  func testDefaults() {
    XCTAssertTrue(Service().serverConfig == ServerConfig.production)
    XCTAssertNil(Service().oauthToken)
    XCTAssertEqual(Service().language, "en")
  }

  func testEquals() {
    let s1 = Service()
    let s2 = Service(serverConfig: ServerConfig.staging)
    let s3 = Service(oauthToken: OauthToken(token: "deadbeef"))
    let s4 = Service(language: "es")

    XCTAssertTrue(s1 == s1)
    XCTAssertTrue(s2 == s2)
    XCTAssertTrue(s3 == s3)
    XCTAssertTrue(s4 == s4)

    XCTAssertFalse(s1 == s2)
    XCTAssertFalse(s1 == s3)
    XCTAssertFalse(s1 == s4)

    XCTAssertFalse(s2 == s3)
    XCTAssertFalse(s2 == s4)

    XCTAssertFalse(s3 == s4)
  }

  func testLogin() {
    let loggedOut = Service()
    let loggedIn = loggedOut.login(OauthToken(token: "deadbeef"))

    XCTAssertTrue(loggedIn == Service(oauthToken: OauthToken(token: "deadbeef")))
  }

  func testLogout() {
    let loggedIn = Service(oauthToken: OauthToken(token: "deadbeef"))
    let loggedOut = loggedIn.logout()

    XCTAssertTrue(loggedOut == Service())
  }

  func testSwiftDecodeModel_ValidModel() {
    let jsonData: String = """
    {
        "array": ["string1", "string2"],
        "bool": true,
        "dict": {"key1": "value1", "key2": "value2"},
        "id": 5,
        "name": "Swift Name"
    }
    """

    let expectedResult = try! JSONDecoder().decode(MySwiftModel.self, from: jsonData.data(using: .utf8)!)

    let model: SignalProducer<MySwiftModel, ErrorEnvelope> = Service()
      .decodeModelToSignal(jsonData.data(using: .utf8)!)
    let result = try! model.single()?.get()
    XCTAssertEqual(result, expectedResult)
  }

  func testSwiftDecodeModel_WrongKeyModel() {
    let jsonData: String = """
    {
        "array": ["string1", "string2"],
        "bool": true,
        "dict": {"key1": "value1", "key2": "value2"},
        "id": 5,
        "wrong_key": "Swift Name"
    }
    """

    let model: SignalProducer<MySwiftModel, ErrorEnvelope> = Service()
      .decodeModelToSignal(jsonData.data(using: .utf8)!)
    XCTAssertThrowsError(try model.single()?.get(), "wrong key should throw an error")
  }

  func testSwiftDecodeModel_WrongTypeModel() {
    let jsonData: String = """
    {
        "array": ["string1", "string2"],
        "bool": "wrong_type",
        "dict": {"key1": "value1", "key2": "value2"},
        "id": 5,
        "name": "Swift Name"
    }
    """

    let model: SignalProducer<MySwiftModel, ErrorEnvelope> = Service()
      .decodeModelToSignal(jsonData.data(using: .utf8)!)
    XCTAssertThrowsError(try model.single()?.get(), "wrong key should throw an error")
  }

  func testSwiftDecodeModel_Optional_WrongTypeModel() {
    let jsonData: String = """
    {
        "array": ["string1", "string2"],
        "bool": "wrong_type",
        "dict": {"key1": "value1", "key2": "value2"},
        "id": 5,
        "name": "Swift Name"
    }
    """
    let data = jsonData.data(using: .utf8)!
    let model: SignalProducer<MySwiftModel?, ErrorEnvelope> = Service().decodeModelToSignal(data: data)
    let result = try! model.single()?.get()
    XCTAssertNil(result)
  }

  func testSwiftDecodeModel_ValidModel_Combine() {
    let expectedResult = MySwiftModel(
      array: ["string1", "string2"],
      bool: true,
      dict: ["key1": "value1", "key2": "value2"],
      id: 5,
      name: "Swift Name"
    )

    let jsonData: String = """
    {
        "array": ["string1", "string2"],
        "bool": true,
        "dict": {"key1": "value1", "key2": "value2"},
        "id": 5,
        "name": "Swift Name"
    }
    """

    let data = jsonData.data(using: .utf8)!
    let result: Result<MySwiftModel?, ErrorEnvelope> = Service()
      .decodeModelToResult(data: data, ofType: MySwiftModel.self)

    switch result {
    case let .success(decodedModel):
      if let decodedModelUnwrapped = decodedModel {
        XCTAssertEqual(expectedResult, decodedModelUnwrapped)
      } else {
        XCTFail("Decoded model is nil")
      }
    case .failure: XCTFail("Failed to decode model")
    }
  }

  func testSwiftDecodeModel_InvalidModel_Combine() {
    let jsonData: String = """
    {
        "notAValidKey": "foo"
    }
    """

    let data = jsonData.data(using: .utf8)!
    let result: Result<MySwiftModel?, ErrorEnvelope> = Service()
      .decodeModelToResult(data: data, ofType: MySwiftModel.self)

    switch result {
    case .success:
      XCTFail("Decode should have failed.")
    case let .failure(error):
      XCTAssertNotNil(error)
      XCTAssertEqual(error.ksrCode, .DecodingJSONFailed)
      XCTAssertEqual(error.errorMessages, ["JSON decoding failed: missing key \"array\""])
    }
  }

  /*
   These two tests shouldn't actually *run* in our testing environment, because we don't want to make real network requests
   in our real tests. But it's a useful little utility for comparing the Combine and ReactiveSwift version of the
   API V1 call Request.
   */

  /*
   func testCompareRequest_Successful_RAC_vs_Combine() {
     let service = Service(serverConfig: ServerConfig.production)
     var project = Project.template
     project.id = 152885112

     let rac_publisher = service.fetchProject(project: project)
     let combine_publisher = service.fetchProject_combine(project: project)

     let combine_observer = CombineTestObserver<Project, ErrorEnvelope>()
     combine_observer.observe(combine_publisher)

     _ = XCTWaiter.wait(for: [expectation(description: "Wait 10 seconds for the server call.")], timeout: 10.0)

     let r1 = rac_publisher.first()
     let r2 = combine_observer.events.first

     if case let .success(p1) = r1 {
       if case let .value(p2) = r2 {
         XCTAssertEqual(p1, p2)
         return
       }
     }

     XCTFail()
   }

   func testCompareRequest_Failure_RAC_vs_Combine() {
     let service = Service(serverConfig: ServerConfig.production)
     var project = Project.template
     project.id = 1 //Not a real project ID

     let rac_publisher = service.fetchProject(project: project)
     let combine_publisher = service.fetchProject_combine(project: project)

     let combine_observer = CombineTestObserver<Project, ErrorEnvelope>()
     combine_observer.observe(combine_publisher)

     _ = XCTWaiter.wait(for: [expectation(description: "Wait 10 seconds for the server call.")], timeout: 10.0)

     let r1 = rac_publisher.first()
     let r2 = combine_observer.events.first

     if case let .failure(e1) = r1 {
       if case let .error(e2) = r2 {
         XCTAssertEqual(e1.errorMessages, e2.errorMessages)
         return
       }
     }

     XCTFail()
   }
   */
}
