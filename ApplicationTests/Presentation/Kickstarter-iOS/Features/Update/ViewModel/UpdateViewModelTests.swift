@testable import Kickstarter_iOS

@testable import KsApi


import Prelude
import WebKit
import XCTest

@MainActor
final class UpdateViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  fileprivate let vm = UpdateViewModel(feature: DiscussionFeature(sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }), makeProvider: {
    AsyncDiscussionProvider(service: AppEnvironment.current.apiService)
  }))

  fileprivate let project = .template |> Project.lens.id .~ 1
  fileprivate let update = .template
    |> Update.lens.projectId .~ 1

  fileprivate let goToComments = UpdateRecorder<Update>()
  fileprivate let goToProject = UpdateRecorder<Project>()
  fileprivate let goToSafariBrowser = UpdateRecorder<URL>()
  fileprivate let title = UpdateRecorder<String>()
  fileprivate let webViewLoadRequest = UpdateRecorder<String?>()

  override func setUp() async throws {
    try await super.setUp()
    self.vm.onComments = { self.goToComments.values.append($0) }
    self.vm.onProject = { project, _ in self.goToProject.values.append(project) }
    self.vm.onSafari = { self.goToSafariBrowser.values.append($0) }
    self.vm.onTitle = { self.title.values.append($0) }
    self.vm.onLoadRequest = { self.webViewLoadRequest.values.append($0.url?.absoluteString) }
  }

  func testUpdateUrlLoads() async {
    self.vm.configureWith(project: self.project, update: self.update)
    self.vm.viewDidLoad()

    let query = "client_id=\(self.apiService.serverConfig.apiClientAuth.clientId)&currency=USD"
    self.webViewLoadRequest.assertValues(
      ["\(self.update.urls.web.update)?\(query)"]
    )
  }

  func testTitle() async {
    self.vm.configureWith(project: self.project, update: self.update)
    self.vm.viewDidLoad()

    await self.vm.waitForLoads()

    self.title.assertValues(
      [Strings.activity_project_update_update_count(update_count: String(self.update.sequence))]
    )
  }

  func testGoToAnotherUpdate() async {
    let prevUpdate = .template
      |> Update.lens.id .~ 42
      |> Update.lens.sequence .~ 42

    let prevUpdateUrl = URL(string: prevUpdate.urls.web.update)
      .flatMap { $0.deletingLastPathComponent() }
      .map { $0.appendingPathComponent(String(prevUpdate.id)) }!

    self.vm.configureWith(project: self.project, update: self.update)
    self.vm.viewDidLoad()

    await withEnvironment(apiService: MockService(fetchUpdateResponse: prevUpdate)) {
      let request = URLRequest(url: prevUpdateUrl)
      let navigationAction = WKNavigationActionData(
        navigationType: .linkActivated,
        request: request,
        sourceFrame: WKFrameInfoData(mainFrame: true, request: request),
        targetFrame: WKFrameInfoData(mainFrame: true, request: request)
      )

      let policy = self.vm.decidePolicyFor(navigationAction: navigationAction)

      XCTAssertEqual(WKNavigationActionPolicy.cancel.rawValue, policy.rawValue)

      await self.vm.waitForLoads()

      self.goToSafariBrowser.assertDidNotEmitValue("New update request should not load in Safari browser.")

      let query = "client_id=\(self.apiService.serverConfig.apiClientAuth.clientId)&currency=USD"
      self.webViewLoadRequest.assertValues(
        [
          "\(self.update.urls.web.update)?\(query)",
          "\(prevUpdateUrl.absoluteString)?\(query)"
        ]
      )

      await self.vm.waitForLoads()

      self.title.assertValues(
        [
          Strings.activity_project_update_update_count(update_count: String(self.update.sequence)),
          Strings.activity_project_update_update_count(update_count: String(prevUpdate.sequence))
        ]
      )
    }
  }

  func testGoToProject() async {
    let anotherProject = .template |> Project.lens.id .~ 42
    let anotherProjectUrl = URL(string: anotherProject.urls.web.project)
      .flatMap { $0.deletingLastPathComponent() }
      .map { $0.appendingPathComponent(String(anotherProject.id)) }!

    self.vm.configureWith(project: self.project, update: self.update)
    self.vm.viewDidLoad()

    await withEnvironment(apiService: MockService(fetchProjectResult: .success(anotherProject))) {
      let request = URLRequest(url: anotherProjectUrl)
      let navigationAction = WKNavigationActionData(
        navigationType: .linkActivated,
        request: request,
        sourceFrame: WKFrameInfoData(mainFrame: true, request: request),
        targetFrame: WKFrameInfoData(mainFrame: true, request: request)
      )

      let policy = self.vm.decidePolicyFor(navigationAction: navigationAction)

      XCTAssertEqual(WKNavigationActionPolicy.cancel.rawValue, policy.rawValue)

      await self.vm.waitForLoads()

      self.goToProject.assertValues([anotherProject])
      self.goToComments.assertValueCount(0)
    }

    let query = "client_id=\(self.apiService.serverConfig.apiClientAuth.clientId)&currency=USD"
    self.webViewLoadRequest.assertValues(
      ["\(self.update.urls.web.update)?\(query)"]
    )
  }

  func testGoToComments() async {
    self.vm.configureWith(project: self.project, update: self.update)
    self.vm.viewDidLoad()

    let commentsRequest = URL(string: self.update.urls.web.update)
      .map { $0.appendingPathComponent("comments") }
      .flatMap { URLRequest.init(url: $0) }!

    let navigationAction = WKNavigationActionData(
      navigationType: .linkActivated,
      request: commentsRequest,
      sourceFrame: WKFrameInfoData(mainFrame: true, request: commentsRequest),
      targetFrame: WKFrameInfoData(mainFrame: true, request: commentsRequest)
    )

    XCTAssertEqual(
      WKNavigationActionPolicy.cancel.rawValue,
      self.vm.decidePolicyFor(navigationAction: navigationAction).rawValue
    )
    self.goToComments.assertValues([self.update])
    await self.vm.waitForLoads()
    self.goToProject.assertDidNotEmitValue()
    await self.vm.waitForLoads()
    self.goToSafariBrowser.assertDidNotEmitValue()
  }

  func testGoToSafariBrowser() async {
    self.vm.configureWith(project: self.project, update: self.update)
    self.vm.viewDidLoad()

    let updateRequest = URLRequest(url: URL(string: self.update.urls.web.update)!)
    var navigationAction = WKNavigationActionData(
      navigationType: .other,
      request: updateRequest,
      sourceFrame: WKFrameInfoData(mainFrame: true, request: updateRequest),
      targetFrame: WKFrameInfoData(mainFrame: true, request: updateRequest)
    )

    XCTAssertEqual(
      WKNavigationActionPolicy.allow.rawValue,
      self.vm.decidePolicyFor(navigationAction: navigationAction).rawValue
    )
    self.webViewLoadRequest.assertValueCount(1)
    await self.vm.waitForLoads()
    self.goToSafariBrowser.assertDidNotEmitValue()

    let outsideUrl = URL(string: "http://www.wikipedia.com")!
    let outsideRequest = URLRequest(url: outsideUrl)

    navigationAction = WKNavigationActionData(
      navigationType: .linkActivated,
      request: outsideRequest,
      sourceFrame: WKFrameInfoData(mainFrame: true, request: outsideRequest),
      targetFrame: WKFrameInfoData(mainFrame: true, request: outsideRequest)
    )

    XCTAssertEqual(
      WKNavigationActionPolicy.cancel.rawValue,
      self.vm.decidePolicyFor(navigationAction: navigationAction).rawValue
    )
    self.goToComments.assertValueCount(0)
    await self.vm.waitForLoads()
    self.goToProject.assertValueCount(0)
    self.webViewLoadRequest.assertValueCount(1)
    await self.vm.waitForLoads()
    self.goToSafariBrowser.assertValues([outsideUrl])

    XCTAssertEqual([], self.segmentTrackingClient.events)
  }

  func testGoToSafariBrowser_PrelaunchProject() async {
    let prelaunchProject = Project.template
      |> Project.lens.id .~ 10
      |> Project.lens.displayPrelaunch .~ true
    let prelaunchProjectURL = URL(string: prelaunchProject.urls.web.project)
      .flatMap { $0.deletingLastPathComponent() }
      .map { $0.appendingPathComponent(String(prelaunchProject.id)) }!

    self.vm.configureWith(project: self.project, update: self.update)
    self.vm.viewDidLoad()

    await withEnvironment(apiService: MockService(fetchProjectResult: .success(prelaunchProject))) {
      guard let google = URL(string: "https://www.google.com") else {
        XCTFail("Should have a URL")
        return
      }

      let request1 = URLRequest(url: google)

      let navigationAction1 = WKNavigationActionData(
        navigationType: .other,
        request: request1,
        sourceFrame: WKFrameInfoData(mainFrame: true, request: request1),
        targetFrame: WKFrameInfoData(mainFrame: true, request: request1)
      )

      XCTAssertEqual(
        WKNavigationActionPolicy.allow.rawValue,
        self.vm.decidePolicyFor(navigationAction: navigationAction1).rawValue
      )

      await self.vm.waitForLoads()

      self.goToProject.assertDidNotEmitValue()
      self.goToComments.assertDidNotEmitValue()
      self.webViewLoadRequest.assertValueCount(1, "Initial update load request")
      await self.vm.waitForLoads()
      self.goToSafariBrowser.assertValues([])

      XCTAssertEqual([], self.segmentTrackingClient.events)
      XCTAssertEqual(nil, self.segmentTrackingClient.properties.last?["context"] as? String)

      let request2 = URLRequest(url: prelaunchProjectURL)

      let navigationAction2 = WKNavigationActionData(
        navigationType: .linkActivated,
        request: request2,
        sourceFrame: WKFrameInfoData(mainFrame: true, request: request2),
        targetFrame: WKFrameInfoData(mainFrame: true, request: request2)
      )

      XCTAssertEqual(
        WKNavigationActionPolicy.cancel.rawValue,
        self.vm.decidePolicyFor(navigationAction: navigationAction2).rawValue
      )

      await self.vm.waitForLoads()

      self.goToProject.assertDidNotEmitValue()
      self.goToComments.assertDidNotEmitValue()
      self.webViewLoadRequest.assertValueCount(1, "Initial update load request")
      await self.vm.waitForLoads()
      self.goToSafariBrowser.assertValues([prelaunchProjectURL])

      XCTAssertEqual([], self.segmentTrackingClient.events)
      XCTAssertEqual(nil, self.segmentTrackingClient.properties.last?["context"] as? String)
    }
  }
}

private final class UpdateRecorder<Value> {
  var values: [Value] = []
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, message, file: file, line: line)
  }
}
private extension UpdateRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
