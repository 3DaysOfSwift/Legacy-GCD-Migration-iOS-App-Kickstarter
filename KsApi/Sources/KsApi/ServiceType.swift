import Apollo
import ApolloAPI
import Combine
import GraphAPI
import Prelude
import ReactiveSwift
import UIKit

public enum Mailbox: String {
  case inbox
  case sent
}

/*
 *
 A type that knows how to perform requests for Kickstarter data.
 */
public protocol ServiceType {
  @MainActor func pledgedProjects(tiers: [GraphAPI.PledgeProjectsOverviewSort], cursor: String?, limit: Int) async throws -> GraphAPI.FetchPledgedProjectsQuery.Data
  @MainActor func confirmPledgeAddress(backingID: String, addressID: String) async throws -> Bool
  @MainActor func setPledgeReceipt(backingID: String, received: Bool) async throws -> Bool
  @MainActor func pledgePaymentPlan(slug: String, amount: String) async throws -> PledgePaymentPlan?
  @MainActor func openPledgeCheckout(_ input: CreateCheckoutInput) async throws -> CreateCheckoutEnvelope
  @MainActor func checkPledgeCheckout(checkoutID: String, sourceID: String, secret: String) async throws -> ValidateCheckoutEnvelope
  @MainActor func finishPledgeCheckout(_ input: GraphAPI.CompleteOnSessionCheckoutInput) async throws
  @MainActor func managedPledgeBacking(id: Int) async throws -> Backing
  @MainActor func managedPledgeRewards(projectID: Int) async throws -> RewardsAndPledgeOverTimeEnvelope
  @MainActor func submitPledge(_ input: CreateBackingInput) async throws -> CreateBackingEnvelope
  @MainActor func revisePledge(_ input: UpdateBackingInput) async throws -> UpdateBackingEnvelope
  @MainActor func cancelPledge(_ input: CancelBackingInput) async throws
  @MainActor func markPledgeReceived(projectID: Int, userID: Int, received: Bool) async throws -> Backing
  @MainActor func paymentCards() async throws -> UserEnvelope<GraphUser>
  @MainActor func removePaymentMethod(id: String) async throws -> DeletePaymentMethodEnvelope
  @MainActor func storePaymentMethod(secret: String) async throws -> CreatePaymentSourceEnvelope
  @MainActor func paymentSetupIntent(input: CreateSetupIntentInput) async throws -> ClientSecretEnvelope
  @MainActor func paymentIntent(input: CreatePaymentIntentInput) async throws -> PaymentIntentEnvelope

  var appId: String { get }
  var serverConfig: ServerConfigType { get }
  var oauthToken: OauthTokenAuthType? { get }
  var language: String { get }
  var currency: String { get }
  var buildVersion: String { get }
  var deviceIdentifier: String { get }
  var apolloClient: ApolloClientType? { get }

  init(
    appId: String,
    serverConfig: ServerConfigType,
    oauthToken: OauthTokenAuthType?,
    language: String,
    currency: String,
    buildVersion: String,
    deviceIdentifier: String,
    apolloClient: ApolloClientType?
  )

  /// Adds a user to a secret reward user group
  func addUserToSecretRewardGroup(token: String, forProject param: Param) ->
    SignalProducer<EmptyResponseEnvelope, ErrorEnvelope>

  /// Fetches a GraphQL query and returns the data.
  func fetch<Q: GraphQLQuery>(query: Q) -> SignalProducer<Q.Data, ErrorEnvelope>

  /// Fetches a GraphQL query with async/await and returns the data.
  func fetch<Q: GraphQLQuery>(query: Q) async throws -> Q.Data?

  /// Search opts into cancellation without changing unrelated query contracts.
  @MainActor func fetchSearchPage(query: GraphAPI.SearchQuery) async throws -> GraphAPI.SearchQuery.Data
  @MainActor func fetchSearchCategories() async throws -> RootCategoriesEnvelope
  @MainActor func fetchSearchDefaultLocations() async throws -> [Location]
  @MainActor func fetchSearchLocations(term: String) async throws -> [Location]

  /// Cancellation-aware project-detail operations. Legacy callers keep their existing APIs.
  @MainActor func projectDetails(param: Param, includeStoryRichText: Bool) async throws -> Project.ProjectPamphletData
  @MainActor func projectDetailsBacking(id: Int) async throws -> ProjectAndBackingEnvelope
  @MainActor func projectDetailsRewards(projectID: Int) async throws -> [Reward]
  @MainActor func sortedProjectRewards(projectID: Int, country: String?, inserter: any NoRewardInserter) async throws -> [Reward]
  @MainActor func relatedProjects(projectID: String) async throws -> GraphAPI.FetchSimilarProjectsQuery.Data
  @MainActor func shippingLocations(projectID: Int) async throws -> [Location]
  @MainActor func projectDetailsBase(param: Param) async throws -> Project
  @MainActor func projectDetailsExtras(param: Param, includeStoryRichText: Bool) async throws -> ProjectPageExtraProperties
  @MainActor func enrollProjectSecretReward(token: String, param: Param) async throws

  /// Returns a new service with the oauth token replaced.
  func login(_ oauthToken: OauthTokenAuthType) -> Self

  /// Returns a new service with the oauth token set to `nil`.
  func logout() -> Self

  /// Request to connect user to Facebook with access token.
  func facebookConnect(facebookAccessToken token: String) -> SignalProducer<User, ErrorEnvelope>

  /// Uploads and attaches an image to the draft of a project update.
  func addImage(file fileURL: URL, toDraft draft: UpdateDraft)
    -> SignalProducer<UpdateDraft.Image, ErrorEnvelope>

  /// Sends facebook ad data and/or google analytics data relevant to the user
  func triggerThirdPartyEventInput(input: TriggerThirdPartyEventInput)
    -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope>

  /// Returns Pledge Over Time payment plan data.
  func buildPaymentPlan(projectSlug: String, pledgeAmount: String)
    -> SignalProducer<GraphAPI.BuildPaymentPlanQuery.Data, ErrorEnvelope>

  /// Cancels a backing
  func cancelBacking(input: CancelBackingInput)
    -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope>

  /// Changes the email on a user account
  func changeEmail(input: ChangeEmailInput) ->
    SignalProducer<EmptyResponseEnvelope, ErrorEnvelope>

  /// Changes the password on a user account
  func changePassword(input: ChangePasswordInput) ->
    SignalProducer<EmptyResponseEnvelope, ErrorEnvelope>

  /// Changes the currency code on a user profile
  func changeCurrency(input: ChangeCurrencyInput) ->
    SignalProducer<EmptyResponseEnvelope, ErrorEnvelope>

  /// Clears the user's unseen activity count.
  func clearUserUnseenActivity(input: EmptyInput)
    -> SignalProducer<ClearUserUnseenActivityEnvelope, ErrorEnvelope>

  /// Let the server know to create/track an attribution event.
  @MainActor func recordProjectAttribution(input: GraphAPI.CreateAttributionEventInput) async throws
  func createAttributionEvent(input: GraphAPI.CreateAttributionEventInput) ->
    SignalProducer<EmptyResponseEnvelope, ErrorEnvelope>

  func createBacking(input: CreateBackingInput) ->
    SignalProducer<CreateBackingEnvelope, ErrorEnvelope>

  func completeOnSessionCheckout(input: GraphAPI.CompleteOnSessionCheckoutInput) ->
    SignalProducer<GraphAPI.CompleteOnSessionCheckoutMutation.Data, ErrorEnvelope>

  /// Create a checkout and returns it. Called before createBacking so that the backend can run some extra validations.
  func createCheckout(input: CreateCheckoutInput) ->
    SignalProducer<CreateCheckoutEnvelope, ErrorEnvelope>

  /// Sends report project data for a specific project
  func createFlaggingInput(input: CreateFlaggingInput)
    -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope>

  func createFlaggingInputCombine(input: CreateFlaggingInput)
    -> AnyPublisher<EmptyResponseEnvelope, ErrorEnvelope>

  /// Fetches and maps flagging options for a given content type (e.g. project, comment, backing).
  @MainActor func recommendationCategory(id: String) async throws -> Category
  @MainActor func reportingEmail() async throws -> String?
  @MainActor func submitProjectReport(input: CreateFlaggingInput) async throws
  func fetchProjectFlaggingOptions() async throws -> [ReportProjectInfoListItem]

  /// Sends report project data for a specific project
  func createPaymentIntentInput(input: CreatePaymentIntentInput)
    -> SignalProducer<PaymentIntentEnvelope, ErrorEnvelope>

  /// Creates the password on a user account
  func createPassword(input: CreatePasswordInput) ->
    SignalProducer<EmptyResponseEnvelope, ErrorEnvelope>

  /// Create Stripe setup intent for use with Stripe payment sheet
  func createStripeSetupIntent(input: CreateSetupIntentInput) ->
    SignalProducer<ClientSecretEnvelope, ErrorEnvelope>

  /// Adds a new credit card to users' payment methods
  func addNewCreditCard(input: CreatePaymentSourceInput) ->
    SignalProducer<CreatePaymentSourceEnvelope, ErrorEnvelope>

  /// Adds a new Stripe payment source to users' payment methods
  func addPaymentSheetPaymentSource(input: CreatePaymentSourceSetupIntentInput) ->
    SignalProducer<CreatePaymentSourceEnvelope, ErrorEnvelope>

  /// Deletes a payment method
  func deletePaymentMethod(input: PaymentSourceDeleteInput) ->
    SignalProducer<DeletePaymentMethodEnvelope, ErrorEnvelope>

  /// Removes an image from a project update draft.
  func delete(image: UpdateDraft.Image, fromDraft draft: UpdateDraft)
    -> SignalProducer<UpdateDraft.Image, ErrorEnvelope>

  /// Fetch a page of activities.
  func fetchActivities(count: Int?) -> SignalProducer<ActivityEnvelope, ErrorEnvelope>

  /// Fetch activities from a pagination URL
  func fetchActivities(paginationUrl: String) -> SignalProducer<ActivityEnvelope, ErrorEnvelope>

  /// Fetches the current user's backing for the project, if it exists.
  func fetchBacking(forProject project: Project, forUser user: User)
    -> SignalProducer<Backing, ErrorEnvelope>

  /// Native discussion reads and independent playback-counter events.
  @MainActor func discussionComments(
    slug: String?, updateID: String?, cursor: String?
  ) async throws -> CommentsEnvelope
  @MainActor func discussionReplies(id: String, cursor: String?) async throws -> CommentRepliesEnvelope
  @MainActor func discussionProject(param: Param) async throws -> Project
  @MainActor func submitDiscussionComment(input: PostCommentInput) async throws -> Comment
  @MainActor func blockDiscussionUser(id: String) async throws -> EmptyResponseEnvelope
  @MainActor func projectUpdate(id: Int, project: Param) async throws -> Update
  @MainActor func reportVideoEvent(project: any HasProjectWebURL, completed: Bool) async throws -> VoidEnvelope
  @MainActor func projectVideoFeed() async throws -> GraphAPI.VideoFeedQuery.Data
  @MainActor func messageThreadsPage(mailbox: Mailbox, project: Project?, cursor: String?) async throws -> MessageThreadsEnvelope
  @MainActor func messageSearch(query: String, project: Project?) async throws -> MessageThreadsEnvelope
  @MainActor func messageThread(id: Int) async throws -> MessageThreadEnvelope
  @MainActor func messageThread(backing: Backing) async throws -> MessageThreadEnvelope?
  @MainActor func messageBacking(project: Project, user: User) async throws -> Backing
  @MainActor func readMessageThread(_ thread: MessageThread) async throws -> MessageThread
  @MainActor func submitMessage(body: String, subject: MessageSubject) async throws -> Message

  @MainActor func activityPage(cursor: String?) async throws -> ActivityEnvelope
  @MainActor func unansweredSurveys() async throws -> [SurveyResponse]
  @MainActor func sessionUser() async throws -> User
  @MainActor func accountEmailUser() async throws -> GraphUser
  @MainActor func sessionSetup() async throws -> GraphUserSetup
  @MainActor func confirmEmail(token: String) async throws -> EmailVerificationResponseEnvelope
  @MainActor func saveEmail(_ input: ChangeEmailInput) async throws
  @MainActor func savePassword(_ input: ChangePasswordInput) async throws
  @MainActor func setInitialPassword(_ input: CreatePasswordInput) async throws
  @MainActor func saveCurrency(_ input: ChangeCurrencyInput) async throws
  @MainActor func requestEmailVerification() async throws
  @MainActor func connectFacebook(token: String) async throws -> User
  @MainActor func saveAccountPreferences(_ user: User) async throws -> User
  @MainActor func projectNotificationSettings() async throws -> [ProjectNotification]
  @MainActor func saveProjectNotification(_ notification: ProjectNotification) async throws -> ProjectNotification
  @MainActor func authenticate(email: String, password: String, code: String?) async throws -> AccessTokenEnvelope
  @MainActor func authenticate(facebookAccessToken: String, code: String?) async throws -> AccessTokenEnvelope
  @MainActor func authenticateApple(input: SignInWithAppleInput) async throws -> SignInWithAppleEnvelope
  @MainActor func authenticationUser(id: Int) async throws -> User
  @MainActor func authenticationUser(oauthToken: String) async throws -> User
  @MainActor func signupFacebook(token: String, sendNewsletters: Bool) async throws -> AccessTokenEnvelope
  @MainActor func exchangeOAuth(params: OAuthTokenExchangeParams) async throws -> OAuthTokenExchangeResponse
  @MainActor func requestPasswordReset(email: String) async throws
  @MainActor func sessionGraphUser() async throws -> User
  @MainActor func clearActivityIndicator() async throws -> Int
  @MainActor func profileBackedProjects(cursor: String?) async throws -> GraphAPI.FetchMyBackedProjectsQuery
    .Data
  @MainActor func profileSavedProjects(cursor: String?) async throws -> GraphAPI.FetchMySavedProjectsQuery
    .Data
  @MainActor func setProjectWatched(id: String, watched: Bool) async throws -> WatchProjectResponseEnvelope

  /// Fetch comments for a project with a slug, cursor and limit.
  func fetchProjectComments(
    slug: String,
    cursor: String?,
    limit: Int?
  ) -> SignalProducer<CommentsEnvelope, ErrorEnvelope>

  /// Fetch comments for an update with an id, cursor, limit and comments' users' stored cards.
  func fetchUpdateComments(
    id: String,
    cursor: String?,
    limit: Int?
  ) -> SignalProducer<CommentsEnvelope, ErrorEnvelope>

  /// Fetch comment replies for a comment with an id, limit, cursor and user information with stored cards.
  func fetchCommentReplies(
    id: String,
    cursor: String?,
    limit: Int
  ) -> SignalProducer<CommentRepliesEnvelope, ErrorEnvelope>

  /// Fetch the config.
  @MainActor func applicationConfiguration() async throws -> Config
  @MainActor func applicationSurvey(id: Int) async throws -> SurveyResponse
  @MainActor func registerApplicationPushToken(_ token: String) async throws

  func fetchConfig() -> SignalProducer<Config, ErrorEnvelope>

  /// Fetch discovery envelope with a pagination url.
  func fetchDiscovery(paginationUrl: String) -> SignalProducer<DiscoveryEnvelope, ErrorEnvelope>

  /// Fetch the full discovery envelope with specified discovery params.
  func fetchDiscovery(params: DiscoveryParams) -> SignalProducer<DiscoveryEnvelope, ErrorEnvelope>

  @MainActor func richTextExampleProjects() async throws -> GraphAPI.RichTextExampleProjectsQuery.Data
  @MainActor func richTextExampleProject(slug: String) async throws -> GraphAPI.RichTextExampleProjectBySlugQuery.Data

  @MainActor func discoveryPage(params: DiscoveryParams) async throws -> DiscoveryEnvelope
  @MainActor func discoveryPage(paginationURL: String) async throws -> DiscoveryEnvelope
  func discoveryActivitySample() async throws -> ActivityEnvelope?

  /// Fetch friends for a user.
  @MainActor func friendsPage(cursor: String?) async throws -> FindFriendsEnvelope
  @MainActor func friendStatistics() async throws -> FriendStatsEnvelope
  @MainActor func followUser(id: Int) async throws -> User
  @MainActor func unfollowUser(id: Int) async throws
  @MainActor func followEveryFriend() async throws

  func fetchFriends() -> SignalProducer<FindFriendsEnvelope, ErrorEnvelope>

  /// Fetch friends from a pagination url.
  func fetchFriends(paginationUrl: String) -> SignalProducer<FindFriendsEnvelope, ErrorEnvelope>

  /// Fetch friend stats.
  func fetchFriendStats() -> SignalProducer<FriendStatsEnvelope, ErrorEnvelope>

  /// Fetch Categories objects using graphQL.
  func fetchGraphCategories() -> SignalProducer<RootCategoriesEnvelope, ErrorEnvelope>

  /// Fetch Category objects using graphQL.
  func fetchGraphCategory(id: String)
    -> SignalProducer<CategoryEnvelope, ErrorEnvelope>

  /// Fetches various fields of a given User using graphQL.
  func fetchGraphUser(withStoredCards: Bool)
    -> SignalProducer<UserEnvelope<GraphUser>, ErrorEnvelope>

  /// Fetches the email of the currently logged in User.
  func fetchGraphUserEmail()
    -> SignalProducer<UserEnvelope<GraphUserEmail>, ErrorEnvelope>

  func fetchGraphUserEmailCombine()
    -> AnyPublisher<UserEnvelope<GraphUserEmail>, ErrorEnvelope>

  /// Fetches the email of the currently logged in User.
  func fetchGraphUserSetup()
    -> SignalProducer<UserEnvelope<GraphUserSetup>, ErrorEnvelope>

  func fetchGraphUserSetupCombine()
    -> AnyPublisher<UserEnvelope<GraphUserSetup>, ErrorEnvelope>

  /// Fetches GraphQL user fragment and returns User instance.
  func fetchGraphUserSelf()
    -> SignalProducer<UserEnvelope<User>, ErrorEnvelope>

  /// Fetch `Backing` data, and the backing's `Project`, using a `Backing` ID.
  /// - Parameters:
  ///    - id: backing ID
  func fetchBacking(id: Int)
    -> SignalProducer<ProjectAndBackingEnvelope, ErrorEnvelope>

  /// Explicitly fetches a `Backing`, with suitable information for loading the Manage Pledge page.
  /// `refundedAmount`is included in the `paymentIncrements`.
  /// - Parameters:
  ///    - id: backing ID
  func fetchBackingForManagePledge(id: Int)
    -> SignalProducer<Backing, ErrorEnvelope>

  /// Fetches all of the messages in a particular message thread.
  func fetchMessageThread(messageThreadId: Int)
    -> SignalProducer<MessageThreadEnvelope, ErrorEnvelope>

  /// Fetches all of the messages related to a particular backing.
  func fetchMessageThread(backing: Backing) -> SignalProducer<MessageThreadEnvelope?, ErrorEnvelope>

  /// Fetches all of the messages in a particular mailbox and specific to a particular project.
  func fetchMessageThreads(mailbox: Mailbox, project: Project?)
    -> SignalProducer<MessageThreadsEnvelope, ErrorEnvelope>

  /// Fetches more messages threads from a pagination URL.
  func fetchMessageThreads(paginationUrl: String)
    -> SignalProducer<MessageThreadsEnvelope, ErrorEnvelope>

  /// Fetch the newest data for a particular project from its id or slug. (v1)
  func fetchProject(param: Param) -> SignalProducer<Project, ErrorEnvelope>

  /// Fetch the newest data for a particular project from its id or slug. Includes backings and rewards.
  /// Does not included extended project properties, shipping, or project video.
  /// Used by `ProjectPageFetcher` to run an optimized project page fetch.
  func fastFetchProjectPageBase(projectParam: Param)
    -> SignalProducer<Project, ErrorEnvelope>

  /// Fetch the newest data for a particular project from its id or slug. Includes extended project properties.
  /// Used by `ProjectPageFetcher` to run an optimized project page fetch.
  func fastFetchProjectPageExtendedProperties(projectParam: Param, includeStoryRichText: Bool)
    -> SignalProducer<ProjectPageExtraProperties, ErrorEnvelope>

  /// Fetch the newest data for a particular project from its id or slug, including an optional backing id if current user is backing project
  /// (currently only used on `ProjectPamphetViewModel`and `ProjectPageViewModel`  because it's a GQL query)
  func fetchProject(projectParam: Param, includeStoryRichText: Bool)
    -> SignalProducer<Project.ProjectPamphletData, ErrorEnvelope>

  /// Fetch the project's rewards and pledge over time data
  func fetchProjectRewardsAndPledgeOverTimeData(projectId: Int)
    -> SignalProducer<RewardsAndPledgeOverTimeEnvelope, ErrorEnvelope>

  /// Fetch the project's rewards only, without shipping rules
  func fetchProjectRewards(projectId: Int) -> SignalProducer<[Reward], ErrorEnvelope>

  /// Fetch the project's rewards, including 'No Reward'. Includes all shipping rules.
  /// Uses the included `NoRewardInserter` to decide where 'No Reward' should live in the list.
  func fetchProjectRewards(
    projectId: Int,
    sortedForShippingCountryCode: String?,
    withNoReward: NoRewardInserter
  )
    -> SignalProducer<[Reward], ErrorEnvelope>

  /// Fetch a single project with the specified discovery params.
  func fetchProject(_ params: DiscoveryParams) -> SignalProducer<DiscoveryEnvelope, ErrorEnvelope>

  /// Fetch the newest data for a particular project from its project value.
  func fetchProject_combine(project: Project) -> AnyPublisher<Project, ErrorEnvelope>

  /// Fetch a page of activities for a project.
  func fetchProjectActivities(forProject project: Project) ->
    SignalProducer<ProjectActivityEnvelope, ErrorEnvelope>

  /// Fetch a page of activities for a project from a pagination url.
  func fetchProjectActivities(paginationUrl: String) ->
    SignalProducer<ProjectActivityEnvelope, ErrorEnvelope>

  /// Fetch the user's project notifications.
  func fetchProjectNotifications() -> SignalProducer<[ProjectNotification], ErrorEnvelope>

  /// Fetches the projects that the current user is a member of.
  func fetchProjects(member: Bool) -> SignalProducer<ProjectsEnvelope, ErrorEnvelope>

  /// Fetches more projects from a pagination URL.
  func fetchProjects(paginationUrl: String) -> SignalProducer<ProjectsEnvelope, ErrorEnvelope>

  /// Fetches the stats for a particular project.
  func fetchProjectStats(projectId: Int) -> SignalProducer<ProjectStatsEnvelope, ErrorEnvelope>

  /// Fetch the add-on rewards for the add-on selection view with a `Project` slug and optional `Location` ID.
  @MainActor func rewardAddOns(slug: String, locationID: String?) async throws -> [Reward]?
  @MainActor func fastRewardAddOns(baseRewardID: Int, country: String) async throws -> [Reward]

  func fetchRewardAddOnsSelectionViewRewards(slug: String, shippingEnabled: Bool, locationId: String?)
    -> SignalProducer<Project, ErrorEnvelope>

  func fastFetchRewardAddOnsSelection(
    baseRewardId: Int,
    countryCode: String
  ) -> SignalProducer<[Reward], ErrorEnvelope>

  /// Fetches a reward's shipping rules for a project and reward id.
  func fetchRewardShippingRules(projectId: Int, rewardId: Int)
    -> SignalProducer<ShippingRulesEnvelope, ErrorEnvelope>

  /// Fetches a survey response belonging to the current user.
  func fetchSurveyResponse(surveyResponseId: Int)
    -> SignalProducer<SurveyResponse, ErrorEnvelope>

  /// Fetches all of the user's unanswered surveys.
  func fetchUnansweredSurveyResponses() -> SignalProducer<[SurveyResponse], ErrorEnvelope>

  /// Fetches an update from its id and project.
  func fetchUpdate(updateId: Int, projectParam: Param) -> SignalProducer<Update, ErrorEnvelope>

  /// Fetches a project update draft.
  @MainActor func creatorDraft(project: Project) async throws -> UpdateDraft
  @MainActor func saveCreatorDraft(_ draft: UpdateDraft, title: String, body: String, isPublic: Bool) async throws -> UpdateDraft
  @MainActor func addCreatorDraftImage(file: URL, draft: UpdateDraft) async throws -> UpdateDraft.Image
  @MainActor func removeCreatorDraftImage(_ image: UpdateDraft.Image, draft: UpdateDraft) async throws -> UpdateDraft.Image
  func fetchUpdateDraft(forProject project: Project) -> SignalProducer<UpdateDraft, ErrorEnvelope>

  /// Fetch the newest data for a particular user.
  func fetchUser(_ user: User) -> SignalProducer<User, ErrorEnvelope>

  /// Fetch a user.
  func fetchUser(userId: Int) -> SignalProducer<User, ErrorEnvelope>

  /// Fetch the logged-in user's data.
  func fetchUserSelf() -> SignalProducer<User, ErrorEnvelope>

  /// Fetch the logged-in user's data.
  func fetchUserSelf_combine(withOAuthToken: String) -> AnyPublisher<User, ErrorEnvelope>

  /// Mark reward received.
  func backingUpdate(forProject project: Project, forUser user: User, received: Bool)
    -> SignalProducer<Backing, ErrorEnvelope>

  /// Mark reward as received or unreceived. Return Bool is true if success.
  func updateRewardReceived(backingId: String, rewardReceived: Bool)
    -> AnyPublisher<Bool, ErrorEnvelope>

  /// Follow all friends of current user.
  func followAllFriends() -> SignalProducer<VoidEnvelope, ErrorEnvelope>

  /// Follow a user with their id.
  func followFriend(userId id: Int) -> SignalProducer<User, ErrorEnvelope>

  /// Increment the video complete stat for a project.
  func incrementVideoCompletion(for project: any HasProjectWebURL)
    -> SignalProducer<VoidEnvelope, ErrorEnvelope>

  /// Increment the video start stat for a project.
  func incrementVideoStart(forProject project: any HasProjectWebURL)
    -> SignalProducer<VoidEnvelope, ErrorEnvelope>

  /// Attempt a login with an email, password and optional code.
  func login(email: String, password: String, code: String?) ->
    SignalProducer<AccessTokenEnvelope, ErrorEnvelope>

  /// Attempt a login with Facebook access token and optional code.
  func login(facebookAccessToken: String, code: String?) ->
    SignalProducer<AccessTokenEnvelope, ErrorEnvelope>

  /// Marks all the messages in a particular thread as read.
  func markAsRead(messageThread: MessageThread) -> SignalProducer<MessageThread, ErrorEnvelope>

  /// Posts a comment to a project or replies in a thread
  func postComment(input: PostCommentInput)
    -> SignalProducer<Comment, ErrorEnvelope>

  /// Returns a project update preview URL.
  func previewUrl(forDraft draft: UpdateDraft) -> URL?

  /// Publishes a project update draft.
  func publish(draft: UpdateDraft) -> SignalProducer<Update, ErrorEnvelope>

  /// Registers a push token.
  func register(pushToken: String) -> SignalProducer<VoidEnvelope, ErrorEnvelope>

  /// Reset user password with email address.
  func resetPassword(email: String) -> SignalProducer<User, ErrorEnvelope>

  /// Searches all of the messages, (optionally) bucketed to a specific project.
  func searchMessages(query: String, project: Project?)
    -> SignalProducer<MessageThreadsEnvelope, ErrorEnvelope>

  /// Sends a message to a subject, i.e. creator project, message thread, backer of backing.
  func sendMessage(body: String, toSubject subject: MessageSubject)
    -> SignalProducer<Message, ErrorEnvelope>

  /// Sends a verification email (after updating the email from account settings).
  func sendVerificationEmail(input: EmptyInput)
    -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope>

  /// Signin with Apple
  func signInWithApple(input: SignInWithAppleInput)
    -> SignalProducer<SignInWithAppleEnvelope, ErrorEnvelope>

  /// Signup with Facebook access token and newsletter bool.
  func signup(facebookAccessToken: String, sendNewsletters: Bool) ->
    SignalProducer<AccessTokenEnvelope, ErrorEnvelope>

  /// Unfollow a user with their id.
  func unfollowFriend(userId id: Int) -> SignalProducer<VoidEnvelope, ErrorEnvelope>

  /// Updates a backing
  func updateBacking(input: UpdateBackingInput) -> SignalProducer<UpdateBackingEnvelope, ErrorEnvelope>

  /// Update the project notification setting.
  func updateProjectNotification(_ notification: ProjectNotification)
    -> SignalProducer<ProjectNotification, ErrorEnvelope>

  /// Update the current user with settings attributes.
  func updateUserSelf(_ user: User) -> SignalProducer<User, ErrorEnvelope>

  /// Updates the draft of a project update.
  func update(draft: UpdateDraft, title: String, body: String, isPublic: Bool)
    -> SignalProducer<UpdateDraft, ErrorEnvelope>

  /// Unwatches a project.
  func unwatchProject(input: WatchProjectInput) ->
    SignalProducer<WatchProjectResponseEnvelope, ErrorEnvelope>

  /// Validates a Post Campaign Pledge
  func validateCheckout(
    checkoutId: String,
    paymentSourceId: String,
    paymentIntentClientSecret: String
  ) -> SignalProducer<ValidateCheckoutEnvelope, ErrorEnvelope>

  /// Verifies an email address with a given access token.
  func verifyEmail(withToken token: String)
    -> SignalProducer<EmailVerificationResponseEnvelope, ErrorEnvelope>

  /// Watches (also known as favoriting) a project.
  func watchProject(input: WatchProjectInput) ->
    SignalProducer<WatchProjectResponseEnvelope, ErrorEnvelope>

  func fetchSavedProjects(cursor: String?, limit: Int?)
    -> SignalProducer<GraphAPI.FetchMySavedProjectsQuery.Data, ErrorEnvelope>

  func fetchBackedProjects(cursor: String?, limit: Int?)
    -> SignalProducer<GraphAPI.FetchMyBackedProjectsQuery.Data, ErrorEnvelope>

  func blockUser(input: BlockUserInput) -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope>

  func fetchDiscovery_combine(paginationUrl: String)
    -> AnyPublisher<DiscoveryEnvelope, ErrorEnvelope>

  func fetchDiscovery_combine(params: DiscoveryParams)
    -> AnyPublisher<DiscoveryEnvelope, ErrorEnvelope>

  func exchangeTokenForOAuthToken(params: OAuthTokenExchangeParams)
    -> AnyPublisher<OAuthTokenExchangeResponse, ErrorEnvelope>

  /// Confirms a backer's address for a given backing. Returns a success boolean.
  func confirmBackingAddress(backingId: String, addressId: String) -> AnyPublisher<Bool, ErrorEnvelope>

  /// Fetch data for the pledged projects overview.
  func fetchPledgedProjects(
    tierTypes: [PledgeProjectsOverviewSort],
    cursor: String?,
    limit: Int?
  ) -> AnyPublisher<GraphAPI.FetchPledgedProjectsQuery.Data, ErrorEnvelope>
}

extension ServiceType {
  /// Returns `true` if an oauth token is present, and `false` otherwise.
  public var isAuthenticated: Bool {
    return self.oauthToken != nil
  }
}

public func == (lhs: ServiceType, rhs: ServiceType) -> Bool {
  return
    type(of: lhs) == type(of: rhs) &&
    lhs.serverConfig == rhs.serverConfig &&
    lhs.oauthToken == rhs.oauthToken &&
    lhs.language == rhs.language &&
    lhs.buildVersion == rhs.buildVersion
}

public func != (lhs: ServiceType, rhs: ServiceType) -> Bool {
  return !(lhs == rhs)
}

extension ServiceType {
  /**
   Prepares a URL request to be sent to the server.

   - parameter originalRequest: The request that should be prepared.
   - parameter query:           Additional query params that should be attached to the request.

   - returns: A new URL request that is properly configured for the server.
   */
  public func preparedRequest(forRequest originalRequest: URLRequest, query: [String: Any] = [:])
    -> URLRequest {
    var request = originalRequest
    guard let URL = request.url else {
      return originalRequest
    }

    var headers = self.defaultHeaders

    let method = request.httpMethod?.uppercased()
    var components = URLComponents(url: URL, resolvingAgainstBaseURL: false)!
    var queryItems = components.queryItems ?? []
    queryItems.append(contentsOf: self.defaultQueryParams.map(URLQueryItem.init(name:value:)))

    if method == .some("POST") || method == .some("PUT") {
      if request.httpBody == nil {
        headers["Content-Type"] = "application/json; charset=utf-8"
        request.httpBody = try? JSONSerialization.data(withJSONObject: query, options: [])
      }
    } else {
      queryItems.append(
        contentsOf: query
          .flatMap(self.queryComponents)
          .map(URLQueryItem.init(name:value:))
      )
    }
    components.queryItems = queryItems.sorted { $0.name < $1.name }
    request.url = components.url

    let currentHeaders = request.allHTTPHeaderFields ?? [:]
    request.allHTTPHeaderFields = currentHeaders.withAllValuesFrom(headers)

    return request
  }

  /**
   Prepares a request to be sent to the server.

   - parameter URL:    The URL to turn into a request and prepare.
   - parameter method: The HTTP verb to use for the request.
   - parameter query:  Additional query params that should be attached to the request.

   - returns: A new URL request that is properly configured for the server.
   */
  public func preparedRequest(forURL url: URL, method: Method = .GET, query: [String: Any] = [:])
    -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue
    return self.preparedRequest(forRequest: request, query: query)
  }

  /**
     Prepares a URL request to be sent to the server.
     - parameter originalRequest: The request that should be prepared
     - parameter queryString: The GraphQL mutation string description
     - parameter input: The input for the mutation

     - returns: A new URL request that is properly configured for the server
   **/
  public func preparedGraphRequest(
    forURL url: URL,
    queryString: String,
    input: [String: Any]
  ) throws -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = Method.POST.rawValue

    guard let URL = request.url else {
      return request
    }

    let requestBody = self.graphMutationRequestBody(mutation: queryString, input: input)
    let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])

    request.httpBody = jsonData

    var headers = self.defaultHeaders
    headers["Content-Type"] = "application/json; charset=utf-8"

    let components = URLComponents(url: URL, resolvingAgainstBaseURL: false)!
    request.url = components.url
    request.allHTTPHeaderFields = headers

    return request
  }

  public func isPrepared(request: URLRequest) -> Bool {
    return request.value(forHTTPHeaderField: "Authorization") == self.authorizationHeader
      && request.value(forHTTPHeaderField: "Kickstarter-iOS-App") != nil
  }

  public func addV1AuthenticationToRequest(_ request: inout URLRequest, oauthToken: String) {
    var headers = request.allHTTPHeaderFields ?? [:]
    headers["X-Auth"] = "token \(oauthToken)"
    request.allHTTPHeaderFields = headers
  }

  internal var defaultHeaders: [String: String] {
    var headers: [String: String] = [:]
    headers["Accept-Language"] = self.language
    headers["Kickstarter-App-Id"] = self.appId
    headers["Kickstarter-iOS-App"] = self.buildVersion
    headers["User-Agent"] = Self.userAgent
    headers["X-KICKSTARTER-CLIENT"] = self.serverConfig.apiClientAuth.clientId
    headers["Kickstarter-iOS-App-UUID"] = self.deviceIdentifier

    /*
     GraphQL - Reads OAuth token from Authorization header
     GraphQL - Ignores X-Auth header
     V1 - Reads basic auth from Authorization header
     V1 - Reads OAuth token from X-Auth header or (deprecated) from oauth_token parameter
     */

    headers["Authorization"] = self.authorizationHeader
    if let oAuthHeader = self.oAuthAuthorizationHeader {
      headers["X-Auth"] = oAuthHeader
    }

    return headers
  }

  func graphMutationRequestBody(mutation: String, input: [String: Any]) -> [String: Any] {
    return [
      "query": mutation,
      "variables": ["input": input]
    ]
  }

  public static var userAgent: String {
    let executable = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String
    let bundleIdentifier = Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String
    let app: String = executable ?? bundleIdentifier ?? "Kickstarter"
    let bundleVersion: String = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    let model = UIDevice.current.model
    let systemVersion = UIDevice.current.systemVersion
    let scale = UIScreen.main.scale

    return "\(app)/\(bundleVersion) (\(model); iOS \(systemVersion) Scale/\(scale))"
  }

  private var oAuthAuthorizationHeader: String? {
    guard let token = self.oauthToken?.token else {
      return nil
    }

    return "token \(token)"
  }

  private var authorizationHeader: String? {
    if let header = oAuthAuthorizationHeader {
      return header
    } else {
      return self.serverConfig.basicHTTPAuth?.authorizationHeader
    }
  }

  private var defaultQueryParams: [String: String] {
    var query: [String: String] = [:]
    query["client_id"] = self.serverConfig.apiClientAuth.clientId
    query["currency"] = self.currency
    return query
  }

  private func queryComponents(_ key: String, _ value: Any) -> [(String, String)] {
    var components: [(String, String)] = []

    if let dictionary = value as? [String: Any] {
      for (nestedKey, value) in dictionary {
        components += self.queryComponents("\(key)[\(nestedKey)]", value)
      }
    } else if let array = value as? [Any] {
      for value in array {
        components += self.queryComponents("\(key)[]", value)
      }
    } else {
      components.append((key, String(describing: value)))
    }

    return components
  }
}
