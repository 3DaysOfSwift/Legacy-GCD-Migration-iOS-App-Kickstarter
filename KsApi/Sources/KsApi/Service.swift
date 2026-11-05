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

  public func addImage(file fileURL: URL, toDraft draft: UpdateDraft)
    -> SignalProducer<UpdateDraft.Image, ErrorEnvelope> {
    return request(Route.addImage(fileUrl: fileURL, toDraft: draft))
  }

  public func fetch<Q: GraphQLQuery>(query: Q) -> SignalProducer<Q.Data, ErrorEnvelope> {
    GraphQL.shared.client.fetch(query: query)
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

  public func addUserToSecretRewardGroup(token: String, forProject param: Param)
    -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
    let input = GraphAPI.AddUserToSecretRewardGroupInput.from(token: token, forProject: param)
    return GraphQL.shared.client
      .perform(
        mutation: GraphAPI.AddUserToSecretRewardGroupMutation(input: input)
      )
      .flatMap { _ in
        SignalProducer(value: EmptyResponseEnvelope())
      }
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

  public func createFlaggingInput(input: CreateFlaggingInput)
    -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
    return GraphQL.shared.client
      .perform(
        mutation: GraphAPI
          .CreateFlaggingMutation(input: GraphAPI.CreateFlaggingInput.from(input))
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

  public func delete(image: UpdateDraft.Image, fromDraft draft: UpdateDraft)
    -> SignalProducer<UpdateDraft.Image, ErrorEnvelope> {
    return request(.deleteImage(image, fromDraft: draft))
  }

  public func previewUrl(forDraft draft: UpdateDraft) -> URL? {
    return self.serverConfig.apiBaseUrl
      .appendingPathComponent("/v1/projects/\(draft.update.projectId)/updates/draft/preview")
  }

  public func fetchActivities(count: Int?) -> SignalProducer<ActivityEnvelope, ErrorEnvelope> {
    let categories: [Activity.Category] = [
      .backing,
      .cancellation,
      .failure,
      .follow,
      .launch,
      .shipped,
      .success,
      .update
    ]
    return request(.activities(categories: categories, count: count))
  }

  public func fetchActivities(paginationUrl: String)
    -> SignalProducer<ActivityEnvelope, ErrorEnvelope> {
    return requestPaginationDecodable(paginationUrl)
  }

  // FIXME: Should be able to convert this to Apollo as it uses /v1 but check its' use cases first.
  public func fetchBacking(forProject project: Project, forUser user: User)
    -> SignalProducer<Backing, ErrorEnvelope> {
    return request(.backing(projectId: project.id, backerId: user.id))
  }

  public func fetchDiscovery(paginationUrl: String)
    -> SignalProducer<DiscoveryEnvelope, ErrorEnvelope> {
    return requestPaginationDecodable(paginationUrl)
  }

  public func fetchDiscovery(params: DiscoveryParams)
    -> SignalProducer<DiscoveryEnvelope, ErrorEnvelope> {
    if !params.validForAPIV1() {
      assert(
        false,
        "Using a field which was added for GraphQL support in API V1. This param may have unexpected effects on an API V1 call."
      )
    }
    return request(.discover(params))
  }

  public func fetchDiscovery_combine(paginationUrl: String)
    -> AnyPublisher<DiscoveryEnvelope, ErrorEnvelope> {
    return requestPaginationDecodable(paginationUrl)
  }

  public func fetchDiscovery_combine(params: DiscoveryParams)
    -> AnyPublisher<DiscoveryEnvelope, ErrorEnvelope> {
    return request(.discover(params))
  }

  public func fetchGraphCategories()
    -> SignalProducer<RootCategoriesEnvelope, ErrorEnvelope> {
    return GraphQL.shared.client
      .fetch(query: GraphAPI.FetchRootCategoriesQuery())
      .map(RootCategoriesEnvelope.envelope(from:))
  }

  public func fetchGraphCategory(id: String)
    -> SignalProducer<CategoryEnvelope, ErrorEnvelope> {
    return GraphQL.shared.client
      .fetch(query: GraphAPI.FetchCategoryQuery(id: id))
      .flatMap(CategoryEnvelope.envelopeProducer(from:))
  }

  public func fetchGraphUser(withStoredCards: Bool)
    -> SignalProducer<UserEnvelope<GraphUser>, ErrorEnvelope> {
    return GraphQL.shared.client
      .fetch(query: GraphAPI.FetchUserQuery(withStoredCards: withStoredCards))
      .flatMap(UserEnvelope<GraphUser>.envelopeProducer(from:))
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

  public func fetchBacking(id: Int)
    -> SignalProducer<ProjectAndBackingEnvelope, ErrorEnvelope> {
    return GraphQL.shared.client
      .fetch(
        query: GraphAPI
          .FetchBackingQuery(
            id: "\(id)"
          )
      )
      .flatMap(ProjectAndBackingEnvelope.envelopeProducer(from:))
  }

  /// Fetches backing details including `refundedAmount` in the `paymentIncrements`.
  ///
  /// Use this method exclusively in flows that require displaying refund information,
  /// such as the `ManagePledge` flow where the "Payment Scheduled" component
  /// needs to reflect refunded increments.
  ///
  /// Fetching `refundedAmount` adds significant load to the backend.
  /// Per the Payments team recommendation, this field should only be queried
  /// when absolutely necessary.
  ///
  /// - Parameters:
  ///   - id: The backing ID.

  public func fastFetchProjectPageBase(projectParam: Param)
    -> SignalProducer<Project, ErrorEnvelope> {
    let query = GraphAPI.FastFetchProjectPageBaseQuery(
      projectId: .someOrNil(projectParam.id),
      slug: .someOrNil(projectParam.slug)
    )

    return GraphQL.shared.client
      .fetch(query: query)
      .flatMap { Project.projectProducer(from: $0) }
  }

  public func fastFetchProjectPageExtendedProperties(projectParam: Param, includeStoryRichText: Bool)
    -> SignalProducer<ProjectPageExtraProperties, ErrorEnvelope> {
    let query = GraphAPI.FastFetchProjectPageExtendedPropertiesQuery(
      projectId: .someOrNil(projectParam.id),
      slug: .someOrNil(projectParam.slug),
      storyRichText: includeStoryRichText
    )

    return GraphQL.shared.client
      .fetch(query: query)
      .flatMap { ProjectPageExtraProperties.extraPropertiesProducer(from: $0) }
  }

  /**
    Use case:
   - `ProjectPageViewModel`

   This is the only use case at the moment as it effects the `ProjectPageViewController` directly.
   */
  public func fetchProject(projectParam: Param, includeStoryRichText: Bool)
    -> SignalProducer<Project.ProjectPamphletData, ErrorEnvelope> {
    let query = GraphAPI.FetchProjectByParamQuery(
      projectId: .someOrNil(projectParam.id),
      slug: .someOrNil(projectParam.slug),
      storyRichText: includeStoryRichText
    )

    return GraphQL.shared.client
      .fetch(query: query)
      .flatMap { Project.projectProducer(from: $0) }
  }

  /**
    Use cases:
   - `ManagePledgeViewModel`
   - `CommentsViewModel`
   - `UpdateViewModel`
   - `UpdatePreviewViewModel`
   - `AppDelegateViewModel`

   Eventually this v1 network request can be replaced with `fetchProject(projectParam:)` if we refactor the use cases above in the future.
   */
  public func fetchProject(param: Param) -> SignalProducer<Project, ErrorEnvelope> {
    return request(.project(param))
  }

  public func fetchProjectRewards(projectId: Int)
    -> SignalProducer<[Reward], ErrorEnvelope> {
    let query = GraphAPI
      .FetchProjectRewardsByIdQuery(
        projectId: projectId,
        includeShippingRules: true,
        includePledgeOverTime: false
      )

    return GraphQL.shared.client
      .fetch(query: query)
      .map(Project.projectRewards(from:))
  }

  public func fetchProjectRewards(
    projectId: Int,
    sortedForShippingCountryCode code: String?,
    withNoReward inserter: NoRewardInserter
  ) -> SignalProducer<[Reward], ErrorEnvelope> {
    let graphCountryCode: GraphAPI.CountryCode?
    if let code {
      graphCountryCode = GraphAPI.CountryCode(rawValue: code)
    } else {
      graphCountryCode = nil
    }

    let query = GraphAPI.FetchSortedProjectRewardsByIdQuery(
      projectId: projectId,
      location: GraphQLEnum.caseOrNil(graphCountryCode)
    )

    return GraphQL.shared.client
      .fetch(query: query)
      .map { results in
        Project.projectRewards(from: results, withNoReward: inserter)
      }
  }

  public func fetchProjectRewardsAndPledgeOverTimeData(projectId: Int)
    -> SignalProducer<RewardsAndPledgeOverTimeEnvelope, ErrorEnvelope> {
    let query = GraphAPI
      .FetchProjectRewardsByIdQuery(
        projectId: projectId,
        includeShippingRules: true,
        includePledgeOverTime: true
      )

    return GraphQL.shared.client
      .fetch(query: query)
      .map(Project.projectRewardsAndPledgeOverTimeData(from:))
  }

  public func fetchProject(_ params: DiscoveryParams) -> SignalProducer<DiscoveryEnvelope, ErrorEnvelope> {
    return request(.discover(params |> DiscoveryParams.lens.perPage .~ 1))
  }

  public func fetchProject_combine(project: Project) -> AnyPublisher<Project, ErrorEnvelope> {
    return request(.project(.id(project.id)))
  }

  public func fetchProjectActivities(forProject project: Project) ->
    SignalProducer<ProjectActivityEnvelope, ErrorEnvelope> {
    return request(.projectActivities(project))
  }

  public func fetchProjectActivities(paginationUrl: String)
    -> SignalProducer<ProjectActivityEnvelope, ErrorEnvelope> {
    return requestPaginationDecodable(paginationUrl)
  }

  public func fetchProjectNotifications() -> SignalProducer<[ProjectNotification], ErrorEnvelope> {
    return request(.projectNotifications)
  }

  public func fetchProjects(member: Bool) -> SignalProducer<ProjectsEnvelope, ErrorEnvelope> {
    return request(.projects(member: member))
  }

  public func fetchProjects(paginationUrl url: String) -> SignalProducer<ProjectsEnvelope, ErrorEnvelope> {
    return requestPaginationDecodable(url)
  }

  public func fetchProjectStats(projectId: Int) ->
    SignalProducer<ProjectStatsEnvelope, ErrorEnvelope> {
    return request(.projectStats(projectId: projectId))
  }

  public func fetchRewardAddOnsSelectionViewRewards(
    slug: String,
    shippingEnabled: Bool,
    locationId: String?
  ) -> SignalProducer<Project, ErrorEnvelope> {
    let query = GraphAPI.FetchAddOnsQuery(
      projectSlug: slug,
      shippingEnabled: shippingEnabled,
      locationId: GraphQLNullable.someOrNil(locationId)
    )

    return GraphQL.shared.client
      .fetch(query: query)
      .flatMap(Project.projectProducer(from:))
  }

  public func fastFetchRewardAddOnsSelection(
    baseRewardId: Int,
    countryCode: String
  ) -> SignalProducer<[Reward], ErrorEnvelope> {
    guard let graphCountryCode = GraphAPI.CountryCode(rawValue: countryCode) else {
      assertionFailure("Unable to map selected code to country")
      return SignalProducer(error: .graphError("Invalid country code"))
    }

    let query = GraphAPI.FastFetchAddOnsQuery(
      baseRewardId: "\(baseRewardId)",
      country: .case(graphCountryCode)
    )

    return GraphQL.shared.client
      .fetch(query: query)
      .flatMap(Reward.addOnsProducer(from:))
  }

  public func fetchBackedProjects(
    cursor: String? = nil,
    limit: Int? = nil
  ) -> SignalProducer<FetchMyBackedProjectsQuery.Data, ErrorEnvelope> {
    let query = GraphAPI.FetchMyBackedProjectsQuery(
      first: GraphQLNullable.someOrNil(limit),
      after: GraphQLNullable.someOrNil(cursor)
    )

    return GraphQL.shared.client
      .fetch(query: query)
  }

  public func fetchSavedProjects(
    cursor: String? = nil,
    limit: Int? = nil
  ) -> SignalProducer<FetchMySavedProjectsQuery.Data, ErrorEnvelope> {
    let query = GraphAPI.FetchMySavedProjectsQuery(
      first: GraphQLNullable.someOrNil(limit),
      after: GraphQLNullable.someOrNil(cursor)
    )

    return GraphQL.shared.client
      .fetch(query: query)
  }

  public func fetchRewardShippingRules(projectId: Int, rewardId: Int)
    -> SignalProducer<ShippingRulesEnvelope, ErrorEnvelope> {
    return request(.shippingRules(projectId: projectId, rewardId: rewardId))
  }

  public func fetchSurveyResponse(surveyResponseId id: Int) -> SignalProducer<SurveyResponse, ErrorEnvelope> {
    return request(.surveyResponse(surveyResponseId: id))
  }

  public func fetchUserSelf() -> SignalProducer<User, ErrorEnvelope> {
    return request(.userSelf)
  }

  public func fetchUserSelf_combine(withOAuthToken token: String) -> AnyPublisher<User, ErrorEnvelope> {
    return requestWithAuthentication(.userSelf, oauthToken: token)
  }

  public func fetchUser(userId: Int) -> SignalProducer<User, ErrorEnvelope> {
    return request(.user(userId: userId))
  }

  public func fetchUser(_ user: User) -> SignalProducer<User, ErrorEnvelope> {
    return self.fetchUser(userId: user.id)
  }

  public func fetchUpdate(updateId: Int, projectParam: Param)
    -> SignalProducer<Update, ErrorEnvelope> {
    return request(.update(updateId: updateId, projectParam: projectParam))
  }

  public func fetchUpdateDraft(forProject project: Project) -> SignalProducer<UpdateDraft, ErrorEnvelope> {
    return request(.fetchUpdateDraft(forProject: project))
  }

  public func fetchUnansweredSurveyResponses() -> SignalProducer<[SurveyResponse], ErrorEnvelope> {
    return request(.unansweredSurveyResponses)
  }

  public func exchangeTokenForOAuthToken(params: OAuthTokenExchangeParams)
    -> AnyPublisher<OAuthTokenExchangeResponse, ErrorEnvelope> {
    return request(.exchangeToken(params: params))
  }

  public func backingUpdate(forProject project: Project, forUser user: User, received: Bool) ->
    SignalProducer<Backing, ErrorEnvelope> {
    return request(.backingUpdate(projectId: project.id, backerId: user.id, received: received))
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

  public func followAllFriends() -> SignalProducer<VoidEnvelope, ErrorEnvelope> {
    return request(.followAllFriends)
  }

  public func followFriend(userId id: Int) -> SignalProducer<User, ErrorEnvelope> {
    return request(.followFriend(userId: id))
  }

  public func login(email: String, password: String, code: String?) ->
    SignalProducer<AccessTokenEnvelope, ErrorEnvelope> {
    return request(.login(email: email, password: password, code: code))
  }

  public func login(facebookAccessToken: String, code: String?) ->
    SignalProducer<AccessTokenEnvelope, ErrorEnvelope> {
    return request(.facebookLogin(facebookAccessToken: facebookAccessToken, code: code))
  }

  public func markAsRead(messageThread: MessageThread) -> SignalProducer<MessageThread, ErrorEnvelope> {
    return request(.markAsRead(messageThread))
  }

  public func publish(draft: UpdateDraft) -> SignalProducer<Update, ErrorEnvelope> {
    return request(.publishUpdateDraft(draft))
  }

  public func register(pushToken: String) -> SignalProducer<VoidEnvelope, ErrorEnvelope> {
    return request(.registerPushToken(pushToken))
  }

  public func resetPassword(email: String) -> SignalProducer<User, ErrorEnvelope> {
    return request(.resetPassword(email: email))
  }

  public func searchMessages(query: String, project: Project?)
    -> SignalProducer<MessageThreadsEnvelope, ErrorEnvelope> {
    return request(.searchMessages(query: query, project: project))
  }

  public func sendMessage(body: String, toSubject subject: MessageSubject)
    -> SignalProducer<Message, ErrorEnvelope> {
    return request(.sendMessage(body: body, messageSubject: subject))
  }

  public func unfollowFriend(userId id: Int) -> SignalProducer<VoidEnvelope, ErrorEnvelope> {
    return request(.unfollowFriend(userId: id))
  }

  public func update(draft: UpdateDraft, title: String, body: String, isPublic: Bool)
    -> SignalProducer<UpdateDraft, ErrorEnvelope> {
    return request(.updateUpdateDraft(draft, title: title, body: body, isPublic: isPublic))
  }

  public func updateProjectNotification(_ notification: ProjectNotification)
    -> SignalProducer<ProjectNotification, ErrorEnvelope> {
    return request(.updateProjectNotification(notification: notification))
  }

  public func verifyEmail(withToken token: String)
    -> SignalProducer<EmailVerificationResponseEnvelope, ErrorEnvelope> {
    request(.verifyEmail(accessToken: token))
  }

  public func blockUser(input: BlockUserInput)
    -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
    return GraphQL.shared.client
      .perform(mutation: GraphAPI.BlockUserMutation(input: GraphAPI.BlockUserInput.from(input)))
      .flatMap { _ in
        SignalProducer(value: EmptyResponseEnvelope())
      }
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
