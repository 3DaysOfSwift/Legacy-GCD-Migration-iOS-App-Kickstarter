@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import WebKit
import XCTest

@MainActor
final class ProjectUpdatesViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  fileprivate let vm = ProjectUpdatesViewModel(feature: DiscussionFeature(sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }), makeProvider: {
    AsyncDiscussionProvider(service: AppEnvironment.current.apiService)
  }, sleep: { _ in try Task.checkCancellation() }))

  fileprivate let goToSafariBrowser = UpdatesRecorder<URL>()
  fileprivate let goToUpdateId = UpdatesRecorder<Int>()
  fileprivate let goToUpdateCommentId = UpdatesRecorder<Int>()
  fileprivate let isActivityIndicatorHidden = UpdatesRecorder<Bool>()
  fileprivate let makePhoneCall = UpdatesRecorder<URL>()
  fileprivate let showMailCompose = UpdatesRecorder<String>()
  fileprivate let showNoEmailError = UpdatesRecorder<UIAlertController>()
  fileprivate let webViewLoadRequest = UpdatesRecorder<URLRequest>()

  internal override func setUp() async throws {
    try await super.setUp()
    self.vm.onSafari = { self.goToSafariBrowser.values.append($0) }
    self.vm.onUpdate = { _, update in self.goToUpdateId.values.append(update.id) }
    self.vm.onComments = { self.goToUpdateCommentId.values.append($0.id) }
    self.vm.onActivityHidden = { self.isActivityIndicatorHidden.values.append($0) }
    self.vm.onPhone = { self.makePhoneCall.values.append($0) }
    self.vm.onMail = { self.showMailCompose.values.append($0) }
    self.vm.onNoEmail = { self.showNoEmailError.values.append($0) }
    self.vm.onLoadRequest = { self.webViewLoadRequest.values.append($0) }
  }

  func testGoToSafariBrowser() async {
    let project = Project.template
    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()

    let googleURL = URL(string: "http://www.google.com")!

    self.goToSafariBrowser.assertValues([])

    let navigationAction = self.navigationAction(with: googleURL)

    XCTAssertEqual(
      WKNavigationActionPolicy.cancel.rawValue,
      self.vm.decidePolicy(forNavigationAction: navigationAction).rawValue
    )

    self.goToSafariBrowser.assertValues([googleURL])
  }

  func testGoToUpdate() async {
    let project = Project.template
      |> (Project.lens.urls.web .. Project.UrlsEnvelope.WebEnvelope.lens.updates)
      .~ "https://www.kickstarter.com/projects/milk/duds/posts"

    let updateId = 11_235

    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()

    let navigationAction = self.navigationAction(
      with:
      URL(string: "\(project.urls.web.updates!)/\(updateId)")!
    )

    XCTAssertEqual(
      WKNavigationActionPolicy.cancel.rawValue,
      self.vm.decidePolicy(forNavigationAction: navigationAction).rawValue
    )

    await self.vm.waitForLoads()

    self.goToUpdateId.assertValues([updateId])

    self.isActivityIndicatorHidden.assertValues([])
    self.vm.webViewDidStartProvisionalNavigation()
    self.isActivityIndicatorHidden.assertValues([false])
    self.vm.webViewDidFinishNavigation()
    self.isActivityIndicatorHidden.assertValues([false, true])
  }

  func testGoToUpdateComments() async {
    let project = Project.template
      |> (Project.lens.urls.web .. Project.UrlsEnvelope.WebEnvelope.lens.updates)
      .~ "https://www.kickstarter.com/projects/smh/lol/posts"

    let updateId = 123_456

    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()

    let navigationAction = self.navigationAction(
      with:
      URL(string: "\(project.urls.web.updates!)/\(updateId)/comments")!
    )

    XCTAssertEqual(
      WKNavigationActionPolicy.cancel.rawValue,
      self.vm.decidePolicy(forNavigationAction: navigationAction).rawValue
    )

    await self.vm.waitForLoads()

    self.goToUpdateCommentId.assertValues([updateId])
  }

  func testShowMailComposeEmits_WhenEmailLinkIsTapped() async {
    let navigationAction = self.navigationAction(with: URL(string: "mailto:dead@beef.com")!)

    self.vm.canSendEmail(true)

    _ = self.vm.decidePolicy(forNavigationAction: navigationAction)
    self.showMailCompose.assertValues(["dead@beef.com"])
  }

  func testShowEmailErrorEmits_WhenEmailLinkIsTapped_AndCantSendEmail() async {
    let navigationAction = self.navigationAction(with: URL(string: "mailto:dead@beef.com")!)

    self.vm.canSendEmail(false)

    _ = self.vm.decidePolicy(forNavigationAction: navigationAction)
    self.showNoEmailError.assertDidEmitValue()
  }

  func testMakePhoneCallEmits_WhenPhoneLinkIsTapped() async {
    let phoneUrl = URL(string: "tel://5551234567")!
    let navigationAction = self.navigationAction(with: phoneUrl)

    self.vm.viewDidLoad()
    _ = self.vm.decidePolicy(forNavigationAction: navigationAction)
    self.makePhoneCall.assertValues([phoneUrl])
  }

  func testWebViewLoadRequests() async {
    let project = Project.template
      |> (Project.lens.urls.web .. Project.UrlsEnvelope.WebEnvelope.lens.updates)
      .~ "https://www.kickstarter.com/projects/shrimp/ijc/posts"

    let updatesIndexRequest = AppEnvironment.current.apiService.preparedRequest(
      forURL: URL(string: project.urls.web.updates!)!
    )

    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()

    self.webViewLoadRequest.assertValues([updatesIndexRequest])
  }

  func testIFrameRequest() async {
    let project = Project.template
      |> (Project.lens.urls.web .. Project.UrlsEnvelope.WebEnvelope.lens.updates)
      .~ "https://www.kickstarter.com/projects/shrimp/ijc/posts"

    let updatesIndexRequest = AppEnvironment.current.apiService.preparedRequest(
      forURL: URL(string: project.urls.web.updates!)!
    )

    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()

    self.webViewLoadRequest.assertValues([updatesIndexRequest])

    let updateRequest = URLRequest(url: URL(string: "https://www.youtube.com/watch")!)
    let navigationAction = WKNavigationActionData(
      navigationType: .linkActivated,
      request: updateRequest,
      sourceFrame: WKFrameInfoData.init(mainFrame: true, request: updateRequest),
      targetFrame: WKFrameInfoData.init(mainFrame: false, request: updateRequest)
    )

    XCTAssertEqual(
      WKNavigationActionPolicy.allow.rawValue,
      self.vm.decidePolicy(forNavigationAction: navigationAction).rawValue
    )

    self.webViewLoadRequest.assertValues([updatesIndexRequest], "Update loaded in VC, not web view.")
  }

  private func navigationAction(with url: URL) -> WKNavigationActionData {
    let request = URLRequest(url: url)
    return WKNavigationActionData(
      navigationType: .linkActivated,
      request: request,
      sourceFrame: WKFrameInfoData.init(mainFrame: true, request: request),
      targetFrame: WKFrameInfoData.init(mainFrame: true, request: request)
    )
  }
}

private final class UpdatesRecorder<Value> {
  var values: [Value] = []
  func assertDidEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(self.values.isEmpty, message, file: file, line: line)
  }
}
private extension UpdatesRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
