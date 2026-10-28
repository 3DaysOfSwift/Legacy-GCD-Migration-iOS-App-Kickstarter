#if DEBUG
  import Apollo
  import Combine
  import Foundation
  import GraphAPI
  import Prelude
  import ReactiveSwift

  internal struct MockService: ServiceType {
    private let demoCatalog: DemoCatalog?

    internal static func publicDemo() -> MockService {
      let unavailable = ErrorEnvelope.graphError("Accounts and payments are unavailable in this fictional demo.")
      return MockService(loginError: unavailable, signupError: unavailable, demoCatalog: DemoCatalog())
    }

    internal let apolloClient: ApolloClientType?
    internal let appId: String
    internal let serverConfig: ServerConfigType
    internal let oauthToken: OauthTokenAuthType?
    internal let language: String
    internal let currency: String
    internal let buildVersion: String
    internal let deviceIdentifier: String

    fileprivate let addNewCreditCardResult: Result<CreatePaymentSourceEnvelope, ErrorEnvelope>?

    fileprivate let addPaymentSheetPaymentSourceResult: Result<CreatePaymentSourceEnvelope, ErrorEnvelope>?

    fileprivate let addUserToSecretRewardGroup: Result<EmptyResponseEnvelope, ErrorEnvelope>?

    fileprivate let blockUserResult: Result<EmptyResponseEnvelope, ErrorEnvelope>?

    fileprivate let buildPaymentPlanResult: Result<GraphAPI.BuildPaymentPlanQuery.Data, ErrorEnvelope>?

    fileprivate let cancelBackingResult: Result<EmptyResponseEnvelope, ErrorEnvelope>?

    fileprivate let changeCurrencyResult: Result<EmptyResponseEnvelope, ErrorEnvelope>?

    fileprivate let changeEmailResult: Result<EmptyResponseEnvelope, ErrorEnvelope>?

    fileprivate let changePasswordResult: Result<EmptyResponseEnvelope, ErrorEnvelope>?

    fileprivate let createAttributionEventResult: Result<EmptyResponseEnvelope, ErrorEnvelope>?

    fileprivate let createBackingResult: Result<CreateBackingEnvelope, ErrorEnvelope>?

    fileprivate let completeOnSessionCheckoutResult: Result<
      GraphAPI.CompleteOnSessionCheckoutMutation.Data,
      ErrorEnvelope
    >?

    fileprivate let createCheckoutResult: Result<CreateCheckoutEnvelope, ErrorEnvelope>?

    fileprivate let createFlaggingResult: Result<EmptyResponseEnvelope, ErrorEnvelope>?

    fileprivate let fetchFlaggingOptionsResult: Result<GraphAPI.FlaggingOptionsQuery.Data, ErrorEnvelope>?

    fileprivate let createPaymentIntentResult: Result<PaymentIntentEnvelope, ErrorEnvelope>?

    fileprivate let createPasswordResult: Result<EmptyResponseEnvelope, ErrorEnvelope>?

    fileprivate let createStripeSetupIntentResult: Result<ClientSecretEnvelope, ErrorEnvelope>?

    fileprivate let changePaymentMethodResult: Result<ChangePaymentMethodEnvelope, ErrorEnvelope>?

    fileprivate let clearUserUnseenActivityResult: Result<ClearUserUnseenActivityEnvelope, ErrorEnvelope>?

    fileprivate let confirmBackingAddressResult: Result<Bool, ErrorEnvelope>?

    fileprivate let deletePaymentMethodResult: Result<DeletePaymentMethodEnvelope, ErrorEnvelope>?

    fileprivate let triggerThirdPartyEventResult: Result<EmptyResponseEnvelope, ErrorEnvelope>?

    fileprivate let facebookConnectResponse: User?
    fileprivate let facebookConnectError: ErrorEnvelope?

    fileprivate let fetchGraphQLResponses: [(any GraphQLQuery.Type, any GraphAPI.SelectionSet)]?
    /// Explicitly pending legacy requests for tests that isolate another workflow.
    fileprivate let pendingLegacyGraphQLQueries: [any GraphQLQuery.Type]

    fileprivate let fetchActivitiesResponse: [Activity]?
    fileprivate let fetchActivitiesError: ErrorEnvelope?

    fileprivate let fetchBackingResponse: Backing
    fileprivate let backingUpdate: Backing

    fileprivate let fetchGraphCategoryResult: Result<CategoryEnvelope, ErrorEnvelope>?

    fileprivate let fetchGraphCategoriesResult: Result<RootCategoriesEnvelope, ErrorEnvelope>?

    fileprivate let fetchProjectCommentsEnvelopeResult: Result<CommentsEnvelope, ErrorEnvelope>?
    fileprivate let fetchUpdateCommentsEnvelopeResult: Result<CommentsEnvelope, ErrorEnvelope>?

    fileprivate let fetchCommentRepliesEnvelopeResult: Result<CommentRepliesEnvelope, ErrorEnvelope>?

    fileprivate let fetchConfigResponse: Config?

    fileprivate let fetchDiscoveryResponse: DiscoveryEnvelope?
    fileprivate let fetchDiscoveryError: ErrorEnvelope?

    fileprivate let fetchFriendsResponse: FindFriendsEnvelope?
    fileprivate let fetchFriendsError: ErrorEnvelope?

    fileprivate let fetchFriendStatsResponse: FriendStatsEnvelope?
    fileprivate let fetchFriendStatsError: ErrorEnvelope?

    fileprivate let fetchDraftResponse: UpdateDraft?
    fileprivate let fetchDraftError: ErrorEnvelope?

    fileprivate let fetchGraphUserResult: Result<UserEnvelope<GraphUser>, ErrorEnvelope>?
    fileprivate let fetchGraphUserSelfResult: Result<UserEnvelope<User>, ErrorEnvelope>?
    fileprivate let fetchGraphUserEmailResult: Result<UserEnvelope<GraphUserEmail>, ErrorEnvelope>?
    fileprivate let fetchGraphUserSetupResult: Result<UserEnvelope<GraphUserSetup>, ErrorEnvelope>?

    fileprivate let addAttachmentResponse: UpdateDraft.Image?
    fileprivate let addAttachmentError: ErrorEnvelope?
    fileprivate let removeAttachmentResponse: UpdateDraft.Image?
    fileprivate let removeAttachmentError: ErrorEnvelope?

    fileprivate let publishUpdateError: ErrorEnvelope?

    fileprivate let fetchBackerSavedProjectsResponse: GraphAPI.FetchMySavedProjectsQuery.Data?
    fileprivate let fetchBackerBackedProjectsResponse: GraphAPI.FetchMyBackedProjectsQuery.Data?

    fileprivate let fetchProjectAndBackingResult:
      Result<ProjectAndBackingEnvelope, ErrorEnvelope>?

    fileprivate let fetchManagePledgeViewBackingResult: Result<Backing, ErrorEnvelope>?

    fileprivate let fetchMessageThreadResult: Result<MessageThread?, ErrorEnvelope>?
    fileprivate let fetchMessageThreadsResponse: [MessageThread]

    fileprivate let fetchPledgedProjectsResult:
      Result<GraphAPI.FetchPledgedProjectsQuery.Data, ErrorEnvelope>?

    /**
     FIXME: Eventually combine `fetchProjectEnvelopeResult` and `fetchProjectPamphletEnvelopeResult` once all calls returning `Project` are using GQL. https://kickstarter.atlassian.net/browse/NTV-219
     */
    fileprivate let fetchProjectEnvelopeResult: Result<Project, ErrorEnvelope>?
    fileprivate let fastFetchProjectPageResult: (
      Result<Project, ErrorEnvelope>,
      Result<ProjectPageExtraProperties, ErrorEnvelope>
    )?
    fileprivate let fetchProjectPamphletEnvelopeResult: Result<Project.ProjectPamphletData, ErrorEnvelope>?
    fileprivate let fetchProjectFriendsEnvelopeResult: Result<[User], ErrorEnvelope>?
    fileprivate let fetchProjectRewardsAndPledgeOverTimeDataResult: Result<
      RewardsAndPledgeOverTimeEnvelope,

      ErrorEnvelope
    >?
    fileprivate let fetchProjectRewardsEnvelopeResult: Result<[Reward], ErrorEnvelope>?
    fileprivate let fetchProjectsResponse: [Project]?
    fileprivate let fetchProjectsError: ErrorEnvelope?

    fileprivate let fetchProjectNotificationsResponse: [ProjectNotification]

    fileprivate let fetchProjectStatsResponse: ProjectStatsEnvelope?
    fileprivate let fetchProjectStatsError: ErrorEnvelope?

    fileprivate let fetchRewardAddOnsSelectionViewRewardsResult:
      Result<Project, ErrorEnvelope>?

    fileprivate let fetchShippingRulesResult: Result<[ShippingRule], ErrorEnvelope>?

    fileprivate let fetchSurveyResponseResponse: SurveyResponse?
    fileprivate let fetchSurveyResponseError: ErrorEnvelope?

    fileprivate let fetchUnansweredSurveyResponsesResponse: [SurveyResponse]

    fileprivate let fetchUpdateResponse: Update

    fileprivate let fetchUserResult: Result<User, ErrorEnvelope>?

    fileprivate let fetchUserSelfResponse: User?
    fileprivate let fetchUserSelfError: ErrorEnvelope?

    fileprivate let followFriendError: ErrorEnvelope?

    fileprivate let incrementVideoCompletionError: ErrorEnvelope?

    fileprivate let incrementVideoStartError: ErrorEnvelope?

    fileprivate let postCommentResult: Result<Comment, ErrorEnvelope>?

    fileprivate let fetchProjectActivitiesResponse: [Activity]?
    fileprivate let fetchProjectActivitiesError: ErrorEnvelope?

    fileprivate let loginResponse: AccessTokenEnvelope?
    fileprivate let loginError: ErrorEnvelope?
    fileprivate let resendCodeResponse: ErrorEnvelope?
    fileprivate let resendCodeError: ErrorEnvelope?

    fileprivate let resetPasswordResponse: User?
    fileprivate let resetPasswordError: ErrorEnvelope?

    fileprivate let sendEmailVerificationResult: Result<EmptyResponseEnvelope, ErrorEnvelope>?

    fileprivate let signInWithAppleResult: Result<SignInWithAppleEnvelope, ErrorEnvelope>?

    fileprivate let signupResponse: AccessTokenEnvelope?
    fileprivate let signupError: ErrorEnvelope?
    fileprivate let tokenExchangeResponse: OAuthTokenExchangeResponse?

    fileprivate let unfollowFriendError: ErrorEnvelope?

    fileprivate let updateRewardReceivedResult: Result<Bool, ErrorEnvelope>?

    fileprivate let updateBackingResult: Result<UpdateBackingEnvelope, ErrorEnvelope>?

    fileprivate let updateDraftError: ErrorEnvelope?

    fileprivate let updatePledgeResult: Result<UpdatePledgeEnvelope, ErrorEnvelope>?

    fileprivate let updateProjectNotificationResponse: ProjectNotification?
    fileprivate let updateProjectNotificationError: ErrorEnvelope?

    fileprivate let updateUserSelfError: ErrorEnvelope?

    fileprivate let unwatchProjectMutationResult: Result<
      WatchProjectResponseEnvelope,
      ErrorEnvelope
    >?

    fileprivate let validateCheckoutResult: Result<ValidateCheckoutEnvelope, ErrorEnvelope>?

    fileprivate let verifyEmailResult: Result<EmailVerificationResponseEnvelope, ErrorEnvelope>?

    fileprivate let watchProjectMutationResult: Result<
      WatchProjectResponseEnvelope,
      ErrorEnvelope
    >?

    internal init(
      appId: String = "com.kickstarter.kickstarter.mock",
      serverConfig: ServerConfigType,
      oauthToken: OauthTokenAuthType?,
      language: String,
      currency: String,
      buildVersion: String = "1",
      deviceIdentifier: String = "DEADBEEF-DEAD-BEEF-DEAD-DEADBEEFBEEF",
      apolloClient: ApolloClientType? = nil
    ) {
      self.init(
        appId: appId,
        serverConfig: serverConfig,
        oauthToken: oauthToken,
        language: language,
        currency: currency,
        buildVersion: buildVersion,
        deviceIdentifier: deviceIdentifier,
        apolloClient: apolloClient
      )
    }

    internal init(
      appId: String = "com.kickstarter.kickstarter.mock",
      serverConfig: ServerConfigType = ServerConfig.production,
      oauthToken: OauthTokenAuthType? = nil,
      language: String = "en",
      currency: String = "USD",
      buildVersion: String = "1",
      deviceIdentifier: String = "DEADBEEF-DEAD-BEEF-DEAD-DEADBEEFBEEF",
      addNewCreditCardResult: Result<CreatePaymentSourceEnvelope, ErrorEnvelope>? = nil,
      addPaymentSheetPaymentSourceResult: Result<CreatePaymentSourceEnvelope, ErrorEnvelope>? = nil,
      addUserToSecretRewardGroup: Result<EmptyResponseEnvelope, ErrorEnvelope>? = nil,
      apolloClient: ApolloClientType? = nil,
      blockUserResult: Result<EmptyResponseEnvelope, ErrorEnvelope>? = nil,
      buildPaymentPlanResult: Result<GraphAPI.BuildPaymentPlanQuery.Data, ErrorEnvelope>? = nil,
      cancelBackingResult: Result<EmptyResponseEnvelope, ErrorEnvelope>? = nil,
      changeEmailResult: Result<EmptyResponseEnvelope, ErrorEnvelope>? = nil,
      changePasswordResult: Result<EmptyResponseEnvelope, ErrorEnvelope>? = nil,
      createAttributionEventResult: Result<EmptyResponseEnvelope, ErrorEnvelope>? = nil,
      createBackingResult: Result<CreateBackingEnvelope, ErrorEnvelope>? = nil,
      completeOnSessionCheckoutResult: Result<
        GraphAPI.CompleteOnSessionCheckoutMutation.Data,
        ErrorEnvelope
      >? = nil,
      createCheckoutResult: Result<CreateCheckoutEnvelope, ErrorEnvelope>? = nil,
      createFlaggingResult: Result<EmptyResponseEnvelope, ErrorEnvelope>? = nil,
      fetchFlaggingOptionsResult: Result<GraphAPI.FlaggingOptionsQuery.Data, ErrorEnvelope>? = nil,
      createPaymentIntentResult: Result<PaymentIntentEnvelope, ErrorEnvelope>? = nil,
      createPasswordResult: Result<EmptyResponseEnvelope, ErrorEnvelope>? = nil,
      createStripeSetupIntentResult: Result<ClientSecretEnvelope, ErrorEnvelope>? = nil,
      changeCurrencyResult: Result<EmptyResponseEnvelope, ErrorEnvelope>? = nil,
      changePaymentMethodResult: Result<ChangePaymentMethodEnvelope, ErrorEnvelope>? = nil,
      confirmBackingAddressResult: Result<Bool, ErrorEnvelope>? = nil,
      deletePaymentMethodResult: Result<DeletePaymentMethodEnvelope, ErrorEnvelope>? = nil,
      triggerThirdPartyEventResult: Result<EmptyResponseEnvelope, ErrorEnvelope>? = nil,
      clearUserUnseenActivityResult: Result<ClearUserUnseenActivityEnvelope, ErrorEnvelope>? = nil,
      facebookConnectResponse: User? = nil,
      facebookConnectError: ErrorEnvelope? = nil,
      fetchGraphQLResponses: [(any GraphQLQuery.Type, any GraphAPI.SelectionSet)]? = nil,
      pendingLegacyGraphQLQueries: [any GraphQLQuery.Type] = [],
      fetchActivitiesResponse: [Activity]? = nil,
      fetchActivitiesError: ErrorEnvelope? = nil,
      fetchBackingResponse: Backing = .template,
      backingUpdate: Backing = .template,
      fetchBackerSavedProjectsResponse: GraphAPI.FetchMySavedProjectsQuery.Data? = nil,
      fetchBackerBackedProjectsResponse: GraphAPI.FetchMyBackedProjectsQuery.Data? = nil,
      fetchGraphCategoryResult: Result<CategoryEnvelope, ErrorEnvelope>? = nil,
      fetchGraphCategoriesResult: Result<RootCategoriesEnvelope, ErrorEnvelope>? = nil,
      fetchCommentsResponse _: [ActivityComment]? = nil,
      fetchCommentsError _: ErrorEnvelope? = nil,
      fetchProjectCommentsEnvelopeResult: Result<CommentsEnvelope, ErrorEnvelope>? = nil,
      fetchUpdateCommentsEnvelopeResult: Result<CommentsEnvelope, ErrorEnvelope>? = nil,
      fetchCommentRepliesEnvelopeResult: Result<CommentRepliesEnvelope, ErrorEnvelope>? = nil,
      fetchConfigResponse: Config? = nil,
      fetchDiscoveryResponse: DiscoveryEnvelope? = nil,
      fetchDiscoveryError: ErrorEnvelope? = nil,
      fetchFriendsResponse: FindFriendsEnvelope? = nil,
      fetchFriendsError: ErrorEnvelope? = nil,
      fetchFriendStatsResponse: FriendStatsEnvelope? = nil,
      fetchFriendStatsError: ErrorEnvelope? = nil,
      fetchDraftResponse: UpdateDraft? = nil,
      fetchDraftError: ErrorEnvelope? = nil,
      fetchGraphUserResult: Result<UserEnvelope<GraphUser>, ErrorEnvelope>? = nil,
      fetchGraphUserSelfResult: Result<UserEnvelope<User>, ErrorEnvelope>? = nil,
      fetchGraphUserEmailResult: Result<UserEnvelope<GraphUserEmail>, ErrorEnvelope>? = nil,
      fetchGraphUserSetupResult: Result<UserEnvelope<GraphUserSetup>, ErrorEnvelope>? = nil,
      addAttachmentResponse: UpdateDraft.Image? = nil,
      addAttachmentError: ErrorEnvelope? = nil,
      removeAttachmentResponse: UpdateDraft.Image? = nil,
      removeAttachmentError: ErrorEnvelope? = nil,
      publishUpdateError: ErrorEnvelope? = nil,
      fetchManagePledgeViewBackingResult: Result<Backing, ErrorEnvelope>? = nil,
      fetchProjectAndBackingResult: Result<ProjectAndBackingEnvelope, ErrorEnvelope>? = nil,
      fetchMessageThreadResult: Result<MessageThread?, ErrorEnvelope>? = nil,
      fetchMessageThreadsResponse: [MessageThread]? = nil,
      fetchPledgedProjectsResult: Result<GraphAPI.FetchPledgedProjectsQuery.Data, ErrorEnvelope>? = nil,
      fetchProjectResult: Result<Project, ErrorEnvelope>? = nil,
      fastFetchProjectPage: (
        Result<Project, ErrorEnvelope>,
        Result<ProjectPageExtraProperties, ErrorEnvelope>
      )? = nil,
      fetchProjectPamphletResult: Result<Project.ProjectPamphletData, ErrorEnvelope>? = nil,
      fetchProjectFriendsResult: Result<[User], ErrorEnvelope>? = nil,
      fetchProjectRewardsAndPledgeOverTimeDataResult: Result<
        RewardsAndPledgeOverTimeEnvelope,

        ErrorEnvelope
      >? = nil,
      fetchProjectRewardsResult: Result<[Reward], ErrorEnvelope>? = nil,
      fetchProjectActivitiesResponse: [Activity]? = nil,
      fetchProjectActivitiesError: ErrorEnvelope? = nil,
      fetchProjectNotificationsResponse: [ProjectNotification]? = nil,
      fetchProjectsResponse: [Project]? = nil,
      fetchProjectsError: ErrorEnvelope? = nil,
      fetchProjectStatsResponse: ProjectStatsEnvelope? = nil,
      fetchProjectStatsError: ErrorEnvelope? = nil,
      fetchShippingRulesResult: Result<[ShippingRule], ErrorEnvelope>? = nil,
      fetchUserProjectsBackedError _: ErrorEnvelope? = nil,
      fetchUserResult: Result<User, ErrorEnvelope>? = nil,
      fetchUserSelfResponse: User? = nil,
      followFriendError: ErrorEnvelope? = nil,
      incrementVideoCompletionError: ErrorEnvelope? = nil,
      incrementVideoStartError: ErrorEnvelope? = nil,
      fetchRewardAddOnsSelectionViewRewardsResult: Result<Project, ErrorEnvelope>? =
        nil,
      fetchSurveyResponseResponse: SurveyResponse? = nil,
      fetchSurveyResponseError: ErrorEnvelope? = nil,
      fetchUnansweredSurveyResponsesResponse: [SurveyResponse] = [],
      fetchUpdateResponse: Update = .template,
      fetchUserSelfError: ErrorEnvelope? = nil,
      postCommentResult: Result<Comment, ErrorEnvelope>? = nil,
      loginResponse: AccessTokenEnvelope? = nil,
      loginError: ErrorEnvelope? = nil,
      tokenExchangeResponse: OAuthTokenExchangeResponse? = nil,
      resendCodeResponse: ErrorEnvelope? = nil,
      resendCodeError: ErrorEnvelope? = nil,
      resetPasswordResponse: User? = nil,
      resetPasswordError: ErrorEnvelope? = nil,
      sendEmailVerificationResult: Result<EmptyResponseEnvelope, ErrorEnvelope>? = nil,
      signInWithAppleResult: Result<SignInWithAppleEnvelope, ErrorEnvelope>? = nil,
      signupResponse: AccessTokenEnvelope? = nil,
      signupError: ErrorEnvelope? = nil,
      unfollowFriendError: ErrorEnvelope? = nil,
      updateRewardReceivedResult: Result<Bool, ErrorEnvelope>? = nil,
      updateBackingResult: Result<UpdateBackingEnvelope, ErrorEnvelope>? = nil,
      updateDraftError: ErrorEnvelope? = nil,
      updatePledgeResult: Result<UpdatePledgeEnvelope, ErrorEnvelope>? = nil,
      updateProjectNotificationResponse: ProjectNotification? = nil,
      updateProjectNotificationError: ErrorEnvelope? = nil,
      updateUserSelfError: ErrorEnvelope? = nil,
      unwatchProjectMutationResult: Result<WatchProjectResponseEnvelope, ErrorEnvelope>? = nil,
      validateCheckoutResult: Result<ValidateCheckoutEnvelope, ErrorEnvelope>? = nil,
      verifyEmailResult: Result<EmailVerificationResponseEnvelope, ErrorEnvelope>? = nil,
      watchProjectMutationResult: Result<WatchProjectResponseEnvelope, ErrorEnvelope>? = nil,
      demoCatalog: DemoCatalog? = nil
    ) {
      self.demoCatalog = demoCatalog
      self.appId = appId
      self.serverConfig = serverConfig
      self.oauthToken = oauthToken
      self.language = language
      self.currency = currency
      self.buildVersion = buildVersion
      self.deviceIdentifier = deviceIdentifier

      self.addNewCreditCardResult = addNewCreditCardResult

      self.addPaymentSheetPaymentSourceResult = addPaymentSheetPaymentSourceResult

      self.addUserToSecretRewardGroup = addUserToSecretRewardGroup

      self.apolloClient = apolloClient ?? MockGraphQLClient.shared.client

      self.blockUserResult = blockUserResult

      self.buildPaymentPlanResult = buildPaymentPlanResult

      self.cancelBackingResult = cancelBackingResult

      self.changeEmailResult = changeEmailResult

      self.changeCurrencyResult = changeCurrencyResult

      self.changePasswordResult = changePasswordResult

      self.clearUserUnseenActivityResult = clearUserUnseenActivityResult

      self.createAttributionEventResult = createAttributionEventResult

      self.createBackingResult = createBackingResult

      self.completeOnSessionCheckoutResult = completeOnSessionCheckoutResult

      self.createCheckoutResult = createCheckoutResult

      self.createFlaggingResult = createFlaggingResult
      self.fetchFlaggingOptionsResult = fetchFlaggingOptionsResult

      self.createPaymentIntentResult = createPaymentIntentResult

      self.createPasswordResult = createPasswordResult

      self.createStripeSetupIntentResult = createStripeSetupIntentResult

      self.changePaymentMethodResult = changePaymentMethodResult

      self.confirmBackingAddressResult = confirmBackingAddressResult

      self.deletePaymentMethodResult = deletePaymentMethodResult

      self.triggerThirdPartyEventResult = triggerThirdPartyEventResult

      self.facebookConnectResponse = facebookConnectResponse
      self.facebookConnectError = facebookConnectError

      self.fetchGraphQLResponses = fetchGraphQLResponses
      self.pendingLegacyGraphQLQueries = pendingLegacyGraphQLQueries

      self.fetchActivitiesResponse = fetchActivitiesResponse ?? [
        .template,
        .template |> Activity.lens.category .~ .backing,
        .template |> Activity.lens.category .~ .success
      ]

      self.fetchActivitiesError = fetchActivitiesError

      self.fetchBackingResponse = fetchBackingResponse

      self.fetchBackerSavedProjectsResponse = fetchBackerSavedProjectsResponse
      self.fetchBackerBackedProjectsResponse = fetchBackerBackedProjectsResponse

      self.backingUpdate = backingUpdate

      self.fetchGraphCategoryResult = fetchGraphCategoryResult

      self.fetchGraphCategoriesResult = fetchGraphCategoriesResult

      self.fetchGraphUserResult = fetchGraphUserResult
      self.fetchGraphUserSelfResult = fetchGraphUserSelfResult
      self.fetchGraphUserEmailResult = fetchGraphUserEmailResult
      self.fetchGraphUserSetupResult = fetchGraphUserSetupResult

      self.fetchPledgedProjectsResult = fetchPledgedProjectsResult

      self.fetchProjectCommentsEnvelopeResult = fetchProjectCommentsEnvelopeResult
      self.fetchUpdateCommentsEnvelopeResult = fetchUpdateCommentsEnvelopeResult

      self.fetchCommentRepliesEnvelopeResult = fetchCommentRepliesEnvelopeResult

      self.fetchConfigResponse = fetchConfigResponse ?? .template

      self.fetchDiscoveryResponse = fetchDiscoveryResponse
      self.fetchDiscoveryError = fetchDiscoveryError

      self.fetchFriendsResponse = fetchFriendsResponse
      self.fetchFriendsError = fetchFriendsError

      self.fetchFriendStatsResponse = fetchFriendStatsResponse
      self.fetchFriendStatsError = fetchFriendStatsError

      self.fetchDraftResponse = fetchDraftResponse
      self.fetchDraftError = fetchDraftError

      self.addAttachmentResponse = addAttachmentResponse
      self.addAttachmentError = addAttachmentError
      self.removeAttachmentResponse = removeAttachmentResponse
      self.removeAttachmentError = removeAttachmentError

      self.publishUpdateError = publishUpdateError

      self.fetchManagePledgeViewBackingResult = fetchManagePledgeViewBackingResult
      self.fetchProjectAndBackingResult = fetchProjectAndBackingResult

      self.fetchRewardAddOnsSelectionViewRewardsResult = fetchRewardAddOnsSelectionViewRewardsResult

      self.fetchMessageThreadResult = fetchMessageThreadResult

      self.fetchMessageThreadsResponse = fetchMessageThreadsResponse ?? [
        .template |> MessageThread.lens.id .~ 1,
        .template |> MessageThread.lens.id .~ 2,
        .template |> MessageThread.lens.id .~ 3
      ]

      self.fetchProjectActivitiesResponse = fetchProjectActivitiesResponse ?? [
        .template,
        .template |> Activity.lens.category .~ .backing,
        .template |> Activity.lens.category .~ .commentProject
      ]
      .enumerated()
      .map(Activity.lens.id.set)

      self.fetchProjectActivitiesError = fetchProjectActivitiesError

      self.fetchProjectNotificationsResponse = fetchProjectNotificationsResponse ?? [
        .template |> ProjectNotification.lens.id .~ 1,
        .template |> ProjectNotification.lens.id .~ 2,
        .template |> ProjectNotification.lens.id .~ 3
      ]

      self.fetchProjectsResponse = fetchProjectsResponse ?? []

      self.fetchProjectsError = fetchProjectsError

      self.fetchProjectEnvelopeResult = fetchProjectResult
      self.fastFetchProjectPageResult = fastFetchProjectPage
      self.fetchProjectPamphletEnvelopeResult = fetchProjectPamphletResult
      self.fetchProjectFriendsEnvelopeResult = fetchProjectFriendsResult
      self.fetchProjectRewardsAndPledgeOverTimeDataResult = fetchProjectRewardsAndPledgeOverTimeDataResult
      self.fetchProjectRewardsEnvelopeResult = fetchProjectRewardsResult

      self.fetchProjectStatsResponse = fetchProjectStatsResponse
      self.fetchProjectStatsError = fetchProjectStatsError

      self.fetchShippingRulesResult = fetchShippingRulesResult

      self.fetchSurveyResponseResponse = fetchSurveyResponseResponse
      self.fetchSurveyResponseError = fetchSurveyResponseError

      self.fetchUnansweredSurveyResponsesResponse = fetchUnansweredSurveyResponsesResponse

      self.fetchUpdateResponse = fetchUpdateResponse

      self.fetchUserResult = fetchUserResult

      self.fetchUserSelfResponse = fetchUserSelfResponse ?? .template
      self.fetchUserSelfError = fetchUserSelfError

      self.followFriendError = followFriendError

      self.incrementVideoCompletionError = incrementVideoCompletionError

      self.incrementVideoStartError = incrementVideoStartError

      self.postCommentResult = postCommentResult

      self.loginResponse = loginResponse

      self.loginError = loginError

      self.resendCodeResponse = resendCodeResponse

      self.resendCodeError = resendCodeError

      self.resetPasswordResponse = resetPasswordResponse

      self.resetPasswordError = resetPasswordError

      self.sendEmailVerificationResult = sendEmailVerificationResult

      self.signInWithAppleResult = signInWithAppleResult

      self.signupResponse = signupResponse

      self.signupError = signupError

      self.unfollowFriendError = unfollowFriendError

      self.updateRewardReceivedResult = updateRewardReceivedResult

      self.updateBackingResult = updateBackingResult

      self.updateDraftError = updateDraftError

      self.updatePledgeResult = updatePledgeResult

      self.updateProjectNotificationResponse = updateProjectNotificationResponse

      self.updateProjectNotificationError = updateProjectNotificationError

      self.updateUserSelfError = updateUserSelfError

      self.unwatchProjectMutationResult = unwatchProjectMutationResult

      self.validateCheckoutResult = validateCheckoutResult

      self.verifyEmailResult = verifyEmailResult

      self.watchProjectMutationResult = watchProjectMutationResult

      self.tokenExchangeResponse = tokenExchangeResponse
    }

    public func addNewCreditCard(input: CreatePaymentSourceInput)
      -> SignalProducer<CreatePaymentSourceEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .CreatePaymentSourceMutation(input: GraphAPI.CreatePaymentSourceInput.from(input))

      return client.performWithResult(mutation: mutation, result: self.addNewCreditCardResult)
    }

    public func addPaymentSheetPaymentSource(input: CreatePaymentSourceSetupIntentInput)
      -> SignalProducer<CreatePaymentSourceEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .CreatePaymentSourceMutation(input: GraphAPI.CreatePaymentSourceInput.from(input))

      return client.performWithResult(mutation: mutation, result: self.addPaymentSheetPaymentSourceResult)
    }

    public func addUserToSecretRewardGroup(token: String, forProject param: Param)
      -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let input = GraphAPI.AddUserToSecretRewardGroupInput.from(token: token, forProject: param)

      let mutation = GraphAPI.AddUserToSecretRewardGroupMutation(input: input)
      return client.performWithResult(mutation: mutation, result: self.addUserToSecretRewardGroup)
    }

    public func blockUser(input: BlockUserInput)
      -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .BlockUserMutation(input: GraphAPI.BlockUserInput(blockUserId: input.blockUserId))

      return client.performWithResult(mutation: mutation, result: self.blockUserResult)
    }

    func buildPaymentPlan(
      projectSlug: String,
      pledgeAmount: String
    ) -> SignalProducer<GraphAPI.BuildPaymentPlanQuery.Data, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let query = GraphAPI.BuildPaymentPlanQuery(
        slug: projectSlug,
        amount: pledgeAmount
      )

      return client.fetchWithResult(query: query, result: self.buildPaymentPlanResult)
    }

    public func cancelBacking(input: CancelBackingInput)
      -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .CancelBackingMutation(input: GraphAPI.CancelBackingInput(id: input.backingId))

      return client.performWithResult(mutation: mutation, result: self.cancelBackingResult)
    }

    internal func changeEmail(input: ChangeEmailInput)
      -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .UpdateUserAccountMutation(input: GraphAPI.UpdateUserAccountInput.from(input))

      return client.performWithResult(mutation: mutation, result: self.changeEmailResult)
    }

    internal func facebookConnect(facebookAccessToken _: String)
      -> SignalProducer<User, ErrorEnvelope> {
      if let response = facebookConnectResponse {
        return SignalProducer(value: response)
      } else if let error = facebookConnectError {
        return SignalProducer(error: error)
      }

      return SignalProducer(
        value:
        User.template
          |> \.id .~ 1
          |> \.facebookConnected .~ true
      )
    }

    internal func changePassword(input: ChangePasswordInput)
      -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .UpdateUserAccountMutation(input: GraphAPI.UpdateUserAccountInput.from(input))

      return client.performWithResult(mutation: mutation, result: self.changePasswordResult)
    }

    public func createAttributionEvent(input: GraphAPI.CreateAttributionEventInput) ->
      SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI.CreateAttributionEventMutation(input: input)

      return client.performWithResult(mutation: mutation, result: self.createAttributionEventResult)
    }

    internal func createBacking(input: CreateBackingInput)
      -> SignalProducer<CreateBackingEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI.CreateBackingMutation(input: GraphAPI.CreateBackingInput.from(input))

      return client.performWithResult(mutation: mutation, result: self.createBackingResult)
    }

    internal func completeOnSessionCheckout(input: GraphAPI.CompleteOnSessionCheckoutInput) ->
      SignalProducer<GraphAPI.CompleteOnSessionCheckoutMutation.Data, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI.CompleteOnSessionCheckoutMutation(input: input)
      return client.performWithResult(mutation: mutation, result: self.completeOnSessionCheckoutResult)
    }

    internal func createCheckout(input: CreateCheckoutInput)
      -> SignalProducer<CreateCheckoutEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI.CreateCheckoutMutation(
        input: GraphAPI
          .CreateCheckoutInput(
            projectId: input.projectId,
            amount: GraphQLNullable.someOrNil(input.amount),
            locationId: GraphQLNullable.someOrNil(input.locationId),
            rewardIds: GraphQLNullable.someOrNil(input.rewardIds),
            refParam: GraphQLNullable.someOrNil(input.refParam)
          )
      )

      return client.performWithResult(mutation: mutation, result: self.createCheckoutResult)
    }

    internal func createFlaggingInput(input: CreateFlaggingInput) -> ReactiveSwift
      .SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .CreateFlaggingMutation(input: GraphAPI.CreateFlaggingInput.from(input))

      return client.performWithResult(mutation: mutation, result: self.createFlaggingResult)
    }

    internal func createFlaggingInputCombine(input: CreateFlaggingInput)
      -> AnyPublisher<EmptyResponseEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return Empty(completeImmediately: false).eraseToAnyPublisher()
      }

      let mutation = GraphAPI
        .CreateFlaggingMutation(input: GraphAPI.CreateFlaggingInput.from(input))

      return client.performWithResult(mutation: mutation, result: self.createFlaggingResult)
    }

    internal func createPaymentIntentInput(input: CreatePaymentIntentInput) -> ReactiveSwift
      .SignalProducer<PaymentIntentEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .CreatePaymentIntentMutation(input: GraphAPI.CreatePaymentIntentInput(
          projectId: input.projectId,
          amount: input.amountDollars,
          digitalMarketingAttributed: GraphQLNullable.someOrNil(input.digitalMarketingAttributed)
        ))

      return client.performWithResult(mutation: mutation, result: self.createPaymentIntentResult)
    }

    internal func createPassword(input: CreatePasswordInput)
      -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .UpdateUserAccountMutation(input: GraphAPI.UpdateUserAccountInput.from(input))

      return client.performWithResult(mutation: mutation, result: self.createPasswordResult)
    }

    internal func createStripeSetupIntent(input: CreateSetupIntentInput)
      -> SignalProducer<ClientSecretEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .CreateSetupIntentMutation(input: GraphAPI.CreateSetupIntentInput.from(input))

      return client.performWithResult(mutation: mutation, result: self.createStripeSetupIntentResult)
    }

    internal func changeCurrency(input: ChangeCurrencyInput)
      -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .UpdateUserProfileMutation(input: GraphAPI.UpdateUserProfileInput.from(input))

      return client.performWithResult(mutation: mutation, result: self.changeCurrencyResult)
    }

    internal func clearUserUnseenActivity(input _: EmptyInput)
      -> SignalProducer<ClearUserUnseenActivityEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .ClearUserUnseenActivityMutation(input: GraphAPI.ClearUserUnseenActivityInput())

      return client.performWithResult(mutation: mutation, result: self.clearUserUnseenActivityResult)
    }

    @MainActor public func discussionComments(slug: String?, updateID: String?, cursor: String?) async throws -> CommentsEnvelope {
      try Task.checkCancellation()
      let result = slug != nil ? self.fetchProjectCommentsEnvelopeResult : self.fetchUpdateCommentsEnvelopeResult
      guard let result else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func submitDiscussionComment(input: PostCommentInput) async throws -> Comment {
      try Task.checkCancellation()
      guard let result = self.postCommentResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func blockDiscussionUser(id: String) async throws -> EmptyResponseEnvelope {
      try Task.checkCancellation()
      guard let result = self.blockUserResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func discussionReplies(id: String, cursor: String?) async throws -> CommentRepliesEnvelope {
      try Task.checkCancellation()
      guard let result = self.fetchCommentRepliesEnvelopeResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func discussionProject(param: Param) async throws -> Project {
      try Task.checkCancellation()
      if let demoCatalog { return try demoCatalog.project(param) }
      guard let result = self.fetchProjectEnvelopeResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func projectUpdate(id: Int, project: Param) async throws -> Update {
      try Task.checkCancellation()
      return self.fetchUpdateResponse |> Update.lens.id .~ id
    }

    @MainActor public func reportVideoEvent(project: any HasProjectWebURL, completed: Bool) async throws -> VoidEnvelope {
      try Task.checkCancellation()
      if let error = completed ? self.incrementVideoCompletionError : self.incrementVideoStartError { throw error }
      return VoidEnvelope()
    }

    @MainActor public func projectVideoFeed() async throws -> GraphAPI.VideoFeedQuery.Data {
      try Task.checkCancellation()
      guard let data = try await self.fetch(query: GraphAPI.VideoFeedQuery(
        first: 30, after: .none, categoryId: .none
      )) else { throw ErrorEnvelope.couldNotParseJSON }
      return data
    }

    @MainActor public func activityPage(cursor _: String?) async throws -> ActivityEnvelope {
      guard let envelope = try await self.discoveryActivitySample()
      else { throw ErrorEnvelope.couldNotParseJSON }
      return envelope
    }

    @MainActor public func unansweredSurveys() async throws -> [SurveyResponse] {
      try Task.checkCancellation()
      return self.fetchUnansweredSurveyResponsesResponse
    }

    @MainActor public func sessionUser() async throws -> User {
      try Task.checkCancellation()
      if let error = self.fetchUserSelfError { throw error }
      return self.fetchUserSelfResponse ?? .template
    }

    @MainActor public func pledgedProjects(tiers: [GraphAPI.PledgeProjectsOverviewSort], cursor: String?, limit: Int) async throws -> GraphAPI.FetchPledgedProjectsQuery.Data {
      try Task.checkCancellation()
      guard let result = self.fetchPledgedProjectsResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }
    @MainActor public func confirmPledgeAddress(backingID: String, addressID: String) async throws -> Bool {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      guard let result = self.confirmBackingAddressResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }
    @MainActor public func setPledgeReceipt(backingID: String, received: Bool) async throws -> Bool {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      guard let result = self.updateRewardReceivedResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }
    @MainActor public func pledgePaymentPlan(slug: String, amount: String) async throws -> GraphAPI.BuildPaymentPlanQuery.Data {
      try Task.checkCancellation()
      guard let result = self.buildPaymentPlanResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func openPledgeCheckout(_ input: CreateCheckoutInput) async throws -> CreateCheckoutEnvelope {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      guard let result = self.createCheckoutResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }
    @MainActor public func checkPledgeCheckout(checkoutID: String, sourceID: String, secret: String) async throws -> ValidateCheckoutEnvelope {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      guard let result = self.validateCheckoutResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }
    @MainActor public func finishPledgeCheckout(_ input: GraphAPI.CompleteOnSessionCheckoutInput) async throws -> GraphAPI.CompleteOnSessionCheckoutMutation.Data {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      guard let result = self.completeOnSessionCheckoutResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }
    @MainActor public func managedPledgeBacking(id: Int) async throws -> Backing {
      try Task.checkCancellation()
      guard let result = self.fetchManagePledgeViewBackingResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }
    @MainActor public func managedPledgeRewards(projectID: Int) async throws -> RewardsAndPledgeOverTimeEnvelope {
      try Task.checkCancellation()
      if let demoCatalog {
        return RewardsAndPledgeOverTimeEnvelope(rewards: try demoCatalog.project(.id(projectID)).rewards,
          isPledgeOverTimeAllowed: false, pledgeOverTimeCollectionPlanChargeExplanation: nil,
          pledgeOverTimeCollectionPlanChargedAsNPayments: nil, pledgeOverTimeCollectionPlanShortPitch: nil,
          pledgeOverTimeMinimumExplanation: nil)
      }
      guard let result = self.fetchProjectRewardsAndPledgeOverTimeDataResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func submitPledge(_ input: CreateBackingInput) async throws -> CreateBackingEnvelope {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      guard let result = self.createBackingResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func revisePledge(_ input: UpdateBackingInput) async throws -> UpdateBackingEnvelope {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      guard let result = self.updateBackingResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func cancelPledge(_ input: CancelBackingInput) async throws {
      try self.completeAccountWrite(self.cancelBackingResult)
    }

    @MainActor public func markPledgeReceived(projectID: Int, userID: Int, received: Bool) async throws -> Backing {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      return self.fetchBackingResponse
        |> Backing.lens.backerId .~ userID
        |> Backing.lens.projectId .~ projectID
        |> Backing.lens.backerCompleted .~ received
    }

    @MainActor public func paymentCards() async throws -> UserEnvelope<GraphUser> {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      guard let result = self.fetchGraphUserResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func removePaymentMethod(id: String) async throws -> DeletePaymentMethodEnvelope {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      guard let result = self.deletePaymentMethodResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func storePaymentMethod(secret: String) async throws -> CreatePaymentSourceEnvelope {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      guard let result = self.addPaymentSheetPaymentSourceResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func paymentSetupIntent(input: CreateSetupIntentInput) async throws -> ClientSecretEnvelope {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      guard let result = self.createStripeSetupIntentResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func paymentIntent(input: CreatePaymentIntentInput) async throws -> PaymentIntentEnvelope {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      guard let result = self.createPaymentIntentResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor private func completeAccountWrite(
      _ result: Result<EmptyResponseEnvelope, ErrorEnvelope>?
    ) throws {
      try Task.checkCancellation()
      guard self.demoCatalog == nil else {
        throw ErrorEnvelope.graphError("Accounts and payments are unavailable in this fictional demo.")
      }
      guard let result else { throw ErrorEnvelope.couldNotParseJSON }
      _ = try result.get()
    }

    @MainActor public func accountEmailUser() async throws -> GraphUser {
      try Task.checkCancellation()
      guard let result = self.fetchGraphUserResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get().me
    }

    @MainActor public func sessionSetup() async throws -> GraphUserSetup {
      try Task.checkCancellation()
      guard let result = self.fetchGraphUserSetupResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get().me
    }

    @MainActor public func confirmEmail(token: String) async throws -> EmailVerificationResponseEnvelope {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      guard let result = self.verifyEmailResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func saveEmail(_ input: ChangeEmailInput) async throws {
      try self.completeAccountWrite(self.changeEmailResult)
    }

    @MainActor public func savePassword(_ input: ChangePasswordInput) async throws {
      try self.completeAccountWrite(self.changePasswordResult)
    }

    @MainActor public func setInitialPassword(_ input: CreatePasswordInput) async throws {
      try self.completeAccountWrite(self.createPasswordResult)
    }

    @MainActor public func saveCurrency(_ input: ChangeCurrencyInput) async throws {
      try self.completeAccountWrite(self.changeCurrencyResult)
    }

    @MainActor public func requestEmailVerification() async throws {
      try self.completeAccountWrite(self.sendEmailVerificationResult)
    }

    @MainActor public func connectFacebook(token: String) async throws -> User {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      if let error = self.facebookConnectError { throw error }
      if let user = self.facebookConnectResponse { return user }
      var user = User.template
      user.id = 1
      user.facebookConnected = true
      return user
    }

    @MainActor public func projectNotificationSettings() async throws -> [ProjectNotification] {
      try Task.checkCancellation()
      guard self.demoCatalog == nil else {
        throw ErrorEnvelope.graphError("Accounts and payments are unavailable in this fictional demo.")
      }
      return self.fetchProjectNotificationsResponse
    }

    @MainActor public func saveProjectNotification(_ notification: ProjectNotification) async throws
      -> ProjectNotification {
      try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      if let error = self.updateProjectNotificationError { throw error }
      return self.updateProjectNotificationResponse ?? notification
    }

    @MainActor public func saveAccountPreferences(_ user: User) async throws -> User {
      try Task.checkCancellation()
      if self.demoCatalog != nil {
        throw ErrorEnvelope.graphError("Accounts and payments are unavailable in this fictional demo.")
      }
      if let error = self.updateUserSelfError { throw error }
      return user
    }

    @MainActor public func sessionGraphUser() async throws -> User {
      try Task.checkCancellation()
      guard let result = self.fetchGraphUserSelfResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get().me
    }

    @MainActor public func clearActivityIndicator() async throws -> Int {
      try Task.checkCancellation()
      guard let result = self.clearUserUnseenActivityResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get().activityIndicatorCount
    }

    @MainActor public func profileBackedProjects(cursor _: String?) async throws -> GraphAPI
      .FetchMyBackedProjectsQuery.Data {
      try Task.checkCancellation()
      guard let data = self.fetchBackerBackedProjectsResponse else { throw ErrorEnvelope.couldNotParseJSON }
      return data
    }

    @MainActor public func profileSavedProjects(cursor _: String?) async throws -> GraphAPI
      .FetchMySavedProjectsQuery.Data {
      try Task.checkCancellation()
      guard let data = self.fetchBackerSavedProjectsResponse else { throw ErrorEnvelope.couldNotParseJSON }
      return data
    }

    @MainActor public func setProjectWatched(
      id: String, watched: Bool
    ) async throws -> WatchProjectResponseEnvelope {
      try Task.checkCancellation()
      guard let result = watched ? self.watchProjectMutationResult : self.unwatchProjectMutationResult
      else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    func fetchProjectComments(
      slug: String,
      cursor: String?,
      limit: Int?
    ) -> SignalProducer<CommentsEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let fetchProjectCommentsQuery = GraphAPI.FetchProjectCommentsQuery(
        slug: slug,
        cursor: GraphQLNullable.someOrNil(cursor),
        limit: GraphQLNullable.someOrNil(limit)
      )

      return client
        .fetchWithResult(query: fetchProjectCommentsQuery, result: self.fetchProjectCommentsEnvelopeResult)
    }

    func fetchUpdateComments(
      id: String,
      cursor: String?,
      limit: Int?
    ) -> SignalProducer<CommentsEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let fetchUpdateCommentsQuery = GraphAPI.FetchUpdateCommentsQuery(
        postId: id,
        cursor: GraphQLNullable.someOrNil(cursor),
        limit: GraphQLNullable.someOrNil(limit)
      )

      return client
        .fetchWithResult(query: fetchUpdateCommentsQuery, result: self.fetchUpdateCommentsEnvelopeResult)
    }

    func fetchCommentReplies(
      id: String,
      cursor: String?,
      limit: Int
    ) -> SignalProducer<CommentRepliesEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let fetchCommentRepliesQuery = GraphAPI.FetchCommentRepliesQuery(
        commentId: id,
        cursor: GraphQLNullable.someOrNil(cursor),
        limit: limit
      )

      return client
        .fetchWithResult(query: fetchCommentRepliesQuery, result: self.fetchCommentRepliesEnvelopeResult)
    }

    internal func fetchConfig() -> SignalProducer<Config, ErrorEnvelope> {
      guard let config = self.fetchConfigResponse else { return .empty }
      return SignalProducer(value: config)
    }

    internal func fetchFriends() -> SignalProducer<FindFriendsEnvelope, ErrorEnvelope> {
      if let response = fetchFriendsResponse {
        return SignalProducer(value: response)
      } else if let error = fetchFriendsError {
        return SignalProducer(error: error)
      }

      return SignalProducer(value: .template)
    }

    internal func fetchFriends(paginationUrl _: String)
      -> SignalProducer<FindFriendsEnvelope, ErrorEnvelope> {
      return self.fetchFriends()
    }

    internal func fetchFriendStats() -> SignalProducer<FriendStatsEnvelope, ErrorEnvelope> {
      if let response = fetchFriendStatsResponse {
        return SignalProducer(value: response)
      } else if let error = fetchFriendStatsError {
        return SignalProducer(error: error)
      }
      return SignalProducer(value: .template)
    }

    internal func followAllFriends() -> SignalProducer<VoidEnvelope, ErrorEnvelope> {
      return SignalProducer(value: VoidEnvelope())
    }

    internal func followFriend(userId id: Int) -> SignalProducer<User, ErrorEnvelope> {
      if let error = followFriendError {
        return SignalProducer(error: error)
      }

      return SignalProducer(
        value:
        User.template
          |> \.id .~ id
          |> \.isFriend .~ true
      )
    }

    internal func fetch<Q: GraphQLQuery>(query: Q) -> SignalProducer<Q.Data, ErrorEnvelope> {
      if let demoCatalog { return demoResponse { try demoCatalog.graphResponse(for: query) } }
      if self.pendingLegacyGraphQLQueries.contains(where: { $0 == Q.self }) { return .never }
      for (queryType, result) in self.fetchGraphQLResponses ?? [] {
        if queryType == Q.self, let response = result as? Q.Data {
          return SignalProducer(value: response)
        }
      }
      return SignalProducer(error: ErrorEnvelope.graphError("Unimplemented mock"))
    }

    internal func fetch<Q: GraphQLQuery>(query: Q) async throws -> Q.Data? {
      if let demoCatalog { return try demoCatalog.graphResponse(for: query) }
      for (queryType, result) in self.fetchGraphQLResponses ?? [] {
        if queryType == Q.self, let response = result as? Q.Data {
          return response
        }
      }
      throw ErrorEnvelope.graphError("Unimplemented mock")
    }

    @MainActor internal func fetchSearchCategories() async throws -> RootCategoriesEnvelope {
      try Task.checkCancellation()
      if let demoCatalog { return demoCatalog.categories }
      guard let result = self.fetchGraphCategoriesResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    internal func fetchGraphCategories()
      -> SignalProducer<RootCategoriesEnvelope, ErrorEnvelope> {
      if let demoCatalog { return SignalProducer(value: demoCatalog.categories) }
      guard let client = self.apolloClient else {
        return .empty
      }

      let fetchGraphCategoriesQuery = GraphAPI.FetchRootCategoriesQuery()

      return client.fetchWithResult(query: fetchGraphCategoriesQuery, result: self.fetchGraphCategoriesResult)
    }

    func fetchProjectFlaggingOptions() async throws -> [ReportProjectInfoListItem] {
      switch self.fetchFlaggingOptionsResult {
      case let .success(data):
        return ReportProjectInfoListItem.items(from: data)
      case let .failure(error):
        throw error
      case .none:
        return []
      }
    }

    internal func fetchGraphCategory(id: String)
      -> SignalProducer<CategoryEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let fetchGraphCategoryQuery = GraphAPI.FetchCategoryQuery(id: id)

      return client.fetchWithResult(query: fetchGraphCategoryQuery, result: self.fetchGraphCategoryResult)
    }

    internal func fetchGraphUserSelf()
      -> SignalProducer<UserEnvelope<User>, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let fetchGraphUserQuery = GraphAPI.FetchUserQuery(withStoredCards: false)

      return client.fetchWithResult(query: fetchGraphUserQuery, result: self.fetchGraphUserSelfResult)
    }

    internal func fetchGraphUser(withStoredCards: Bool)
      -> SignalProducer<UserEnvelope<GraphUser>, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let fetchGraphUserQuery = GraphAPI.FetchUserQuery(withStoredCards: withStoredCards)

      return client.fetchWithResult(query: fetchGraphUserQuery, result: self.fetchGraphUserResult)
    }

    internal func fetchGraphUserEmail() -> SignalProducer<UserEnvelope<GraphUserEmail>, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let fetchGraphUserEmailQuery = GraphAPI.FetchUserEmailQuery()

      return client.fetchWithResult(query: fetchGraphUserEmailQuery, result: self.fetchGraphUserEmailResult)
    }

    func fetchGraphUserEmailCombine() -> AnyPublisher<UserEnvelope<GraphUserEmail>, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return Empty(completeImmediately: false).eraseToAnyPublisher()
      }

      let fetchGraphUserEmailQuery = GraphAPI.FetchUserEmailQuery()
      return client.fetchWithResult(query: fetchGraphUserEmailQuery, result: self.fetchGraphUserEmailResult)
    }

    internal func fetchGraphUserSetup() -> SignalProducer<UserEnvelope<GraphUserSetup>, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let fetchGraphUserSetupQuery = GraphAPI.FetchUserSetupQuery()

      return client.fetchWithResult(query: fetchGraphUserSetupQuery, result: self.fetchGraphUserSetupResult)
    }

    func fetchGraphUserSetupCombine() -> AnyPublisher<UserEnvelope<GraphUserSetup>, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return Empty(completeImmediately: false).eraseToAnyPublisher()
      }

      let fetchGraphUserSetupQuery = GraphAPI.FetchUserSetupQuery()
      return client.fetchWithResult(query: fetchGraphUserSetupQuery, result: self.fetchGraphUserSetupResult)
    }

    internal func unfollowFriend(userId _: Int) -> SignalProducer<VoidEnvelope, ErrorEnvelope> {
      if let error = unfollowFriendError {
        return SignalProducer(error: error)
      }

      return SignalProducer(value: VoidEnvelope())
    }

    internal func login(_ oauthToken: OauthTokenAuthType) -> MockService {
      return self |> MockService.lens.oauthToken .~ oauthToken
    }

    internal func logout() -> MockService {
      return self |> MockService.lens.oauthToken .~ nil
    }

    internal func fetchActivities(count _: Int?) -> SignalProducer<ActivityEnvelope, ErrorEnvelope> {
      if let error = fetchActivitiesError {
        return SignalProducer(error: error)
      } else if let activities = fetchActivitiesResponse {
        return SignalProducer(
          value: ActivityEnvelope(
            activities: activities,
            urls: ActivityEnvelope.UrlsEnvelope(
              api: ActivityEnvelope.UrlsEnvelope.ApiEnvelope(
                moreActivities: "http://\(Secrets.Api.Endpoint.production)/gimme/more"
              )
            )
          )
        )
      }
      return .empty
    }

    internal func fetchActivities(paginationUrl _: String)
      -> SignalProducer<ActivityEnvelope, ErrorEnvelope> {
      return self.fetchActivities(count: nil)
    }

    func fetchBacking(forProject project: Project, forUser user: User)
      -> SignalProducer<Backing, ErrorEnvelope> {
      return SignalProducer(
        value: self.fetchBackingResponse
          |> Backing.lens.backer .~ user
          |> Backing.lens.backerId .~ user.id
          |> Backing.lens.projectId .~ project.id
      )
    }

    func backingUpdate(forProject project: Project, forUser user: User, received: Bool)
      -> SignalProducer<Backing, ErrorEnvelope> {
      return SignalProducer(
        value: self.fetchBackingResponse
          |> Backing.lens.backer .~ user
          |> Backing.lens.backerId .~ user.id
          |> Backing.lens.projectId .~ project.id
          |> Backing.lens.backerCompleted .~ received
      )
    }

    func updateRewardReceived(
      backingId _: String,
      rewardReceived _: Bool
    ) -> AnyPublisher<Bool, ErrorEnvelope> {
      guard let updateRewardReceivedResponse = self.updateRewardReceivedResult else {
        return Fail(outputType: Bool.self, failure: ErrorEnvelope.couldNotParseErrorEnvelopeJSON)
          .eraseToAnyPublisher()
      }

      switch updateRewardReceivedResponse {
      case let .success(rewardReceivedValue):
        return Just(rewardReceivedValue).setFailureType(to: ErrorEnvelope.self).eraseToAnyPublisher()

      case let .failure(envelope):
        return Fail(outputType: Bool.self, failure: envelope).eraseToAnyPublisher()
      }
    }

    internal func discoveryPage(params: DiscoveryParams) async throws -> DiscoveryEnvelope {
      try Task.checkCancellation()
      if let demoCatalog { return try demoCatalog.discovery(params) }
      if let error = self.fetchDiscoveryError { throw error }
      return self.fetchDiscoveryResponse ?? (
        .template |> DiscoveryEnvelope.lens.projects .~ (1...4).map { index in
          .template |> Project.lens.id .~ (index + params.hashValue)
        }
      )
    }

    internal func discoveryPage(paginationURL: String) async throws -> DiscoveryEnvelope {
      try Task.checkCancellation()
      if let demoCatalog { return try demoCatalog.discovery(paginationURL: paginationURL) }
      if let error = self.fetchDiscoveryError { throw error }
      return self.fetchDiscoveryResponse ?? (
        .template
          |> DiscoveryEnvelope.lens.projects .~ (1...4).map { index in
            .template |> Project.lens.id .~ (index + paginationURL.hashValue)
          }
          |> DiscoveryEnvelope.lens.urls.api.moreProjects .~ (paginationURL + "+1")
      )
    }

    internal func discoveryActivitySample() async throws -> ActivityEnvelope? {
      try Task.checkCancellation()
      if let error = self.fetchActivitiesError { throw error }
      guard let activities = self.fetchActivitiesResponse else { return nil }
      return ActivityEnvelope(activities: activities, urls: .init(api: .init(
        moreActivities: "http://\(Secrets.Api.Endpoint.production)/gimme/more"
      )))
    }

    internal func fetchDiscovery(paginationUrl: String)
      -> SignalProducer<DiscoveryEnvelope, ErrorEnvelope> {
      if let demoCatalog { return demoResponse { try demoCatalog.discovery(paginationURL: paginationUrl) } }
      if let error = fetchDiscoveryError {
        return SignalProducer(error: error)
      }

      let project: (Int) -> Project = {
        .template |> Project.lens.id .~ ($0 + paginationUrl.hashValue)
      }
      let envelope = self.fetchDiscoveryResponse ?? (
        .template
          |> DiscoveryEnvelope.lens.projects .~ (1...4).map(project)
          |> DiscoveryEnvelope.lens.urls.api.moreProjects .~ (paginationUrl + "+1")
      )

      return SignalProducer(value: envelope)
    }

    internal func fetchDiscovery(params: DiscoveryParams)
      -> SignalProducer<DiscoveryEnvelope, ErrorEnvelope> {
      if let demoCatalog { return demoResponse { try demoCatalog.discovery(params) } }
      if let error = fetchDiscoveryError {
        return SignalProducer(error: error)
      }

      let project: (Int) -> Project = {
        .template |> Project.lens.id %~ const($0 + params.hashValue)
      }
      let envelope = self.fetchDiscoveryResponse ?? (
        .template
          |> DiscoveryEnvelope.lens.projects .~ (1...4).map(project)
      )

      return SignalProducer(value: envelope)
    }

    func fetchBacking(id _: Int)
      -> SignalProducer<ProjectAndBackingEnvelope, ErrorEnvelope> {
      return producer(for: self.fetchProjectAndBackingResult)
    }

    func fetchBackingForManagePledge(id _: Int)
      -> SignalProducer<Backing, ErrorEnvelope> {
      return producer(for: self.fetchManagePledgeViewBackingResult)
    }

    func fetchRewardAddOnsSelectionViewRewards(slug: String, shippingEnabled: Bool, locationId: String?)
      -> SignalProducer<Project, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let fetchRewardAddOnsSelectionViewRewardsQuery = GraphAPI.FetchAddOnsQuery(
        projectSlug: slug,
        shippingEnabled: shippingEnabled,
        locationId: GraphQLNullable.someOrNil(locationId)
      )

      return client
        .fetchWithResult(
          query: fetchRewardAddOnsSelectionViewRewardsQuery,
          result: self.fetchRewardAddOnsSelectionViewRewardsResult
        )
    }

    func fastFetchRewardAddOnsSelection(
      baseRewardId _: Int,
      countryCode _: String
    ) -> SignalProducer<[Reward], ErrorEnvelope> {
      return SignalProducer(error: ErrorEnvelope.graphError("Unimplemented mock"))
    }

    @MainActor public func messageThreadsPage(
      mailbox _: Mailbox, project _: Project?, cursor _: String?
    ) async throws -> MessageThreadsEnvelope {
      _ = try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      return MessageThreadsEnvelope(
        messageThreads: self.fetchMessageThreadsResponse,
        urls: .init(api: .init(moreMessageThreads: ""))
      )
    }

    @MainActor public func messageSearch(query _: String, project: Project?) async throws -> MessageThreadsEnvelope {
      try await self.messageThreadsPage(mailbox: .inbox, project: project, cursor: nil)
    }

    @MainActor public func messageThread(id _: Int) async throws -> MessageThreadEnvelope {
      _ = try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      if let error = self.fetchMessageThreadResult?.error { throw error }
      return MessageThreadEnvelope(
        participants: [.template, .template |> \.id .~ 2],
        messages: [.template |> Message.lens.id .~ 1, .template |> Message.lens.id .~ 2,
                   .template |> Message.lens.id .~ 3],
        messageThread: self.fetchMessageThreadResult?.value as? MessageThread ?? .template
      )
    }

    @MainActor public func messageThread(backing _: Backing) async throws -> MessageThreadEnvelope? {
      _ = try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      if let error = self.fetchMessageThreadResult?.error { throw error }
      guard self.fetchMessageThreadResult?.value as? MessageThread != nil else { return nil }
      return try await self.messageThread(id: 0)
    }

    @MainActor public func messageBacking(project: Project, user: User) async throws -> Backing {
      _ = try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      return self.fetchBackingResponse
        |> Backing.lens.backer .~ user
        |> Backing.lens.backerId .~ user.id
        |> Backing.lens.projectId .~ project.id
    }

    @MainActor public func readMessageThread(_ thread: MessageThread) async throws -> MessageThread {
      _ = try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      return thread
    }

    @MainActor public func submitMessage(body: String, subject _: MessageSubject) async throws -> Message {
      _ = try self.completeAccountWrite(.success(EmptyResponseEnvelope()))
      return .template |> Message.lens.id .~ body.hashValue |> Message.lens.body .~ body
    }

    internal func fetchMessageThread(messageThreadId _: Int)
      -> SignalProducer<MessageThreadEnvelope, ErrorEnvelope> {
      if let error = self.fetchMessageThreadResult?.error {
        return SignalProducer(error: error)
      }

      return SignalProducer(
        value: MessageThreadEnvelope(
          participants: [.template, .template |> \.id .~ 2],
          messages: [
            .template |> Message.lens.id .~ 1,
            .template |> Message.lens.id .~ 2,
            .template |> Message.lens.id .~ 3
          ],
          messageThread: self.fetchMessageThreadResult?.value as? MessageThread ?? .template
        )
      )
    }

    internal func fetchMessageThread(backing _: Backing)
      -> SignalProducer<MessageThreadEnvelope?, ErrorEnvelope> {
      if let error = self.fetchMessageThreadResult?.error {
        return SignalProducer(error: error)
      }

      if let thread = self.fetchMessageThreadResult?.value as? MessageThread {
        return SignalProducer(
          value: MessageThreadEnvelope(
            participants: [.template, .template |> \.id .~ 2],
            messages: [
              .template |> Message.lens.id .~ 1,
              .template |> Message.lens.id .~ 2,
              .template |> Message.lens.id .~ 3
            ],
            messageThread: thread
          )
        )
      } else {
        return SignalProducer(value: nil)
      }
    }

    internal func fetchMessageThreads(mailbox _: Mailbox, project _: Project?)
      -> SignalProducer<MessageThreadsEnvelope, ErrorEnvelope> {
      return SignalProducer(
        value:
        MessageThreadsEnvelope(
          messageThreads: self.fetchMessageThreadsResponse,
          urls: MessageThreadsEnvelope.UrlsEnvelope(
            api: MessageThreadsEnvelope.UrlsEnvelope.ApiEnvelope(
              moreMessageThreads: ""
            )
          )
        )
      )
    }

    internal func fetchMessageThreads(paginationUrl _: String)
      -> SignalProducer<MessageThreadsEnvelope, ErrorEnvelope> {
      return SignalProducer(
        value:
        MessageThreadsEnvelope(
          messageThreads: self.fetchMessageThreadsResponse,
          urls: MessageThreadsEnvelope.UrlsEnvelope(
            api: MessageThreadsEnvelope.UrlsEnvelope.ApiEnvelope(
              moreMessageThreads: ""
            )
          )
        )
      )
    }

    internal func fetchProjectNotifications() -> SignalProducer<[ProjectNotification], ErrorEnvelope> {
      return SignalProducer(value: self.fetchProjectNotificationsResponse)
    }

    public func fetchSavedProjects(
      cursor _: String? = nil,
      limit _: Int? = nil
    ) -> SignalProducer<GraphAPI.FetchMySavedProjectsQuery.Data, ErrorEnvelope> {
      guard let result = self.fetchBackerSavedProjectsResponse else {
        return .empty
      }
      return SignalProducer(value: result)
    }

    public func fetchBackedProjects(
      cursor _: String? = nil,
      limit _: Int? = nil
    ) -> SignalProducer<
      GraphAPI.FetchMyBackedProjectsQuery.Data,
      ErrorEnvelope
    > {
      guard let result = self.fetchBackerBackedProjectsResponse else {
        return .empty
      }
      return SignalProducer(value: result)
    }

    internal func fetchProject(param: Param) -> SignalProducer<Project, ErrorEnvelope> {
      if let demoCatalog { return demoResponse { try demoCatalog.project(param) } }
      guard let result = self.fetchProjectEnvelopeResult else {
        return .empty
      }

      switch result {
      case let .success(project):
        return SignalProducer(value: project)
      case let .failure(error):
        return SignalProducer(error: error)
      }
    }

    // Async fixture access mirrors the legacy project-detail results without
    // creating a reactive execution graph or contacting a live service.
    @MainActor public func projectDetails(param: Param, includeStoryRichText: Bool) async throws -> Project.ProjectPamphletData {
      try Task.checkCancellation()
      if let demoCatalog {
        let project = try demoCatalog.project(param)
        let extras = try demoCatalog.extraProperties(param)
        return Project.ProjectPamphletData(project: extras.addExtraProperties(toProject: project), backingId: nil)
      }
      guard let result = self.fetchProjectPamphletEnvelopeResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func projectDetailsBacking(id: Int) async throws -> ProjectAndBackingEnvelope {
      try Task.checkCancellation()
      guard let result = self.fetchProjectAndBackingResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func projectDetailsRewards(projectID: Int) async throws -> [Reward] {
      try Task.checkCancellation()
      if let demoCatalog { return try demoCatalog.project(.id(projectID)).rewards }
      guard let result = self.fetchProjectRewardsEnvelopeResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func sortedProjectRewards(
      projectID: Int, country: String?, inserter: any NoRewardInserter
    ) async throws -> [Reward] {
      // Legacy fixtures already contain the synthetic no-reward entry.
      try await self.projectDetailsRewards(projectID: projectID)
    }

    @MainActor public func shippingLocations(projectID: Int) async throws -> [Location] {
      try Task.checkCancellation()
      guard let data = try await self.fetch(query: GraphAPI.ShippableLocationsForProjectQuery(id: projectID))
      else { throw ErrorEnvelope.couldNotParseJSON }
      return Location.locations(from: data)
    }

    @MainActor public func relatedProjects(projectID: String) async throws -> GraphAPI.FetchSimilarProjectsQuery.Data {
      try Task.checkCancellation()
      if self.pendingLegacyGraphQLQueries.contains(where: { $0 == GraphAPI.FetchSimilarProjectsQuery.self }) {
        // The fixture deliberately suspends this independent dependency.
        // Cancellation releases it when its route is destroyed.
        try await Task.sleep(nanoseconds: UInt64.max)
        throw CancellationError()
      }
      guard let data = try await self.fetch(query: GraphAPI.FetchSimilarProjectsQuery(projectID: projectID))
      else { throw ErrorEnvelope.couldNotParseJSON }
      return data
    }

    @MainActor public func projectDetailsBase(param: Param) async throws -> Project {
      try Task.checkCancellation()
      if let demoCatalog { return try demoCatalog.project(param) }
      if let result = self.fastFetchProjectPageResult { return try result.0.get() }
      let data = try await self.fetch(query: GraphAPI.FastFetchProjectPageBaseQuery(
        projectId: .someOrNil(param.id), slug: .someOrNil(param.slug)
      ))
      guard let data, let project = Project.project(from: data) else { throw ErrorEnvelope.couldNotParseJSON }
      return project
    }

    @MainActor public func projectDetailsExtras(param: Param, includeStoryRichText: Bool) async throws -> ProjectPageExtraProperties {
      try Task.checkCancellation()
      if let demoCatalog { return try demoCatalog.extraProperties(param) }
      if let result = self.fastFetchProjectPageResult { return try result.1.get() }
      let data = try await self.fetch(query: GraphAPI.FastFetchProjectPageExtendedPropertiesQuery(
        projectId: .someOrNil(param.id), slug: .someOrNil(param.slug), storyRichText: includeStoryRichText
      ))
      guard let data, let extras = ProjectPageExtraProperties.extraProperties(from: data) else { throw ErrorEnvelope.couldNotParseJSON }
      return extras
    }

    @MainActor public func enrollProjectSecretReward(token: String, param: Param) async throws {
      try Task.checkCancellation()
      guard let result = self.addUserToSecretRewardGroup else { throw ErrorEnvelope.couldNotParseJSON }
      _ = try result.get()
    }

    internal func fastFetchProjectPageBase(projectParam: Param)
      -> SignalProducer<Project, ErrorEnvelope> {
      if let demoCatalog { return demoResponse { try demoCatalog.project(projectParam) } }
      // If a result was set, use the result for mocking.
      if let result = self.fastFetchProjectPageResult {
        let baseProjectResult = result.0
        switch baseProjectResult {
        case let .success(project):
          return SignalProducer(value: project)
        case let .failure(error):
          return SignalProducer(error: error)
        }
      }

      // Otherwise, fall back to the GraphQL mocking code.
      let query = GraphAPI.FastFetchProjectPageBaseQuery(
        projectId: .someOrNil(projectParam.id),
        slug: .someOrNil(projectParam.slug)
      )

      return self
        .fetch(query: query)
        .flatMap { Project.projectProducer(from: $0) }
    }

    internal func fastFetchProjectPageExtendedProperties(
      projectParam: Param,
      includeStoryRichText: Bool
    )
      -> SignalProducer<ProjectPageExtraProperties, ErrorEnvelope> {
      if let demoCatalog { return demoResponse { try demoCatalog.extraProperties(projectParam) } }
      // If a result was set, use the result for mocking.
      if let result = self.fastFetchProjectPageResult {
        let extraPropertiesResult = result.1
        switch extraPropertiesResult {
        case let .success(project):
          return SignalProducer(value: project)
        case let .failure(error):
          return SignalProducer(error: error)
        }
      }

      let query = GraphAPI.FastFetchProjectPageExtendedPropertiesQuery(
        projectId: .someOrNil(projectParam.id),
        slug: .someOrNil(projectParam.slug),
        storyRichText: includeStoryRichText
      )

      // Otherwise, fall back to the GraphQL mocking code.
      return self
        .fetch(query: query)
        .flatMap { ProjectPageExtraProperties.extraPropertiesProducer(from: $0) }
    }

    internal func fetchProject(projectParam: Param, includeStoryRichText: Bool)
      -> SignalProducer<Project.ProjectPamphletData, ErrorEnvelope> {
      if let demoCatalog {
        return demoResponse {
          let project = try demoCatalog.project(projectParam)
          let details = try demoCatalog.extraProperties(projectParam)
          return Project.ProjectPamphletData(project: details.addExtraProperties(toProject: project), backingId: nil)
        }
      }
      guard let client = self.apolloClient else {
        return .empty
      }
      let query = GraphAPI.FetchProjectByParamQuery(
        projectId: .someOrNil(projectParam.id),
        slug: .someOrNil(projectParam.slug),
        storyRichText: includeStoryRichText
      )

      return client.fetchWithResult(
        query: query,
        result: self.fetchProjectPamphletEnvelopeResult
      )
    }

    func fetchProjectRewardsAndPledgeOverTimeData(projectId: Int)
      -> SignalProducer<
        RewardsAndPledgeOverTimeEnvelope,
        ErrorEnvelope
      > {
      if let demoCatalog {
        return demoResponse {
          RewardsAndPledgeOverTimeEnvelope(rewards: try demoCatalog.project(.id(projectId)).rewards,
            isPledgeOverTimeAllowed: false, pledgeOverTimeCollectionPlanChargeExplanation: nil,
            pledgeOverTimeCollectionPlanChargedAsNPayments: nil, pledgeOverTimeCollectionPlanShortPitch: nil,
            pledgeOverTimeMinimumExplanation: nil)
        }
      }
      guard let client = self.apolloClient else {
        return .empty
      }

      let query = GraphAPI
        .FetchProjectRewardsByIdQuery(
          projectId: projectId,
          includeShippingRules: false,
          includePledgeOverTime: true
        )

      return client
        .fetchWithResult(
          query: query,
          result: self.fetchProjectRewardsAndPledgeOverTimeDataResult
        )
    }

    internal func fetchProjectRewards(projectId: Int) -> SignalProducer<[Reward], ErrorEnvelope> {
      if let demoCatalog { return demoResponse { try demoCatalog.project(.id(projectId)).rewards } }
      guard let client = self.apolloClient else {
        return .empty
      }

      let fetchProjectRewardsQuery = GraphAPI
        .FetchProjectRewardsByIdQuery(
          projectId: projectId,
          includeShippingRules: false,
          includePledgeOverTime: false
        )

      return client
        .fetchWithResult(
          query: fetchProjectRewardsQuery,
          result: self.fetchProjectRewardsEnvelopeResult
        )
    }

    func fetchProjectRewards(
      projectId: Int,
      sortedForShippingCountryCode _: String?,
      withNoReward _: NoRewardInserter
    ) -> SignalProducer<[Reward], ErrorEnvelope> {
      if let demoCatalog { return demoResponse { try demoCatalog.project(.id(projectId)).rewards } }
      guard let client = self.apolloClient else {
        return .empty
      }

      let fetchProjectRewardsQuery = GraphAPI
        .FetchSortedProjectRewardsByIdQuery(
          projectId: projectId,
          location: nil
        )

      return client
        .fetchWithResult(
          query: fetchProjectRewardsQuery,
          result: self.fetchProjectRewardsEnvelopeResult
        )
    }

    internal func fetchProject(
      _ params: DiscoveryParams
    ) -> SignalProducer<DiscoveryEnvelope, ErrorEnvelope> {
      if let demoCatalog { return demoResponse { try demoCatalog.discovery(params) } }
      if let envelope = self.fetchDiscoveryResponse {
        return SignalProducer(value: envelope)
      }
      let envelope = .template
        |> DiscoveryEnvelope.lens.projects .~ [
          .template |> Project.lens.id .~ params.hashValue
        ]
      return SignalProducer(value: envelope)
    }

    internal func fetchProject_combine(project: Project) -> AnyPublisher<Project, ErrorEnvelope> {
      if let demoCatalog { return demoPublisher { try demoCatalog.project(.id(project.id)) } }
      fatalError("Sorry, this is unimplemented!")
    }

    internal func fetchProjectActivities(forProject _: Project) ->
      SignalProducer<ProjectActivityEnvelope, ErrorEnvelope> {
      if let error = fetchProjectActivitiesError {
        return SignalProducer(error: error)
      } else if let activities = fetchProjectActivitiesResponse {
        return SignalProducer(
          value: ProjectActivityEnvelope(
            activities: activities,
            urls: ProjectActivityEnvelope.UrlsEnvelope(
              api: ProjectActivityEnvelope.UrlsEnvelope.ApiEnvelope(
                moreActivities: "http://\(Secrets.Api.Endpoint.production)/gimme/more"
              )
            )
          )
        )
      }
      return .empty
    }

    internal func fetchProjectActivities(paginationUrl _: String)
      -> SignalProducer<ProjectActivityEnvelope, ErrorEnvelope> {
      if let error = fetchProjectActivitiesError {
        return SignalProducer(error: error)
      } else if let activities = fetchProjectActivitiesResponse {
        return SignalProducer(
          value: ProjectActivityEnvelope(
            activities: activities,
            urls: ProjectActivityEnvelope.UrlsEnvelope(
              api: ProjectActivityEnvelope.UrlsEnvelope.ApiEnvelope(
                moreActivities: ""
              )
            )
          )
        )
      }
      return .empty
    }

    internal func fetchProjects(member _: Bool) -> SignalProducer<ProjectsEnvelope, ErrorEnvelope> {
      if let error = fetchProjectsError {
        return SignalProducer(error: error)
      } else if let projects = fetchProjectsResponse {
        return SignalProducer(
          value: ProjectsEnvelope(
            projects: projects,
            urls: ProjectsEnvelope.UrlsEnvelope(
              api: ProjectsEnvelope.UrlsEnvelope.ApiEnvelope(
                moreProjects: ""
              )
            )
          )
        )
      }
      return .empty
    }

    internal func fetchProjects(paginationUrl _: String) ->
      SignalProducer<ProjectsEnvelope, ErrorEnvelope> {
      return self.fetchProjects(member: true)
    }

    internal func fetchProjectStats(projectId _: Int) ->
      SignalProducer<ProjectStatsEnvelope, ErrorEnvelope> {
      if let error = fetchProjectStatsError {
        return SignalProducer(error: error)
      } else if let response = fetchProjectStatsResponse {
        return SignalProducer(value: response)
      }

      return SignalProducer(value: .template)
    }

    internal func fetchRewardShippingRules(projectId _: Int, rewardId _: Int)
      -> SignalProducer<ShippingRulesEnvelope, ErrorEnvelope> {
      if let error = self.fetchShippingRulesResult?.error {
        return SignalProducer(error: error)
      }

      return SignalProducer(value: .init(shippingRules: self.fetchShippingRulesResult?.value ?? [.template]))
    }

    internal func fetchUserSelf() -> SignalProducer<User, ErrorEnvelope> {
      if let error = fetchUserSelfError {
        return SignalProducer(error: error)
      }

      return SignalProducer(value: self.fetchUserSelfResponse ?? .template)
    }

    func fetchUserSelf_combine(withOAuthToken _: String) -> AnyPublisher<User, ErrorEnvelope> {
      if let error = fetchUserSelfError {
        return Fail(outputType: User.self, failure: self.fetchUserSelfError!).eraseToAnyPublisher()
      }

      return Just(self.fetchUserSelfResponse ?? .template).setFailureType(to: ErrorEnvelope.self)
        .eraseToAnyPublisher()
    }

    internal func fetchSurveyResponse(surveyResponseId id: Int)
      -> SignalProducer<SurveyResponse, ErrorEnvelope> {
      if let response = fetchSurveyResponseResponse {
        return SignalProducer(value: response)
      } else if let error = fetchSurveyResponseError {
        return SignalProducer(error: error)
      }
      return SignalProducer(value: .template |> SurveyResponse.lens.id .~ id)
    }

    internal func fetchUnansweredSurveyResponses() -> SignalProducer<[SurveyResponse], ErrorEnvelope> {
      return SignalProducer(value: self.fetchUnansweredSurveyResponsesResponse)
    }

    internal func fetchUser(userId _: Int) -> SignalProducer<User, ErrorEnvelope> {
      return producer(for: self.fetchUserResult)
    }

    internal func fetchUser(_: User) -> SignalProducer<User, ErrorEnvelope> {
      return producer(for: self.fetchUserResult)
    }

    internal func incrementVideoCompletion(for _: any HasProjectWebURL) ->
      SignalProducer<VoidEnvelope, ErrorEnvelope> {
      if let error = incrementVideoCompletionError {
        return .init(error: error)
      } else {
        return .init(value: VoidEnvelope())
      }
    }

    internal func incrementVideoStart(forProject _: any HasProjectWebURL) ->
      SignalProducer<VoidEnvelope, ErrorEnvelope> {
      if let error = incrementVideoStartError {
        return .init(error: error)
      } else {
        return .init(value: VoidEnvelope())
      }
    }

    @MainActor public func authenticate(
      email _: String, password _: String, code _: String?
    ) async throws -> AccessTokenEnvelope {
      try self.authenticationResponse()
    }

    @MainActor public func authenticate(
      facebookAccessToken _: String, code _: String?
    ) async throws -> AccessTokenEnvelope {
      try self.authenticationResponse()
    }

    @MainActor public func authenticateApple(input _: SignInWithAppleInput) async throws
      -> SignInWithAppleEnvelope {
      try self.requireLiveAuthenticationFixture()
      guard let result = self.signInWithAppleResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func authenticationUser(id _: Int) async throws -> User {
      try self.requireLiveAuthenticationFixture()
      guard let result = self.fetchUserResult else { throw ErrorEnvelope.couldNotParseJSON }
      return try result.get()
    }

    @MainActor public func authenticationUser(oauthToken _: String) async throws -> User {
      try self.requireLiveAuthenticationFixture()
      if let error = self.fetchUserSelfError { throw error }
      return self.fetchUserSelfResponse ?? .template
    }

    @MainActor public func signupFacebook(
      token _: String,
      sendNewsletters _: Bool
    ) async throws -> AccessTokenEnvelope {
      try self.requireLiveAuthenticationFixture()
      if let error = self.signupError { throw error }
      return self.signupResponse ?? AccessTokenEnvelope(accessToken: "deadbeef", user: .template)
    }

    @MainActor public func exchangeOAuth(params _: OAuthTokenExchangeParams) async throws
      -> OAuthTokenExchangeResponse {
      try self.requireLiveAuthenticationFixture()
      if let response = self.tokenExchangeResponse { return response }
      throw self.loginError ?? ErrorEnvelope.couldNotParseJSON
    }

    @MainActor public func requestPasswordReset(email _: String) async throws {
      try self.requireLiveAuthenticationFixture()
      if self.resetPasswordResponse != nil { return }
      if let error = self.resetPasswordError { throw error }
    }

    private func requireLiveAuthenticationFixture() throws {
      try Task.checkCancellation()
      if self.demoCatalog != nil { throw self.loginError ?? ErrorEnvelope.couldNotParseJSON }
    }

    private func authenticationResponse() throws -> AccessTokenEnvelope {
      if let error = self.loginError { throw error }
      if let response = self.loginResponse { return response }
      if let response = self.resendCodeResponse { throw response }
      if let error = self.resendCodeError { throw error }
      return AccessTokenEnvelope(accessToken: "deadbeef", user: .template)
    }

    internal func login(email _: String, password _: String, code _: String?) ->
      SignalProducer<AccessTokenEnvelope, ErrorEnvelope> {
      if let error = loginError {
        return SignalProducer(error: error)
      } else if let accessTokenEnvelope = loginResponse {
        return SignalProducer(value: accessTokenEnvelope)
      } else if let resendCodeResponse = resendCodeResponse {
        return SignalProducer(error: resendCodeResponse)
      } else if let resendCodeError = resendCodeError {
        return SignalProducer(error: resendCodeError)
      }

      return SignalProducer(value: AccessTokenEnvelope(accessToken: "deadbeef", user: .template))
    }

    internal func login(facebookAccessToken _: String, code _: String?) ->
      SignalProducer<AccessTokenEnvelope, ErrorEnvelope> {
      if let error = loginError {
        return SignalProducer(error: error)
      } else if let accessTokenEnvelope = loginResponse {
        return SignalProducer(value: accessTokenEnvelope)
      } else if let resendCodeResponse = resendCodeResponse {
        return SignalProducer(error: resendCodeResponse)
      } else if let resendCodeError = resendCodeError {
        return SignalProducer(error: resendCodeError)
      }

      return SignalProducer(value: AccessTokenEnvelope(accessToken: "deadbeef", user: .template))
    }

    internal func markAsRead(messageThread: MessageThread)
      -> SignalProducer<MessageThread, ErrorEnvelope> {
      return SignalProducer(value: messageThread)
    }

    func postComment(input: PostCommentInput)
      -> SignalProducer<Comment, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .PostCommentMutation(input: GraphAPI.PostCommentInput.from(input))

      return client.performWithResult(mutation: mutation, result: self.postCommentResult)
    }

    func resetPassword(email _: String) -> SignalProducer<User, ErrorEnvelope> {
      if let response = resetPasswordResponse {
        return SignalProducer(value: response)
      } else if let error = resetPasswordError {
        return SignalProducer(error: error)
      }
      return SignalProducer(value: .template)
    }

    func register(pushToken _: String) -> SignalProducer<VoidEnvelope, ErrorEnvelope> {
      return SignalProducer(value: VoidEnvelope())
    }

    internal func searchMessages(query _: String, project _: Project?)
      -> SignalProducer<MessageThreadsEnvelope, ErrorEnvelope> {
      return SignalProducer(
        value:
        MessageThreadsEnvelope(
          messageThreads: self.fetchMessageThreadsResponse,
          urls: MessageThreadsEnvelope.UrlsEnvelope(
            api: MessageThreadsEnvelope.UrlsEnvelope.ApiEnvelope(
              moreMessageThreads: ""
            )
          )
        )
      )
    }

    internal func sendMessage(body: String, toSubject _: MessageSubject)
      -> SignalProducer<Message, ErrorEnvelope> {
      return SignalProducer(
        value: .template
          |> Message.lens.id .~ body.hashValue
          |> Message.lens.body .~ body
      )
    }

    internal func sendVerificationEmail(input _: EmptyInput)
      -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutationSendVerificationEmail = GraphAPI
        .UserSendEmailVerificationMutation(input: GraphAPI.UserSendEmailVerificationInput())

      return client
        .performWithResult(mutation: mutationSendVerificationEmail, result: self.sendEmailVerificationResult)
    }

    internal func signInWithApple(input: SignInWithAppleInput)
      -> SignalProducer<SignInWithAppleEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutationSignInWithApple = GraphAPI
        .SignInWithAppleMutation(input: GraphAPI.SignInWithAppleInput.from(input))

      return client
        .performWithResult(mutation: mutationSignInWithApple, result: self.signInWithAppleResult)
    }

    internal func signup(facebookAccessToken _: String, sendNewsletters _: Bool) ->
      SignalProducer<AccessTokenEnvelope, ErrorEnvelope> {
      if let error = signupError {
        return SignalProducer(error: error)
      } else if let accessTokenEnvelope = signupResponse {
        return SignalProducer(value: accessTokenEnvelope)
      }
      return SignalProducer(
        value:
        AccessTokenEnvelope(
          accessToken: "deadbeef",
          user: .template
        )
      )
    }

    internal func updateProjectNotification(_ notification: ProjectNotification)
      -> SignalProducer<ProjectNotification, ErrorEnvelope> {
      if let error = updateProjectNotificationError {
        return SignalProducer(error: error)
      }
      return SignalProducer(value: notification)
    }

    internal func updateUserSelf(_ user: User) -> SignalProducer<User, ErrorEnvelope> {
      if let error = updateUserSelfError {
        return SignalProducer(error: error)
      }
      return SignalProducer(value: user)
    }

    internal func fetchUpdate(updateId: Int, projectParam _: Param)
      -> SignalProducer<Update, ErrorEnvelope> {
      return SignalProducer(value: self.fetchUpdateResponse |> Update.lens.id .~ updateId)
    }

    internal func fetchUpdateDraft(forProject _: Project) -> SignalProducer<UpdateDraft, ErrorEnvelope> {
      if let error = self.fetchDraftError {
        return SignalProducer(error: error)
      }
      return SignalProducer(value: self.fetchDraftResponse ?? .template)
    }

    internal func update(draft: UpdateDraft, title: String, body: String, isPublic: Bool)
      -> SignalProducer<UpdateDraft, ErrorEnvelope> {
      if let error = self.updateDraftError {
        return SignalProducer(error: error)
      }
      let updatedDraft = draft
        |> UpdateDraft.lens.update.title .~ title
        |> UpdateDraft.lens.update.body .~ body
        |> UpdateDraft.lens.update.isPublic .~ isPublic

      return SignalProducer(value: updatedDraft)
    }

    internal func updateBacking(input: UpdateBackingInput)
      -> SignalProducer<UpdateBackingEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutationUpdateBacking = GraphAPI
        .UpdateBackingMutation(input: GraphAPI.UpdateBackingInput.from(input))

      return client
        .performWithResult(mutation: mutationUpdateBacking, result: self.updateBackingResult)
    }

    internal func unwatchProject(input: WatchProjectInput)
      -> SignalProducer<WatchProjectResponseEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutationUnwatchProject = GraphAPI
        .UnwatchProjectMutation(input: GraphAPI.UnwatchProjectInput.from(input))

      return client
        .performWithResult(mutation: mutationUnwatchProject, result: self.unwatchProjectMutationResult)
    }

    internal func validateCheckout(
      checkoutId _: String,
      paymentSourceId _: String,
      paymentIntentClientSecret _: String
    ) -> SignalProducer<ValidateCheckoutEnvelope, ErrorEnvelope> {
      return producer(for: self.validateCheckoutResult)
    }

    internal func verifyEmail(withToken _: String)
      -> SignalProducer<EmailVerificationResponseEnvelope, ErrorEnvelope> {
      return producer(for: self.verifyEmailResult)
    }

    internal func watchProject(input: WatchProjectInput)
      -> SignalProducer<WatchProjectResponseEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutationWatchProject = GraphAPI.WatchProjectMutation(input: GraphAPI.WatchProjectInput.from(input))

      return client
        .performWithResult(mutation: mutationWatchProject, result: self.watchProjectMutationResult)
    }

    internal func addImage(file _: URL, toDraft _: UpdateDraft)
      -> SignalProducer<UpdateDraft.Image, ErrorEnvelope> {
      if let error = addAttachmentError {
        return SignalProducer(error: error)
      }

      return SignalProducer(value: self.addAttachmentResponse ?? .template)
    }

    internal func delete(image _: UpdateDraft.Image, fromDraft _: UpdateDraft)
      -> SignalProducer<UpdateDraft.Image, ErrorEnvelope> {
      if let error = removeAttachmentError {
        return SignalProducer(error: error)
      }

      return SignalProducer(value: self.removeAttachmentResponse ?? .template)
    }

    internal func deletePaymentMethod(input: PaymentSourceDeleteInput) -> SignalProducer<
      DeletePaymentMethodEnvelope, ErrorEnvelope
    > {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .DeletePaymentSourceMutation(input: GraphAPI.PaymentSourceDeleteInput.from(input))

      return client.performWithResult(mutation: mutation, result: self.deletePaymentMethodResult)
    }

    internal func triggerThirdPartyEventInput(input: TriggerThirdPartyEventInput) -> ReactiveSwift
      .SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
      guard let client = self.apolloClient else {
        return .empty
      }

      let mutation = GraphAPI
        .TriggerThirdPartyEventMutation(input: GraphAPI.TriggerThirdPartyEventInput.from(input))

      return client.performWithResult(mutation: mutation, result: self.triggerThirdPartyEventResult)
    }

    internal func publish(draft _: UpdateDraft) -> SignalProducer<Update, ErrorEnvelope> {
      if let error = publishUpdateError {
        return SignalProducer(error: error)
      }

      return SignalProducer(value: self.fetchUpdateResponse)
    }

    internal func previewUrl(forDraft draft: UpdateDraft) -> URL? {
      return URL(
        string: "https://\(Secrets.Api.Endpoint.production)/projects/\(draft.update.projectId)/updates/"
          + "\(draft.update.id)/preview"
      )
    }

    func fetchDiscovery_combine(params: DiscoveryParams) -> AnyPublisher<DiscoveryEnvelope, ErrorEnvelope> {
      if let demoCatalog { return demoPublisher { try demoCatalog.discovery(params) } }
      return Empty(completeImmediately: false).eraseToAnyPublisher()
    }

    func fetchDiscovery_combine(paginationUrl: String) -> AnyPublisher<DiscoveryEnvelope, ErrorEnvelope> {
      if let demoCatalog { return demoPublisher { try demoCatalog.discovery(paginationURL: paginationUrl) } }
      return Empty(completeImmediately: false).eraseToAnyPublisher()
    }

    func exchangeTokenForOAuthToken(params _: OAuthTokenExchangeParams)
      -> AnyPublisher<OAuthTokenExchangeResponse, ErrorEnvelope> {
      if let tokenExchangeResponse = self.tokenExchangeResponse {
        return Just(tokenExchangeResponse).setFailureType(to: ErrorEnvelope.self).eraseToAnyPublisher()
      } else if let loginError = self.loginError {
        return Fail(outputType: OAuthTokenExchangeResponse.self, failure: loginError).eraseToAnyPublisher()
      } else {
        return Empty(completeImmediately: false).eraseToAnyPublisher()
      }
    }

    func confirmBackingAddress(
      backingId _: String,
      addressId _: String
    ) -> AnyPublisher<Bool, ErrorEnvelope> {
      guard let confirmResponse = self.confirmBackingAddressResult else {
        return Fail(outputType: Bool.self, failure: ErrorEnvelope.couldNotParseErrorEnvelopeJSON)
          .eraseToAnyPublisher()
      }

      switch confirmResponse {
      case let .success(didMutationSucceed):
        return Just(didMutationSucceed).setFailureType(to: ErrorEnvelope.self).eraseToAnyPublisher()

      case let .failure(envelope):
        return Fail(outputType: Bool.self, failure: envelope).eraseToAnyPublisher()
      }
    }

    func fetchPledgedProjects(
      tierTypes _: [PledgeProjectsOverviewSort],
      cursor _: String?,
      limit _: Int?
    ) -> AnyPublisher<GraphAPI.FetchPledgedProjectsQuery.Data, ErrorEnvelope> {
      guard let response = self.fetchPledgedProjectsResult else {
        return Fail(
          outputType: GraphAPI.FetchPledgedProjectsQuery.Data.self,
          failure: ErrorEnvelope.couldNotParseErrorEnvelopeJSON
        )
        .eraseToAnyPublisher()
      }

      switch response {
      case let .success(pledgedProjectsData):
        return Just(pledgedProjectsData).setFailureType(to: ErrorEnvelope.self).delay(
          for: 0.01,
          scheduler: DispatchQueue.main
        ).eraseToAnyPublisher()

      case let .failure(envelope):
        return Fail(outputType: GraphAPI.FetchPledgedProjectsQuery.Data.self, failure: envelope)
          .eraseToAnyPublisher()
      }
    }
  }

  private extension MockService {
    enum lens {
      static let oauthToken = Lens<MockService, OauthTokenAuthType?>(
        view: { $0.oauthToken },
        set: {
          MockService(
            appId: $1.appId,
            serverConfig: $1.serverConfig,
            oauthToken: $0,
            language: $1.language,
            buildVersion: $1.buildVersion,
            addNewCreditCardResult: $1.addNewCreditCardResult,
            fetchFlaggingOptionsResult: $1.fetchFlaggingOptionsResult,
            changePaymentMethodResult: $1.changePaymentMethodResult,
            deletePaymentMethodResult: $1.deletePaymentMethodResult,
            clearUserUnseenActivityResult: $1.clearUserUnseenActivityResult,
            facebookConnectResponse: $1.facebookConnectResponse,
            facebookConnectError: $1.facebookConnectError,
            fetchActivitiesResponse: $1.fetchActivitiesResponse,
            fetchActivitiesError: $1.fetchActivitiesError,
            fetchBackingResponse: $1.fetchBackingResponse,
            fetchGraphCategoryResult: $1.fetchGraphCategoryResult,
            fetchGraphCategoriesResult: $1.fetchGraphCategoriesResult,
            fetchProjectCommentsEnvelopeResult: $1.fetchProjectCommentsEnvelopeResult,
            fetchConfigResponse: $1.fetchConfigResponse,
            fetchDiscoveryResponse: $1.fetchDiscoveryResponse,
            fetchDiscoveryError: $1.fetchDiscoveryError,
            fetchFriendsResponse: $1.fetchFriendsResponse,
            fetchFriendsError: $1.fetchFriendsError,
            fetchFriendStatsResponse: $1.fetchFriendStatsResponse,
            fetchFriendStatsError: $1.fetchFriendStatsError,
            fetchDraftResponse: $1.fetchDraftResponse,
            fetchDraftError: $1.fetchDraftError,
            fetchGraphUserResult: $1.fetchGraphUserResult,
            fetchGraphUserSelfResult: $1.fetchGraphUserSelfResult,
            fetchGraphUserEmailResult: $1.fetchGraphUserEmailResult,
            addAttachmentResponse: $1.addAttachmentResponse,
            addAttachmentError: $1.addAttachmentError,
            removeAttachmentResponse: $1.removeAttachmentResponse,
            removeAttachmentError: $1.removeAttachmentError,
            publishUpdateError: $1.publishUpdateError,
            fetchManagePledgeViewBackingResult: $1.fetchManagePledgeViewBackingResult,
            fetchProjectAndBackingResult: $1.fetchProjectAndBackingResult,
            fetchMessageThreadResult: $1.fetchMessageThreadResult,
            fetchMessageThreadsResponse: $1.fetchMessageThreadsResponse,
            fetchProjectResult: $1.fetchProjectEnvelopeResult,
            fetchProjectFriendsResult: $1.fetchProjectFriendsEnvelopeResult,
            fetchProjectRewardsResult: $1.fetchProjectRewardsEnvelopeResult,
            fetchProjectActivitiesResponse: $1.fetchProjectActivitiesResponse,
            fetchProjectActivitiesError: $1.fetchProjectActivitiesError,
            fetchProjectNotificationsResponse: $1.fetchProjectNotificationsResponse,
            fetchProjectsResponse: $1.fetchProjectsResponse,
            fetchProjectsError: $1.fetchProjectsError,
            fetchProjectStatsResponse: $1.fetchProjectStatsResponse,
            fetchProjectStatsError: $1.fetchProjectStatsError,
            fetchShippingRulesResult: $1.fetchShippingRulesResult,
            fetchUserResult: $1.fetchUserResult,
            fetchUserSelfResponse: $1.fetchUserSelfResponse,
            followFriendError: $1.followFriendError,
            incrementVideoCompletionError: $1.incrementVideoCompletionError,
            incrementVideoStartError: $1.incrementVideoStartError,
            fetchSurveyResponseResponse: $1.fetchSurveyResponseResponse,
            fetchSurveyResponseError: $1.fetchSurveyResponseError,
            fetchUnansweredSurveyResponsesResponse: $1.fetchUnansweredSurveyResponsesResponse,
            fetchUpdateResponse: $1.fetchUpdateResponse,
            fetchUserSelfError: $1.fetchUserSelfError,
            postCommentResult: $1.postCommentResult,
            loginResponse: $1.loginResponse,
            loginError: $1.loginError,
            resendCodeResponse: $1.resendCodeResponse,
            resendCodeError: $1.resendCodeError,
            resetPasswordResponse: $1.resetPasswordResponse,
            resetPasswordError: $1.resetPasswordError,
            signupResponse: $1.signupResponse,
            signupError: $1.signupError,
            unfollowFriendError: $1.unfollowFriendError,
            updateBackingResult: $1.updateBackingResult,
            updateDraftError: $1.updateDraftError,
            updatePledgeResult: $1.updatePledgeResult,
            updateProjectNotificationResponse: $1.updateProjectNotificationResponse,
            updateProjectNotificationError: $1.updateProjectNotificationError,
            updateUserSelfError: $1.updateUserSelfError,
            unwatchProjectMutationResult: $1.unwatchProjectMutationResult,
            watchProjectMutationResult: $1.watchProjectMutationResult,
            demoCatalog: $1.demoCatalog
          )
        }
      )
    }
  }

  /// Cold producers retain the existing caller-owned cancellation/scheduler behavior.
  private func demoPublisher<Value>(_ response: @escaping () throws -> Value)
    -> AnyPublisher<Value, ErrorEnvelope> {
    Deferred { () -> AnyPublisher<Value, ErrorEnvelope> in
      do { return Just(try response()).setFailureType(to: ErrorEnvelope.self).eraseToAnyPublisher() }
      catch let error as ErrorEnvelope { return Fail(error: error).eraseToAnyPublisher() }
      catch { return Fail(error: ErrorEnvelope.couldNotParseJSON).eraseToAnyPublisher() }
    }.eraseToAnyPublisher()
  }

  private func demoResponse<Value>(_ response: @escaping () throws -> Value)
    -> SignalProducer<Value, ErrorEnvelope> {
    SignalProducer { observer, _ in
      do { observer.send(value: try response()); observer.sendCompleted() }
      catch let error as ErrorEnvelope { observer.send(error: error) }
      catch { observer.send(error: ErrorEnvelope.couldNotParseJSON) }
    }
  }

  private func producer<T, E>(for property: Result<T, E>?) -> SignalProducer<T, E> {
    guard let result = property else { return .empty }
    switch result {
    case let .success(value): return .init(value: value)
    case let .failure(error): return .init(error: error)
    }
  }

  private extension Result {
    var value: Success? {
      switch self {
      case let .success(value): return value
      case .failure: return nil
      }
    }

    var error: Failure? {
      switch self {
      case .success: return nil
      case let .failure(error): return error
      }
    }
  }

  extension GraphAPI.CompleteOnSessionCheckoutMutation.Data: Decodable {
    public init(from _: Decoder) throws {
      fatalError("The test code should not actually be decoding this object.")
    }
  }

  extension GraphAPI.BuildPaymentPlanQuery.Data: Decodable {
    public init(from _: Decoder) throws {
      fatalError("The test code should not actually be decoding this object.")
    }
  }

#endif
