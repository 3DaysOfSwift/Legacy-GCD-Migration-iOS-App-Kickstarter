@testable import Kickstarter_iOS
import Prelude
import WebKit
import XCTest

@testable import KsApi


@MainActor
final class PledgeManagerWebViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = PledgeFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
    makeProvider: { AsyncPledgeProvider(service: AppEnvironment.current.apiService) })
  private lazy var vm: PledgeManagerWebViewModel = PledgeManagerWebViewModel(
    feature: self.feature)

  fileprivate let dismissViewController = PledgeWebRecorder<Void>()
  fileprivate let goToNativeScreen = PledgeWebRecorder<PledgeManagerNativeNatigationRequest>()
  fileprivate let presentUpdateVC = PledgeWebRecorder<(Project, Update)>()
  fileprivate let goToLoginSignup = PledgeWebRecorder<LoginIntent>()
  fileprivate let title = PledgeWebRecorder<String?>()
  fileprivate let webViewLoadRequestIsPrepared = PledgeWebRecorder<Bool>()
  fileprivate let webViewLoadRequest = PledgeWebRecorder<URLRequest>()

  override func setUp() async throws {
    try await super.setUp()
    MainActor.assumeIsolated {

      self.vm.onEvent = { [weak self] event in
        guard let self else { return }
        switch event {
        case .dismissViewController: self.dismissViewController.record(())
        case let .goToNativeScreen(request): self.goToNativeScreen.record(request)
        case let .presentUpdateVC(project, update): self.presentUpdateVC.record((project, update))
        case let .goToLoginSignup(intent): self.goToLoginSignup.record(intent)
        case let .title(title): self.title.record(title)
        case let .webViewLoadRequest(request):
          self.webViewLoadRequestIsPrepared.record(AppEnvironment.current.apiService.isPrepared(request: request))
          self.webViewLoadRequest.record(request)
        }
      }

      AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: .template))
    }
  }

  func testDismissViewControllerOnCloseButtonTapped() {
    self.vm.configureWith(url: SurveyResponse.template.urls.web.survey)
    self.vm.viewDidLoad()
    self.dismissViewController.assertDidNotEmitValue()

    self.vm.closeButtonTapped()
    self.dismissViewController.assertValueCount(1)
  }

  func testRespondToSurvey() {
    let project = Project.template
    let surveyResponse =
      .template
      |> SurveyResponse.lens.id .~ 123
      |> SurveyResponse.lens.project .~ project

    self.vm.configureWith(url: surveyResponse.urls.web.survey)
    self.vm.viewDidLoad()

    // 1. Load survey.
    self.webViewLoadRequestIsPrepared.assertValues([true])
    self.webViewLoadRequest.assertValueCount(1)

    let surveyPreparedGetRequest = surveyRequest(project: project, prepared: true, method: .GET)

    let surveyPreparedGetRequestNavigationAction = WKNavigationActionData(
      navigationType: .other,
      request: surveyPreparedGetRequest,
      sourceFrame: WKFrameInfoData(mainFrame: true, request: surveyPreparedGetRequest),
      targetFrame: WKFrameInfoData(mainFrame: true, request: surveyPreparedGetRequest)
    )

    let surveyPreparedGetRequestPolicy = self.vm.decidePolicyFor(
      navigationAction: surveyPreparedGetRequestNavigationAction
    )

    XCTAssertEqual(WKNavigationActionPolicy.allow.rawValue, surveyPreparedGetRequestPolicy.rawValue)

    // 2. Submit unprepared survey with non-nil body.
    var surveyUnpreparedPostRequest = surveyRequest(
      project: project, prepared: false, method: .POST)
    surveyUnpreparedPostRequest.httpBody = "data=data".data(using: .utf8)

    let surveyUnpreparedPostRequestNavigationAction = WKNavigationActionData(
      navigationType: .formSubmitted,
      request: surveyUnpreparedPostRequest,
      sourceFrame: WKFrameInfoData(mainFrame: true, request: surveyUnpreparedPostRequest),
      targetFrame: WKFrameInfoData(mainFrame: true, request: surveyUnpreparedPostRequest)
    )

    let surveyUnpreparedPostRequestPolicy = self.vm.decidePolicyFor(
      navigationAction: surveyUnpreparedPostRequestNavigationAction
    )

    XCTAssertEqual(
      WKNavigationActionPolicy.cancel.rawValue, surveyUnpreparedPostRequestPolicy.rawValue,
      "Not prepared"
    )

    XCTAssertEqual(self.webViewLoadRequest.values.last?.httpBody, "data=data".data(using: .utf8))

    self.webViewLoadRequestIsPrepared.assertValues([true, true])
    self.webViewLoadRequest.assertValueCount(2)

    // 3. Redirect to completed responses.
    let surveyRedirectGetRequest = surveyRequest(project: project, prepared: true, method: .GET)

    let surveyRedirectGetRequestNavigationAction = WKNavigationActionData(
      navigationType: .other,
      request: surveyRedirectGetRequest,
      sourceFrame: WKFrameInfoData(mainFrame: true, request: surveyRedirectGetRequest),
      targetFrame: WKFrameInfoData(mainFrame: true, request: surveyRedirectGetRequest)
    )

    let surveyRedirectGetRequestPolicy = self.vm.decidePolicyFor(
      navigationAction: surveyRedirectGetRequestNavigationAction
    )

    XCTAssertEqual(
      WKNavigationActionPolicy.allow.rawValue, surveyRedirectGetRequestPolicy.rawValue,
      "Allow redirect to completed survey responses"
    )

    // 4. Tap close button, dismiss view controller.
    self.dismissViewController.assertDidNotEmitValue()

    self.vm.closeButtonTapped()
    self.dismissViewController.assertValueCount(1)
  }

  func testTitle() {
    let project = Project.template
    let basicBackingUrl = "\(project.urls.web.project)/backing/"

    let backingDetailsAction = navigationData(basicBackingUrl + "details")
    _ = self.vm.decidePolicyFor(navigationAction: backingDetailsAction)
    self.title.assertLastValue(nil)

    let redeemAction = navigationData(basicBackingUrl + "redeem")
    _ = self.vm.decidePolicyFor(navigationAction: redeemAction)
    self.title.assertLastValue("Pledge Manager")

    let pledgeManagementAction = navigationData(basicBackingUrl + "pledge_management")
    _ = self.vm.decidePolicyFor(navigationAction: pledgeManagementAction)
    self.title.assertLastValue(nil)

    let surveyAction = navigationData(basicBackingUrl + "survey_responses")
    _ = self.vm.decidePolicyFor(navigationAction: surveyAction)
    self.title.assertLastValue(nil)
  }

  // MARK: - Test links

  func testGoToPledge() {
    let project = Project.template
    let surveyResponse =
      .template
      |> SurveyResponse.lens.project .~ project

    self.vm.configureWith(url: surveyResponse.urls.web.survey)
    self.vm.viewDidLoad()

    self.goToNativeScreen.assertDidNotEmitValue()

    let request = URLRequest(url: URL(string: project.urls.web.project + "/pledge/edit")!)
    let navigationAction = WKNavigationActionData(
      navigationType: .linkActivated,
      request: request,
      sourceFrame: WKFrameInfoData(mainFrame: true, request: request),
      targetFrame: WKFrameInfoData(mainFrame: true, request: request)
    )

    let policy = self.vm.decidePolicyFor(navigationAction: navigationAction)
    XCTAssertEqual(WKNavigationActionPolicy.cancel.rawValue, policy.rawValue)

    self.dismissViewController.assertDidNotEmitValue()
    self.goToNativeScreen.assertLastValue(.goToPledge(param: .slug(project.slug)))
  }

  func testGoToProject() {
    let project = Project.template
    let surveyResponse =
      .template
      |> SurveyResponse.lens.project .~ project

    self.vm.configureWith(url: surveyResponse.urls.web.survey)
    self.vm.viewDidLoad()

    self.goToNativeScreen.assertDidNotEmitValue()

    let request = URLRequest(url: URL(string: project.urls.web.project)!)
    let navigationAction = WKNavigationActionData(
      navigationType: .linkActivated,
      request: request,
      sourceFrame: WKFrameInfoData(mainFrame: true, request: request),
      targetFrame: WKFrameInfoData(mainFrame: true, request: request)
    )

    let policy = self.vm.decidePolicyFor(navigationAction: navigationAction)

    XCTAssertEqual(WKNavigationActionPolicy.cancel.rawValue, policy.rawValue)

    self.dismissViewController.assertDidNotEmitValue()
    self.goToNativeScreen.assertLastValue(.goToProject(param: .slug(project.slug), refTag: nil))
  }

  func testGoToUpdate() async {
    let project = Project.template
    let surveyResponse =
      .template
      |> SurveyResponse.lens.project .~ project

    let update = Update.template

    self.vm.configureWith(url: surveyResponse.urls.web.survey)
    self.vm.viewDidLoad()

    await withEnvironment(
      apiService: MockService(
        fetchProjectResult: .success(project),
        fetchUpdateResponse: update
      )
    ) {
      self.presentUpdateVC.assertDidNotEmitValue()
      self.goToNativeScreen.assertDidNotEmitValue()

      let updateId = 1
      let request = URLRequest(url: URL(string: project.urls.web.project + "/posts/\(updateId)")!)
      let navigationAction = WKNavigationActionData(
        navigationType: .linkActivated,
        request: request,
        sourceFrame: WKFrameInfoData(mainFrame: true, request: request),
        targetFrame: WKFrameInfoData(mainFrame: true, request: request)
      )

      let policy = self.vm.decidePolicyFor(navigationAction: navigationAction)
      XCTAssertEqual(WKNavigationActionPolicy.cancel.rawValue, policy.rawValue)

      self.goToNativeScreen.assertLastValue(
        .goToUpdate(param: .slug(project.slug), updateId: updateId))

      self.vm.fetchUpdateVCData(param: .slug(project.slug), updateId: updateId)
      await self.vm.waitForUpdate()
      await self.feature.waitForOperations()

      self.dismissViewController.assertDidNotEmitValue()
      self.presentUpdateVC.assertValueCount(1)
      let (projectResult, updateResult) = self.presentUpdateVC.lastValue!
      XCTAssertEqual(project, projectResult, "Update project is wrong.")
      XCTAssertEqual(update, updateResult, " Update is wrong.")
    }
  }

  // MARK: - Test login

  func testGoToLoginSignup() {
    withEnvironment(currentUser: nil) {
      let surveyResponse = SurveyResponse.template

      self.vm.configureWith(url: surveyResponse.urls.web.survey)
      self.vm.viewDidLoad()

      self.goToLoginSignup.assertValue(.generic)
    }
  }

  func testLoginSuccess() {
    withEnvironment(currentUser: nil) {
      let surveyResponse = SurveyResponse.template

      self.vm.configureWith(url: surveyResponse.urls.web.survey)
      self.vm.viewDidLoad()

      // Request should not send when user is logged out.
      self.webViewLoadRequest.assertValueCount(0)

      self.vm.userSessionStarted()

      // Request should be sent as soon as user has logged in.
      self.webViewLoadRequest.assertValueCount(1)
    }
  }

  // MARK: - Decision policy tests

  func testDecisionPolicyBypass() {
    let mockConfigClient = MockRemoteConfigClient()
    mockConfigClient.features = [
      RemoteConfigFeature.bypassPledgeManagerDecisionPolicy.rawValue: true
    ]

    withEnvironment(remoteConfigClient: mockConfigClient) {
      let navigationData = navigationData("https://www.fake.com/unrecognized-url")
      XCTAssertEqual(
        self.vm.decidePolicyFor(navigationAction: navigationData),
        WKNavigationActionPolicy.allow
      )
    }
  }

  func testBadRequest() {
    let navigationData = navigationData("https://www.fake.com/bad-url")
    XCTAssertEqual(
      self.vm.decidePolicyFor(navigationAction: navigationData),
      WKNavigationActionPolicy.cancel
    )
  }

  func testBadStripeRequest() {
    let navigationData = navigationData("https://www.stripecdn.network")
    XCTAssertEqual(
      self.vm.decidePolicyFor(navigationAction: navigationData),
      WKNavigationActionPolicy.cancel
    )
  }

  func testStripeNetworkRequest() {
    let navigationData = navigationData("https://m.stripe.network/inner.html#url=fake")
    XCTAssertEqual(
      self.vm.decidePolicyFor(navigationAction: navigationData),
      WKNavigationActionPolicy.allow
    )
  }

  func testStripeElementRequest() {
    let navigationData = navigationData("https://js.stripe.com/v3/controller-fake.html")
    XCTAssertEqual(
      self.vm.decidePolicyFor(navigationAction: navigationData),
      WKNavigationActionPolicy.allow
    )
  }

  func testStripeCdnRequest() {
    let navigationData = navigationData("https://b.stripecdn.com/assets/v21.19/Captcha.html")
    XCTAssertEqual(
      self.vm.decidePolicyFor(navigationAction: navigationData),
      WKNavigationActionPolicy.allow
    )
  }
}

// MARK: - Helpers

private func navigationData(_ url: String) -> WKNavigationActionData {
  let request = URLRequest(url: URL.init(string: url)!)
  return WKNavigationActionData(
    navigationType: .other,
    request: request,
    sourceFrame: WKFrameInfoData(mainFrame: true, request: request),
    targetFrame: nil
  )
}

@MainActor
private func surveyRequest(project: Project, prepared: Bool, method: KsApi.Method) -> URLRequest {
  let url = "\(project.urls.web.project)/surveys/1"
  var request = URLRequest(url: URL(string: url)!)
  request.httpMethod = method.rawValue
  if prepared {
    return AppEnvironment.current.apiService.preparedRequest(forRequest: request)
  } else {
    return request
  }
}

fileprivate final class PledgeWebRecorder<Value> {
  private(set) var values: [Value] = []
  var lastValue: Value? { self.values.last }
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    self.assertValueCount(0, message, file: file, line: line)
  }
}
fileprivate extension PledgeWebRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
  func assertValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    self.assertValues([expected], message, file: file, line: line)
  }
  func assertLastValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.last, expected, message, file: file, line: line)
  }
}
