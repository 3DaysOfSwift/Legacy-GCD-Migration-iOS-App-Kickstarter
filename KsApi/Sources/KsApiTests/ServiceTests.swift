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
  @MainActor
  func testNativeFriendsRoutesPreserveReadAndWriteSemantics() throws {
    let service = Service()
    for (route, method, path) in [
      (Route.friends, "GET", "/v1/users/self/friends/find"),
      (.friendStats, "GET", "/v1/users/self/friends/find"),
      (.followFriend(userId: 42), "POST", "/v1/users/self/friends"),
      (.unfollowFriend(userId: 42), "DELETE", "/v1/users/self/friends/42"),
      (.followAllFriends, "PUT", "/v1/users/self/friends/follow_all")
    ] {
      let request = try service.preparedRouteRequest(route)
      XCTAssertEqual(request.httpMethod, method)
      XCTAssertEqual(request.url?.path, path)
    }
    let stats = try service.preparedRouteRequest(.friendStats)
    let query = URLComponents(url: try XCTUnwrap(stats.url), resolvingAgainstBaseURL: false)?.queryItems
    XCTAssertEqual(query?.first(where: { $0.name == "count" })?.value, "0")
    let follow = try service.preparedRouteRequest(.followFriend(userId: 42))
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(follow.httpBody)) as? [String: Int])
    XCTAssertEqual(body["followed_id"], 42)

  }

  @MainActor
  func testNativeFriendsMockPreservesResponsesAndFailures() async throws {
    let page = try await MockService().friendsPage(cursor: "next")
    XCTAssertEqual(page.users, FindFriendsEnvelope.template.users)
    let stats = try await MockService().friendStatistics()
    XCTAssertEqual(stats.stats.friendProjectsCount, FriendStatsEnvelope.template.stats.friendProjectsCount)
    XCTAssertEqual(stats.stats.remoteFriendsCount, FriendStatsEnvelope.template.stats.remoteFriendsCount)
    let user = try await MockService().followUser(id: 42)
    XCTAssertEqual(user.id, 42)
    XCTAssertEqual(user.isFriend, true)
    try await MockService().unfollowUser(id: 42)
    try await MockService().followEveryFriend()
    do {
      _ = try await MockService(fetchFriendsError: .couldNotParseJSON).friendsPage(cursor: nil)
      XCTFail("Expected the configured error")
    } catch { XCTAssertTrue(error is ErrorEnvelope) }
    do {
      _ = try await MockService(fetchFriendStatsError: .couldNotParseJSON).friendStatistics()
      XCTFail("Expected the configured error")
    } catch { XCTAssertTrue(error is ErrorEnvelope) }
  }

  @MainActor
  func testPublicDemoRejectsFollowMutations() async {
    let service = MockService.publicDemo()
    do { _ = try await service.followUser(id: 42); XCTFail("Demo must not follow") }
    catch { XCTAssertTrue(error is ErrorEnvelope) }
    do { try await service.unfollowUser(id: 42); XCTFail("Demo must not unfollow") }
    catch { XCTAssertTrue(error is ErrorEnvelope) }
    do { try await service.followEveryFriend(); XCTFail("Demo must not follow all") }
    catch { XCTAssertTrue(error is ErrorEnvelope) }
  }

  @MainActor
  func testNativeFriendsRejectInvalidCursorBeforeNetworkAdmission() async {
    do {
      _ = try await Service().friendsPage(cursor: "http://[")
      XCTFail("Malformed cursor must fail before transport")
    } catch { XCTAssertTrue(error is ErrorEnvelope) }
  }

  @MainActor
  func testFastAddOnsRejectInvalidCountryBeforeNetworkAdmission() async {
    do {
      _ = try await Service().fastRewardAddOns(baseRewardID: 1, country: "INVALID")
      XCTFail("Invalid country must fail without asserting or starting a request")
    } catch { XCTAssertTrue(error is ErrorEnvelope) }
  }

  @MainActor
  func testNativeAddOnsMockPreservesNilEmptyAndFailureResponses() async throws {
    var project = Project.template
    project.rewardData.addOns = nil
    let absent = try await MockService(fetchRewardAddOnsSelectionViewRewardsResult: .success(project))
      .rewardAddOns(slug: project.slug, locationID: nil)
    XCTAssertNil(absent)
    project.rewardData.addOns = []
    let empty = try await MockService(fetchRewardAddOnsSelectionViewRewardsResult: .success(project))
      .rewardAddOns(slug: project.slug, locationID: nil)
    XCTAssertEqual(empty, [])
    do {
      _ = try await MockService(fetchRewardAddOnsSelectionViewRewardsResult: .failure(.couldNotParseJSON))
        .rewardAddOns(slug: project.slug, locationID: nil)
      XCTFail("Expected explicit request failure")
    } catch { XCTAssertTrue(error is ErrorEnvelope) }
  }

  @MainActor
  func testPublicDemoRejectsNativeMessagingOperations() async {
    let service = MockService.publicDemo()
    let operations: [() async throws -> Void] = [
      { _ = try await service.messageThreadsPage(mailbox: .inbox, project: nil, cursor: nil) },
      { _ = try await service.messageSearch(query: "fixture", project: nil) },
      { _ = try await service.messageThread(id: 1) },
      { _ = try await service.messageThread(backing: .template) },
      { _ = try await service.messageBacking(project: .template, user: .template) },
      { _ = try await service.readMessageThread(.template) },
      { _ = try await service.submitMessage(body: "fixture", subject: .project(id: 1, name: "Fixture")) }
    ]
    for operation in operations {
      do { try await operation(); XCTFail("Public demo must reject account messaging") }
      catch { XCTAssertTrue(error is ErrorEnvelope) }
    }
  }

  func testNativeMessagingRoutesKeepMailboxProjectAndQuery() throws {
    let service = Service()
    let inbox = try service.preparedRouteRequest(.messageThreads(mailbox: .inbox, project: nil))
    XCTAssertEqual(inbox.httpMethod, "GET")
    XCTAssertEqual(inbox.url?.path, "/v1/message_threads/inbox")
    let project = Project.template
    let sent = try service.preparedRouteRequest(.messageThreads(mailbox: .sent, project: project))
    XCTAssertEqual(sent.url?.path, "/v1/projects/\(project.id)/message_threads/sent")
    let search = try service.preparedRouteRequest(.searchMessages(query: "hello & goodbye", project: project))
    XCTAssertEqual(search.url?.path, "/v1/projects/\(project.id)/message_threads/search")
    let query = URLComponents(url: try XCTUnwrap(search.url), resolvingAgainstBaseURL: false)?.queryItems
    XCTAssertEqual(query?.first(where: { $0.name == "q" })?.value, "hello & goodbye")
  }

  func testNativeMessagingWritesKeepDestinationAndUntrimmedBody() throws {
    let service = Service()
    let thread = MessageThread.template
    let read = try service.preparedRouteRequest(.markAsRead(thread))
    XCTAssertEqual(read.httpMethod, "PUT")
    XCTAssertEqual(read.url?.path, "/v1/message_threads/\(thread.id)/read")
    let body = " Hello & goodbye \n"
    let send = try service.preparedRouteRequest(.sendMessage(body: body, messageSubject: .messageThread(thread)))
    XCTAssertEqual(send.httpMethod, "POST")
    XCTAssertEqual(send.url?.path, "/v1/message_threads/\(thread.id)/messages")
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(send.httpBody)) as? [String: String])
    XCTAssertEqual(json["body"], body)
    let project = try service.preparedRouteRequest(.sendMessage(
      body: body, messageSubject: .project(id: 42, name: "Fixture")
    ))
    XCTAssertEqual(project.url?.path, "/v1/projects/42/messages")
  }

  func testNativeProjectNotificationRoutesPreserveBothChannels() throws {
    let service = Service()
    let list = try service.preparedRouteRequest(.projectNotifications)
    XCTAssertEqual(list.httpMethod, "GET")
    XCTAssertEqual(list.url?.path, "/v1/users/self/notifications")
    let notification = ProjectNotification.template
    let update = try service.preparedRouteRequest(.updateProjectNotification(notification: notification))
    XCTAssertEqual(update.httpMethod, "PUT")
    XCTAssertEqual(update.url?.path, "/v1/users/self/notifications/\(notification.id)")
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(update.httpBody)) as? [String: Bool])
    XCTAssertEqual(body, ["email": notification.email, "mobile": notification.mobile])
  }

  func testNativeProjectNotificationDecoderPreservesChannelValues() throws {
    let data = Data("""
      [{"id":17,"email":true,"mobile":false,"project":{"id":99,"name":"Fixture project"}}]
      """.utf8)
    let url = try XCTUnwrap(URL(string: "https://example.invalid/notifications"))
    let response = try XCTUnwrap(HTTPURLResponse(
      url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]
    ))
    let values: [ProjectNotification] = try Service.decodeDiscoveryResponse(data, response: response)
    let value = try XCTUnwrap(values.first)
    XCTAssertEqual(value.id, 17)
    XCTAssertTrue(value.email)
    XCTAssertFalse(value.mobile)
    XCTAssertEqual(value.project.id, 99)
    XCTAssertEqual(value.project.name, "Fixture project")
  }

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
