@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class ActivitiesViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let sessionFeature =
    SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) })
  private lazy var feature = ActivityFeature(
    sessionFeature: self.sessionFeature,
    makeProvider: { AsyncActivityProvider(service: AppEnvironment.current.apiService) },
    sleep: { _ in }
  )
  private lazy var vm = ActivitiesViewModel(activityFeature: self.feature)
  private func advanceRequests() async {
    await self.vm.pageTask?.value
    await self.vm.surveyTask?.value
    await self.vm.userTask?.value
    await self.vm.badgeTask?.value
  }

  override func tearDown() async throws {
    await self.advanceRequests()
    try await super.tearDown()
  }

  fileprivate let activities = ActivityRecorder<[Activity]>()
  fileprivate let activitiesPresent = ActivityRecorder<Bool>()
  fileprivate let clearBadgeValue = ActivityRecorder<()>()
  fileprivate let erroredBackings = ActivityRecorder<[ProjectAndBackingEnvelope]>()
  fileprivate let isRefreshing = ActivityRecorder<Bool>()
  fileprivate let goToProject = ActivityRecorder<Project>()
  fileprivate let goToSurveyResponse = ActivityRecorder<SurveyResponse>()
  fileprivate let showRefTag = ActivityRecorder<RefTag>()
  fileprivate let deleteFacebookConnectSection = ActivityRecorder<()>()
  fileprivate let deleteFindFriendsSection = ActivityRecorder<()>()
  fileprivate let hideEmptyState = ActivityRecorder<()>()
  fileprivate let goToFriends = ActivityRecorder<FriendsSource>()
  fileprivate let goToManagePledgeProjectParam = ActivityRecorder<Param>()
  fileprivate let goToManagePledgeBackingParam = ActivityRecorder<Param?>()
  fileprivate let showEmptyStateIsLoggedIn = ActivityRecorder<Bool>()
  fileprivate let showFacebookConnectSection = ActivityRecorder<Bool>()
  fileprivate let showFacebookConnectSectionSource = ActivityRecorder<FriendsSource>()
  fileprivate let showFindFriendsSection = ActivityRecorder<Bool>()
  fileprivate let showFindFriendsSectionSource = ActivityRecorder<FriendsSource>()
  fileprivate let showFacebookConnectErrorAlert = ActivityRecorder<AlertError>()
  fileprivate let unansweredSurveyResponse = ActivityRecorder<[SurveyResponse]>()
  fileprivate let updateUserInEnvironment = ActivityRecorder<User>()

  override func setUp() async throws {
    try await super.setUp()

    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .activities(activities): self.activities.record(activities); self.activitiesPresent.record(!activities.isEmpty)
      case .clearBadgeValue: self.clearBadgeValue.record(())
      case let .erroredBackings(backings): self.erroredBackings.record(backings)
      case .hideEmptyState: self.hideEmptyState.record(())
      case let .isRefreshing(value): self.isRefreshing.record(value)
      case let .goToProject(project, refTag): self.goToProject.record(project); self.showRefTag.record(refTag)
      case let .goToSurveyResponse(survey): self.goToSurveyResponse.record(survey)
      case let .goToManagePledge(params):
        self.goToManagePledgeProjectParam.record(params.projectParam)
        self.goToManagePledgeBackingParam.record(params.backingParam)
      case let .showEmptyStateIsLoggedIn(value): self.showEmptyStateIsLoggedIn.record(value)
      case let .unansweredSurveys(surveys): self.unansweredSurveyResponse.record(surveys)
      case let .updateUserInEnvironment(user): self.updateUserInEnvironment.record(user)
      case .goToUpdate: break
      }
    }
  }

  // Tests the flow of logging in with a user that has activities.
  func testLoginFlow_ForUserWithActivities() async {
    self.vm.viewDidLoad()
    self.vm.viewWillAppear(animated: false)

    self.activitiesPresent.assertValues([], "No activities shown for logged-out user.")
    self.showEmptyStateIsLoggedIn.assertValues([false], "Logged-out empty state emits.")

    self.vm.viewWillAppear(animated: false)

    self.activitiesPresent.assertValues([], "No activities shown for logged-out user.")
    self.showEmptyStateIsLoggedIn.assertValues([false], "Logged-out empty state does not emit again.")
    self.hideEmptyState.assertValueCount(1, "Dismiss empty state emits.")

    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: User.template))
    await withEnvironment(apiService: MockService(fetchActivitiesResponse: [
      self.activity1,
      self.activity2
    ])) {
      self.vm.userSessionStarted()
      self.vm.viewWillAppear(animated: false)

      await self.advanceRequests()

      self.activitiesPresent.assertValues([true], "Activities load after session starts and view appears.")
      self.showEmptyStateIsLoggedIn.assertValues([false], "Empty state does not emit.")
      self.hideEmptyState.assertValueCount(2, "Dismiss empty state emits.")

      self.vm.viewWillAppear(animated: false)

      self.activitiesPresent.assertValues([true], "Same activities do not emit again.")
      self.showEmptyStateIsLoggedIn.assertValues([false], "Empty state does not emit.")
      self.hideEmptyState.assertValueCount(2, "Dismiss empty state does not emit.")
    }

    AppEnvironment.logout()
    self.vm.userSessionEnded()

    self.activitiesPresent.assertValues([true, false], "Activities are cleared.")
    self.showEmptyStateIsLoggedIn.assertValues([false], "Empty logged-in state does not emit.")
    self.hideEmptyState.assertValueCount(2, "Dismiss empty state does not emit.")

    self.vm.viewWillAppear(animated: false)

    self.activitiesPresent.assertValues([true, false], "Activities are still cleared.")
    self.showEmptyStateIsLoggedIn.assertValues([false, false], "Logged-out empty state emits again.")
    self.hideEmptyState.assertValueCount(2, "Dismiss empty state does not emit.")

    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeefffffff", user: User.brando))
    await withEnvironment(apiService: MockService(fetchActivitiesResponse: [])) {
      self.vm.userSessionStarted()
      self.vm.viewWillAppear(animated: false)

      await self.advanceRequests()

      self.activitiesPresent.assertValues([true, false, false], "Emits empty activities.")
      self.showEmptyStateIsLoggedIn.assertValues([false, false, true], "Logged-in empty state emits.")
      self.hideEmptyState.assertValueCount(2, "Dismiss empty state does not emit.")
    }
  }

  // Tests the flow of logging in with a user that has no activities and making sure the correct
  // empty state shows.
  func testLoginFlow_ForUserWithNoActivities() async {
    await withEnvironment(apiService: MockService(fetchActivitiesResponse: [])) {
      self.vm.viewDidLoad()
      self.vm.viewWillAppear(animated: false)
      await self.advanceRequests()

      self.activitiesPresent.assertValues([], "Activities didn't emit.")
      self.showEmptyStateIsLoggedIn.assertValues([false], "Logged out empty state emits.")

      AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: User.template))
      self.vm.userSessionStarted()
      self.vm.viewWillAppear(animated: false)

      await self.advanceRequests()

      self.activitiesPresent.assertValues([false], "Activities emit an empty array.")
      // NB: Technically, it is correct that the logged-in empty state should emit here.
      // However, it would be better if the logged-out empty state could have dismissed first.
      // For now, the view controller won't present another empty state if this modal exists already.
      self.showEmptyStateIsLoggedIn.assertValues([false, true], "Logged in empty state emits.")
      self.hideEmptyState.assertValueCount(1, "Dismiss empty state emits on view load.")

      self.vm.viewWillAppear(animated: false)

      self.activitiesPresent.assertValues([false], "Activities does not emit.")
      self.showEmptyStateIsLoggedIn.assertValues([false, true], "Logged in empty state does not emit again.")
      self.hideEmptyState.assertValueCount(1, "Dismiss empty state does not emit.")
    }
  }

  // Tests that activities are cleared if the user is logged out for any reason.
  func testInvalidatedTokenFlow_ActivitiesClearAfterSessionCleared() async {
    self.vm.viewDidLoad()

    self.hideEmptyState.assertValueCount(1, "Dismiss empty state emits.")

    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: User.template))
    self.vm.userSessionStarted()
    self.vm.viewWillAppear(animated: false)

    await self.advanceRequests()

    self.activitiesPresent.assertValues([true], "Activities show right away.")
    self.showEmptyStateIsLoggedIn.assertValueCount(0, "Empty state does not emit.")
    self.hideEmptyState.assertValueCount(2, "Dismiss empty state emits.")

    AppEnvironment.logout()
    self.vm.userSessionEnded()

    self.showEmptyStateIsLoggedIn.assertValueCount(0, "Empty state does not emit.")

    self.vm.viewWillAppear(animated: false)

    await self.advanceRequests()

    self.activitiesPresent.assertValues([true, false], "Activities clear right away.")
    self.showEmptyStateIsLoggedIn.assertValues([false], "Logged out empty state emits.")
    self.hideEmptyState.assertValueCount(2, "Dismiss empty state does not emit.")

    self.vm.viewWillAppear(animated: false)

    self.activitiesPresent.assertValues([true, false], "Activities does not emit again.")
    self.showEmptyStateIsLoggedIn.assertValues([false], "Logged out empty state does not emit again.")
    self.hideEmptyState.assertValueCount(2, "Dismiss empty state does not emit.")
  }

  // Tests the flow:
  //   * user logs in before ever view activities
  //   * user navigates to activities
  func testLogin_BeforeActivityViewAppeared() async {
    self.vm.viewDidLoad()

    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: User.template))
    self.vm.userSessionStarted()
    await self.advanceRequests()

    self.activitiesPresent.assertValues([], "Activities don't load after session starts.")

    self.vm.viewWillAppear(animated: false)

    self.activitiesPresent.assertValues([true], "Activities load once view appears.")
  }

  func testLogoutBeforeFirstAppearanceDoesNotShowBufferedActivities() async {
    await withEnvironment(apiService: MockService(fetchActivitiesResponse: [self.activity1])) {
      self.vm.viewDidLoad()
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture", user: .template))
      self.vm.userSessionStarted()
      await self.advanceRequests()
      AppEnvironment.logout()
      self.vm.userSessionEnded()
      self.vm.viewWillAppear(animated: false)
      self.activitiesPresent.assertValues([false])
      self.showEmptyStateIsLoggedIn.assertValues([false])
    }
  }

  func testRefreshActivities() async {
    await withEnvironment(
      apiService: MockService(fetchActivitiesResponse: [self.activity1, self.activity2]),
      currentUser: .template
    ) {
      self.vm.viewDidLoad()
      self.vm.userSessionStarted()
      self.vm.viewWillAppear(animated: false)
      await self.advanceRequests()

      self.activitiesPresent.assertValues([true], "Activities load immediately after session starts.")

      self.vm.willDisplayRow(9, outOf: 10)
      await self.advanceRequests()

      self.activitiesPresent.assertValues([true, true], "New activities emit on pagination.")

      // New fetchActivitiesResponse
      await withEnvironment(apiService: MockService(fetchActivitiesResponse: [
        self.activity1,
        self.activity2,
        self.activity3
      ])) {
        self.vm.refresh()
        await self.advanceRequests()

        self.activitiesPresent.assertValues([true, true, true], "New activities emit on refresh.")
      }
    }
  }

  func testShippedActivities() async {
    await withEnvironment(
      apiService: MockService(fetchActivitiesResponse: [
        self.activity1,
        self.activity2,
        self.shippedActivity
      ]),
      currentUser: .template
    ) {
      self.vm.viewDidLoad()
      self.vm.userSessionStarted()
      self.vm.viewWillAppear(animated: false)
      await self.advanceRequests()

      self.activitiesPresent.assertValues([true], "Activities loaded.")
      self.activities.assertValues([[self.shippedActivity, self.activity2, self.activity1]])
    }
  }

  func testClearBadgeValueOnRefreshActivities() async {
    self.updateUserInEnvironment.assertValues([])
    self.clearBadgeValue.assertValueCount(0)

    let mockService1 = MockService(
      clearUserUnseenActivityResult: Result.success(.init(activityIndicatorCount: 0)),
      fetchActivitiesResponse: [self.activity1, self.activity2]
    )

    let mockService2 = MockService(
      clearUserUnseenActivityResult: Result.success(.init(activityIndicatorCount: 0)),
      fetchActivitiesResponse: [self.activity1, self.activity2, self.activity3]
    )

    let user = User.template
      |> User.lens.unseenActivityCount .~ 100

    await withEnvironment(
      apiService: mockService1,
      currentUser: user
    ) {
      self.vm.viewDidLoad()
      self.vm.userSessionStarted()
      self.vm.viewWillAppear(animated: false)
      await self.advanceRequests()

      self.updateUserInEnvironment.assertValues([])
      self.activitiesPresent.assertValues([true], "Activities load immediately after session starts.")
      self.clearBadgeValue.assertValueCount(0)

      await withEnvironment(apiService: mockService2) {
        self.vm.refresh()
        await self.advanceRequests()

        self.activitiesPresent.assertValues([true, true], "New activities emit on refresh.")
        self.clearBadgeValue.assertValueCount(1)
        XCTAssertEqual(self.updateUserInEnvironment.values.map { $0.id }, [user.id])

        await self.advanceRequests()

        XCTAssertEqual(self.updateUserInEnvironment.values.map { $0.id }, [user.id])
      }
    }
  }

  func testClearBadgeValueOnRefreshActivities_LoggedOut() async {
    self.updateUserInEnvironment.assertValues([])
    self.clearBadgeValue.assertValueCount(0)

    let mockService1 = MockService(
      clearUserUnseenActivityResult: Result.success(.init(activityIndicatorCount: 0)),
      fetchActivitiesResponse: [self.activity1, self.activity2]
    )

    let mockService2 = MockService(
      clearUserUnseenActivityResult: Result.success(.init(activityIndicatorCount: 0)),
      fetchActivitiesResponse: [self.activity1, self.activity2, self.activity3]
    )

    await withEnvironment(
      apiService: mockService1
    ) {
      self.vm.viewDidLoad()
      self.vm.userSessionStarted()
      self.vm.viewWillAppear(animated: false)
      await self.advanceRequests()

      self.updateUserInEnvironment.assertValues([])
      self.activitiesPresent.assertValues([])
      self.clearBadgeValue.assertValueCount(0)

      await withEnvironment(apiService: mockService2) {
        self.vm.refresh()
        await self.advanceRequests()

        self.activitiesPresent.assertValues([])
        self.clearBadgeValue.assertValueCount(0)
        self.updateUserInEnvironment.assertValues([])

        await self.advanceRequests()

        self.updateUserInEnvironment.assertValues([])
      }
    }
  }

  func testGoToProject() async {
    let activity = .template |> Activity.lens.category .~ .backing
    let project = activity.project!
    let refTag = RefTag.activity

    self.vm.activityUpdateCellTappedProjectImage(activity: activity)

    self.goToProject.assertValues([project])
    self.showRefTag.assertValues([refTag])

    XCTAssertEqual(self.segmentTrackingClient.events, ["CTA Clicked"])

    XCTAssertEqual(
      ["activity_feed"],
      self.segmentTrackingClient.properties(forKey: "context_page", as: String.self)
    )
  }

  func testSurveys() async {
    let surveyResponse = SurveyResponse.template

    self.vm.viewDidLoad()
    self.vm.viewWillAppear(animated: false)
    await self.advanceRequests()

    self.unansweredSurveyResponse.assertValueCount(0, "Survey does not emit when logged out.")

    await withEnvironment(
      apiService: MockService(fetchUnansweredSurveyResponsesResponse: [surveyResponse]),
      currentUser: .template
    ) {
      self.vm.userSessionStarted()
      self.vm.viewWillAppear(animated: false)
      await self.advanceRequests()

      self.unansweredSurveyResponse.assertValues([[surveyResponse]])

      // Tap to see survey response.
      self.vm.tappedRespondNow(forSurveyResponse: surveyResponse)
      self.goToSurveyResponse.assertValues([surveyResponse])

      // Exited survey full screen.
      self.vm.viewWillAppear(animated: true)
      await self.advanceRequests()
      self.unansweredSurveyResponse.assertValues(
        [[surveyResponse], [surveyResponse]],
        "Survey emits whenever view appears"
      )

      self.vm.tappedRespondNow(forSurveyResponse: surveyResponse)
      self.goToSurveyResponse.assertValues([surveyResponse, surveyResponse])

      // Exited survey modal.
      self.vm.surveyResponseViewControllerDismissed()
      await self.advanceRequests()
      self.unansweredSurveyResponse.assertValues(
        [[surveyResponse], [surveyResponse], [surveyResponse]],
        "Same unanswered survey emits."
      )
    }
  }

  func testGoToManagePledge() async {
    self.goToManagePledgeProjectParam.assertDidNotEmitValue()
    self.goToManagePledgeBackingParam.assertDidNotEmitValue()

    let env = ProjectAndBackingEnvelope.template
      |> \.project .~ .template

    self.vm.erroredBackingViewDidTapManage(with: env)

    self.goToManagePledgeProjectParam.assertValues([.id(env.project.id)])
    self.goToManagePledgeBackingParam.assertValues([.id(env.backing.id)])
  }

  func testUpdateUserInEnvironmentOnManagePledgeViewDidFinish_DidReturnUser() async {
    let user = User.template

    await withEnvironment(currentUser: user) {
      self.updateUserInEnvironment.assertDidNotEmitValue()
      self.erroredBackings.assertDidNotEmitValue()

      self.vm.managePledgeViewControllerDidFinish()

      await self.advanceRequests()

      self.updateUserInEnvironment.assertValues([user])
      self.erroredBackings.assertDidNotEmitValue()

      self.vm.currentUserUpdated()

      await self.advanceRequests()

      self.updateUserInEnvironment.assertValues([user])
      self.erroredBackings.assertValues([])
    }
  }

  func testUpdateUserInEnvironmentOnManagePledgeViewDidFinish_DidReturnUserAndNoErroredBackings() async {
    let user = User.template

    await withEnvironment(currentUser: user) {
      self.updateUserInEnvironment.assertDidNotEmitValue()
      self.erroredBackings.assertDidNotEmitValue()

      self.vm.managePledgeViewControllerDidFinish()

      await self.advanceRequests()

      self.updateUserInEnvironment.assertValues([user])
      self.erroredBackings.assertDidNotEmitValue()

      self.vm.currentUserUpdated()

      await self.advanceRequests()

      self.updateUserInEnvironment.assertValues([user])
      self.erroredBackings.assertValues([])
    }
  }

  func testSurvey_DoesntEmitAfterLogOut() async {
    let surveyResponse = SurveyResponse.template

    await withEnvironment(apiService: MockService(fetchUnansweredSurveyResponsesResponse: [surveyResponse])) {
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: .template))
      self.vm.viewDidLoad()
      self.vm.viewWillAppear(animated: false)
      await self.advanceRequests()

      self.unansweredSurveyResponse.assertValues([[surveyResponse]])

      AppEnvironment.logout()
      self.vm.userSessionEnded()
      self.vm.viewWillAppear(animated: false)
      await self.advanceRequests()

      self.unansweredSurveyResponse.assertValues([[surveyResponse]])
    }
  }

  fileprivate let activity1 = .template |> Activity.lens.id .~ 1
  fileprivate let activity2 = .template |> Activity.lens.id .~ 2
  fileprivate let activity3 = .template |> Activity.lens.id .~ 3
  fileprivate let shippedActivity = .template
    |> Activity.lens.id .~ 4
    |> Activity.lens.category .~ .shipped
    |> Activity.lens.trackingNumber .~ "test-tracking-number"
    |> Activity.lens.trackingUrl .~ "https://example.com"
}

fileprivate final class ActivityRecorder<Value> {
  private(set) var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    self.assertValueCount(0, message, file: file, line: line)
  }
}
fileprivate extension ActivityRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
