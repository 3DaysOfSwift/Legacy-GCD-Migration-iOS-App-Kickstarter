import Apollo
import Combine
import Foundation
import GraphAPI
import Prelude
import ReactiveExtensions
import ReactiveSwift
import UIKit

public extension Bundle {
  var _buildVersion: String {
    return (self.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
  }
}

/**
 A `ServerType` that requests data from an API webservice.
 */
public struct Service: ServiceType {
  public let appId: String
  public let serverConfig: ServerConfigType
  public let oauthToken: OauthTokenAuthType?
  public let language: String
  public let currency: String
  public let buildVersion: String
  public let deviceIdentifier: String
  public let apolloClient: ApolloClientType?

  public init(
    appId: String = Bundle.main.bundleIdentifier ?? "com.kickstarter.kickstarter",
    serverConfig: ServerConfigType = ServerConfig.production,
    oauthToken: OauthTokenAuthType? = nil,
    language: String = "en",
    currency: String = "USD",
    buildVersion: String = Bundle.main._buildVersion,
    deviceIdentifier: String = UIDevice.current.identifierForVendor.coalesceWith(UUID()).uuidString,
    apolloClient: ApolloClientType? = nil
  ) {
    self.appId = appId
    self.serverConfig = serverConfig
    self.oauthToken = oauthToken
    self.language = language
    self.currency = currency
    self.buildVersion = buildVersion
    self.deviceIdentifier = deviceIdentifier
    /// Dummy client, only required to satisfy `ApolloClientType` protocol, not used.
    self.apolloClient = apolloClient

    // Global override required for injecting custom User-Agent header in ajax requests
    UserDefaults.standard.register(defaults: ["UserAgent": Service.userAgent])

    // Configure GraphQL Client
    GraphQL.shared.configure(
      with: serverConfig.graphQLEndpointUrl,
      headers: self.defaultHeaders,
      additionalHeaders: { [:] }
    )
  }

  public func login(_ oauthToken: OauthTokenAuthType) -> Service {
    return Service(
      appId: self.appId,
      serverConfig: self.serverConfig,
      oauthToken: oauthToken,
      language: self.language,
      buildVersion: self.buildVersion
    )
  }

  public func logout() -> Service {
    return Service(
      appId: self.appId,
      serverConfig: self.serverConfig,
      oauthToken: nil,
      language: self.language,
      buildVersion: self.buildVersion
    )
  }

  public func fetch<Q: GraphQLQuery>(query: Q) async throws -> Q.Data? {
    let client = AsyncApolloClient(client: GraphQL.shared.client)
    return try await client.fetch(query).data
  }

  @MainActor public func fetchSearchPage(query: GraphAPI.SearchQuery) async throws -> SearchPageResponse {
    try await self.cancellableQuery(query, map: { SearchPageResponse($0) })
  }

  @MainActor public func fetchSearchCategories() async throws -> RootCategoriesEnvelope {
    try await self.cancellableQuery(GraphAPI.FetchRootCategoriesQuery(),
      map: { RootCategoriesEnvelope.envelope(from: $0) })
  }

  @MainActor public func fetchSearchDefaultLocations() async throws -> [Location] {
    try await self.cancellableQuery(GraphAPI.DefaultLocationsQuery(first: 5),
      map: { Location.locations(from: $0) })
  }

  @MainActor public func fetchSearchLocations(term: String) async throws -> [Location] {
    try await self.cancellableQuery(
      GraphAPI.LocationsByTermQuery(term: .some(term), first: 10),
      map: { Location.locations(from: $0) })
  }

  public func triggerThirdPartyEventInput(input: TriggerThirdPartyEventInput)
    -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
    return GraphQL.shared.client
      .perform(
        mutation: GraphAPI
          .TriggerThirdPartyEventMutation(input: GraphAPI.TriggerThirdPartyEventInput.from(input))
      )
      .flatMap { _ in
        SignalProducer(value: EmptyResponseEnvelope())
      }
  }

  public func createFlaggingInputCombine(input: CreateFlaggingInput)
    -> AnyPublisher<EmptyResponseEnvelope, ErrorEnvelope> {
    return GraphQL.shared.client
      .perform(
        mutation: GraphAPI
          .CreateFlaggingMutation(input: GraphAPI.CreateFlaggingInput.from(input))
      )
      .map { _ in
        EmptyResponseEnvelope()
      }
      .eraseToAnyPublisher()
  }

  @MainActor public func fetchProjectFlaggingOptions() async throws -> [ReportProjectInfoListItem] {
    try await self.cancellableQuery(
      GraphAPI.FlaggingOptionsQuery(contentType: GraphQLEnum(.project)),
      map: { ReportProjectInfoListItem.items(from: $0) }
    )
  }

  public func previewUrl(forDraft draft: UpdateDraft) -> URL? {
    return self.serverConfig.apiBaseUrl
      .appendingPathComponent("/v1/projects/\(draft.update.projectId)/updates/draft/preview")
  }

  public func fetchDiscovery_combine(paginationUrl: String)
    -> AnyPublisher<DiscoveryEnvelope, ErrorEnvelope> {
    return requestPaginationDecodable(paginationUrl)
  }

  public func fetchDiscovery_combine(params: DiscoveryParams)
    -> AnyPublisher<DiscoveryEnvelope, ErrorEnvelope> {
    return request(.discover(params))
  }

  public func fetchGraphUserEmailCombine()
    -> AnyPublisher<UserEnvelope<GraphUserEmail>, ErrorEnvelope> {
    GraphQL.shared.client
      .fetch(query: GraphAPI.FetchUserEmailQuery())
      .mapFetchResults { (data: GraphAPI.FetchUserEmailQuery.Data) -> UserEnvelope<GraphUserEmail>? in
        UserEnvelope<GraphUserEmail>.userEnvelope(from: data)
      }
  }

  public func fetchGraphUserSetupCombine()
    -> AnyPublisher<UserEnvelope<GraphUserSetup>, ErrorEnvelope> {
    GraphQL.shared.client
      .fetch(query: GraphAPI.FetchUserSetupQuery())
      .mapFetchResults { (data: GraphAPI.FetchUserSetupQuery.Data) -> UserEnvelope<GraphUserSetup>? in
        UserEnvelope<GraphUserSetup>.userEnvelope(from: data)
      }
  }



  public func fetchProject_combine(project: Project) -> AnyPublisher<Project, ErrorEnvelope> {
    return request(.project(.id(project.id)))
  }

  public func fetchUserSelf_combine(withOAuthToken token: String) -> AnyPublisher<User, ErrorEnvelope> {
    return requestWithAuthentication(.userSelf, oauthToken: token)
  }

  public func exchangeTokenForOAuthToken(params: OAuthTokenExchangeParams)
    -> AnyPublisher<OAuthTokenExchangeResponse, ErrorEnvelope> {
    return request(.exchangeToken(params: params))
  }

  public func updateRewardReceived(
    backingId: String,
    rewardReceived: Bool
  ) -> AnyPublisher<Bool, ErrorEnvelope> {
    let input = GraphAPI.UpdateBackerCompletedInput(id: backingId, backerCompleted: rewardReceived)
    let mutation = GraphAPI.UpdateBackerCompletedMutation(input: input)
    return GraphQL.shared.client
      .perform(mutation: mutation)
      .map { data -> Bool in
        // Verify success by confirming response value is equal to input.
        data.updateBackerCompleted?.backing?.backerCompleted == rewardReceived
      }
      .eraseToAnyPublisher()
  }

  /**
   Post Campaign Pledge Validation.
   - parameter checkoutId: The Checkout Id..
   - parameter paymentSourceId: The id of the payment source.
   - parameter paymentIntentClientSecret: The client secret returned from our CreatePaymentIntent Mutation.
   */

  public func confirmBackingAddress(
    backingId: String,
    addressId: String
  ) -> AnyPublisher<Bool, ErrorEnvelope> {
    let input = GraphAPI.CreateOrUpdateBackingAddressInput(backingId: backingId, addressId: addressId)
    let mutation = GraphAPI.CreateOrUpdateBackingAddressMutation(input: input)
    return GraphQL.shared.client
      .perform(mutation: mutation)
      .map { data in
        data.createOrUpdateBackingAddress?.success ?? false
      }
      .eraseToAnyPublisher()
  }

  public func fetchPledgedProjects(
    tierTypes: [PledgeProjectsOverviewSort],
    cursor: String? = nil,
    limit: Int? = nil
  ) -> AnyPublisher<GraphAPI.FetchPledgedProjectsQuery.Data, ErrorEnvelope> {
    GraphQL.shared.client
      .fetch(query: GraphAPI.FetchPledgedProjectsQuery(
        first: GraphQLNullable.someOrNil(limit),
        after: GraphQLNullable.someOrNil(cursor),
        tierTypes: GraphQLNullable.some(tierTypes.map { GraphQLEnum($0) })
      ))
      .eraseToAnyPublisher()
  }
}
