import Combine
import Foundation
import Prelude
import ReactiveExtensions
import ReactiveSwift

extension Service {
  private static let session = URLSession(configuration: .default)

  @MainActor public func activityPage(cursor: String?) async throws -> ActivityEnvelope {
    if let cursor {
      guard let url = URL(string: cursor) else { throw ErrorEnvelope.invalidPaginationUrl }
      return try await self.discoveryResponse(for: self.preparedRequest(forURL: url))
    }
    return try await self.discussionResponse(route: .activities(
      categories: [.backing, .cancellation, .failure, .follow, .launch, .shipped, .success, .update],
      count: nil
    ))
  }

  @MainActor public func unansweredSurveys() async throws -> [SurveyResponse] {
    try await self.discussionResponse(route: .unansweredSurveyResponses)
  }

  @MainActor public func sessionUser() async throws -> User {
    try await self.discussionResponse(route: .userSelf)
  }

  @MainActor public func confirmEmail(token: String) async throws -> EmailVerificationResponseEnvelope {
    try await self.discussionResponse(route: .verifyEmail(accessToken: token))
  }

  @MainActor public func connectFacebook(token: String) async throws -> User {
    try await self.discussionResponse(route: .facebookConnect(facebookAccessToken: token))
  }

  @MainActor public func projectNotificationSettings() async throws -> [ProjectNotification] {
    try await self.discussionResponse(route: .projectNotifications)
  }

  @MainActor public func saveProjectNotification(_ notification: ProjectNotification) async throws
    -> ProjectNotification {
    try await self.discussionResponse(route: .updateProjectNotification(notification: notification))
  }

  @MainActor public func saveAccountPreferences(_ user: User) async throws -> User {
    try await self.discussionResponse(route: .updateUserSelf(user))
  }

  @MainActor public func authenticate(
    email: String, password: String, code: String?
  ) async throws -> AccessTokenEnvelope {
    try await self.discussionResponse(route: .login(email: email, password: password, code: code))
  }

  @MainActor public func authenticate(
    facebookAccessToken: String, code: String?
  ) async throws -> AccessTokenEnvelope {
    try await self.discussionResponse(route: .facebookLogin(
      facebookAccessToken: facebookAccessToken,
      code: code
    ))
  }

  @MainActor public func discussionProject(param: Param) async throws -> Project {
    try await self.discussionResponse(route: .project(param))
  }

  @MainActor public func projectUpdate(id: Int, project: Param) async throws -> Update {
    try await self.discussionResponse(route: .update(updateId: id, projectParam: project))
  }

  @MainActor public func reportVideoEvent(
    project: any HasProjectWebURL, completed: Bool
  ) async throws -> VoidEnvelope {
    do {
      return try await self.discussionResponse(
        route: completed
          ? .incrementVideoCompletion(project: project) : .incrementVideoStart(project: project)
      )
    } catch let error as ErrorEnvelope where error.ksrCode == .ErrorEnvelopeJSONParsingFailed {
      // These legacy counters may return an empty response after accepting the event.
      return VoidEnvelope()
    }
  }

  @MainActor public func authenticationUser(id: Int) async throws -> User {
    try await self.discussionResponse(route: .user(userId: id))
  }

  @MainActor public func authenticationUser(oauthToken: String) async throws -> User {
    try await self.discussionResponse(route: .userSelf, oauthToken: oauthToken)
  }

  @MainActor public func signupFacebook(
    token: String,
    sendNewsletters: Bool
  ) async throws -> AccessTokenEnvelope {
    try await self.discussionResponse(route: .facebookSignup(
      facebookAccessToken: token,
      sendNewsletters: sendNewsletters
    ))
  }

  @MainActor public func exchangeOAuth(params: OAuthTokenExchangeParams) async throws
    -> OAuthTokenExchangeResponse {
    try await self.discussionResponse(route: .exchangeToken(params: params))
  }

  @MainActor public func requestPasswordReset(email: String) async throws {
    let _: User = try await self.discussionResponse(route: .resetPassword(email: email))
  }

  private func discussionResponse<Model: Decodable>(
    route: Route,
    oauthToken: String? = nil
  ) async throws -> Model {
    try await self.discoveryResponse(for: self.preparedRouteRequest(route, oauthToken: oauthToken))
  }

  // Shared native route preparation, including OAuth's uncommitted token override.
  func preparedRouteRequest(_ route: Route, oauthToken: String? = nil) throws -> URLRequest {
    let properties = route.requestProperties
    guard let url = URL(string: properties.path, relativeTo: self.serverConfig.apiBaseUrl as URL) else {
      throw ErrorEnvelope.couldNotParseErrorEnvelopeJSON
    }
    var request = self.preparedRequest(
      forURL: url, method: properties.method, query: properties.query
    )
    if let oauthToken { self.addV1AuthenticationToRequest(&request, oauthToken: oauthToken) }
    return request
  }

  public func discoveryPage(params: DiscoveryParams) async throws -> DiscoveryEnvelope {
    let properties = Route.discover(params).requestProperties
    guard let url = URL(string: properties.path, relativeTo: self.serverConfig.apiBaseUrl as URL) else {
      throw ErrorEnvelope.couldNotParseErrorEnvelopeJSON
    }
    return try await self.discoveryResponse(for: self.preparedRequest(
      forURL: url, method: properties.method, query: properties.query
    ))
  }

  public func discoveryPage(paginationURL: String) async throws -> DiscoveryEnvelope {
    guard let url = URL(string: paginationURL) else { throw ErrorEnvelope.invalidPaginationUrl }
    return try await self.discoveryResponse(for: self.preparedRequest(forURL: url))
  }

  public func discoveryActivitySample() async throws -> ActivityEnvelope? {
    let categories: [Activity.Category] = [
      .backing, .cancellation, .failure, .follow, .launch, .shipped, .success, .update
    ]
    let properties = Route.activities(categories: categories, count: 1).requestProperties
    guard let url = URL(string: properties.path, relativeTo: self.serverConfig.apiBaseUrl as URL) else {
      throw ErrorEnvelope.couldNotParseErrorEnvelopeJSON
    }
    let envelope: ActivityEnvelope = try await self.discoveryResponse(for: self.preparedRequest(
      forURL: url, method: properties.method, query: properties.query
    ))
    return envelope
  }

  /// Native async transport using the existing session, authentication and error contract.
  /// URLSession owns cancellation of its data task; no reactive executor or callback bridge.
  private func discoveryResponse<Model: Decodable>(for request: URLRequest) async throws -> Model {
    try Task.checkCancellation()
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await Self.session.data(for: request)
    } catch {
      try Task.checkCancellation()
      throw ErrorEnvelope.couldNotParseErrorEnvelopeJSON
    }
    try Task.checkCancellation()
    return try Self.decodeDiscoveryResponse(data, response: response)
  }

  internal static func decodeDiscoveryResponse<Model: Decodable>(
    _ data: Data, response: URLResponse
  ) throws -> Model {
    guard let response = response as? HTTPURLResponse else {
      throw ErrorEnvelope.couldNotParseErrorEnvelopeJSON
    }
    let headers = response.allHeaderFields as? [String: String]
    guard (200..<300).contains(response.statusCode),
          headers?["Content-Type"]?.hasPrefix("application/json") == true else {
      guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        throw ErrorEnvelope.couldNotParseErrorEnvelopeJSON
      }
      let envelope: ErrorEnvelope
      do { envelope = try ErrorEnvelope.decodeJSONDictionary(json) }
      catch { throw ErrorEnvelope.couldNotDecodeJSON(error) }
      throw envelope
    }
    do { return try JSONDecoder().decode(Model.self, from: data) }
    catch { throw ErrorEnvelope.couldNotDecodeJSON(error) }
  }

  func request<Model: Decodable>(_ route: Route)
    -> SignalProducer<Model, ErrorEnvelope> {
    let properties = route.requestProperties

    guard let URL = URL(string: properties.path, relativeTo: self.serverConfig.apiBaseUrl as URL) else {
      fatalError(
        "URL(string: \(properties.path), relativeToURL: \(self.serverConfig.apiBaseUrl)) == nil"
      )
    }

    return Service.session.rac_dataResponse(
      preparedRequest(forURL: URL, method: properties.method, query: properties.query),
      uploading: properties.file.map { ($1, $0.rawValue) }
    )
    .flatMap(self.decodeModelToSignal)
  }

  func request<Model: Decodable>(_ route: Route) -> AnyPublisher<Model, ErrorEnvelope> {
    let properties = route.requestProperties

    guard let URL = URL(string: properties.path, relativeTo: self.serverConfig.apiBaseUrl as URL) else {
      fatalError(
        "URL(string: \(properties.path), relativeToURL: \(self.serverConfig.apiBaseUrl)) == nil"
      )
    }

    return Service.session.combine_dataResponse(
      preparedRequest(forURL: URL, method: properties.method, query: properties.query),
      uploading: properties.file.map { ($1, $0.rawValue) }
    ).handle_combine_dataResponse(service: self)
  }

  func requestWithAuthentication<Model: Decodable>(
    _ route: Route,
    oauthToken: String
  ) -> AnyPublisher<Model, ErrorEnvelope> {
    let properties = route.requestProperties

    guard let URL = URL(string: properties.path, relativeTo: self.serverConfig.apiBaseUrl as URL) else {
      fatalError(
        "URL(string: \(properties.path), relativeToURL: \(self.serverConfig.apiBaseUrl)) == nil"
      )
    }

    var preparedRequest = preparedRequest(forURL: URL, method: properties.method, query: properties.query)
    addV1AuthenticationToRequest(&preparedRequest, oauthToken: oauthToken)

    return Service.session.combine_dataResponse(
      preparedRequest,
      uploading: properties.file.map { ($1, $0.rawValue) }
    ).handle_combine_dataResponse(service: self)
  }

  func requestPaginationDecodable<Model: Decodable>(_ paginationUrl: String)
    -> SignalProducer<Model, ErrorEnvelope> {
    guard let paginationUrl = URL(string: paginationUrl) else {
      return .init(error: .invalidPaginationUrl)
    }

    return Service.session
      .rac_dataResponse(preparedRequest(forURL: paginationUrl))
      .flatMap(self.decodeModelToSignal)
  }

  func requestPaginationDecodable<Model: Decodable>(_ paginationUrl: String)
    -> AnyPublisher<Model, ErrorEnvelope> {
    guard let paginationUrl = URL(string: paginationUrl) else {
      fatalError("Invalid pagination URL \(paginationUrl)")
    }

    return Service.session
      .combine_dataResponse(preparedRequest(forURL: paginationUrl))
      .handle_combine_dataResponse(service: self)
  }
}

extension Publisher where Output == Data, Failure == ErrorEnvelope {
  func handle_combine_dataResponse<Model: Decodable>(service: Service) -> AnyPublisher<Model, ErrorEnvelope> {
    return self
      .tryMap { data in
        let result: Result<Model?, ErrorEnvelope> = service
          .decodeModelToResult(data: data, ofType: Model.self)

        switch result {
        case let .success(value):
          return value
        case let .failure(error):
          throw error
        }
      }
      .compactMap { $0 }
      .mapError { error in
        error as! ErrorEnvelope
      }.eraseToAnyPublisher()
  }
}
