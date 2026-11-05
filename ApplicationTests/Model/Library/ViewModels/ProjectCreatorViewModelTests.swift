@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import WebKit
import XCTest

@MainActor
final class ProjectCreatorViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  fileprivate let vm = ProjectCreatorViewModel(projectDetailsFeature: ProjectDetailsFeature(
      sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
      discussionFeature: DiscussionFeature(sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }), makeProvider: { AsyncDiscussionProvider(service: AppEnvironment.current.apiService) }),
      makeProvider: { AsyncProjectDetailsProvider(service: MockService()) }
    ))

  fileprivate let goBackToProject = Recorder<()>()
  fileprivate let goToLoginTout = Recorder<LoginIntent>()
  fileprivate let goToMessageDialogContext = Recorder<KSRAnalytics.MessageDialogContext>()
  fileprivate let goToMessageDialogSubject = Recorder<MessageSubject>()
  fileprivate let goToSafariBrowser = Recorder<URL>()
  fileprivate let loadWebViewRequest = Recorder<URLRequest>()

  override func setUp() async throws {
    try await super.setUp()
    self.vm.onGoBack = { [weak self] in self?.goBackToProject.record(()) }
    self.vm.onLogin = { [weak self] in self?.goToLoginTout.record($0) }
    self.vm.onMessage = { [weak self] subject, context in
      self?.goToMessageDialogSubject.record(subject)
      self?.goToMessageDialogContext.record(context)
    }
    self.vm.onSafari = { [weak self] in self?.goToSafariBrowser.record($0) }
    self.vm.onLoad = { [weak self] in self?.loadWebViewRequest.record($0) }
  }

  func testGoToLoginTout_LoggedOut() throws {
    let project = Project.template
    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()

    self.goToMessageDialogContext.assertValueCount(0)
    self.goToMessageDialogSubject.assertValueCount(0)
    self.goToLoginTout.assertValueCount(0)

    let messagesRequest = URLRequest(
      url: try XCTUnwrap(URL(string: "https://www.kickstarter.com/projects/a/b/messages/new"))
    )
    let policy = self.vm.decidePolicy(
      forNavigationAction: WKNavigationActionData(
        navigationType: .linkActivated,
        request: messagesRequest,
        sourceFrame: WKFrameInfoData(mainFrame: true, request: messagesRequest),
        targetFrame: WKFrameInfoData(mainFrame: true, request: messagesRequest)
      )
    )
    XCTAssertEqual(.cancel, policy)

    self.goToMessageDialogContext.assertValues([])
    self.goToMessageDialogSubject.assertValues([])
    self.goToLoginTout.assertValues([.messageCreator])
  }

  func testGoToLoginTout_LoggedIn() throws {
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: User.template))

    let project = Project.template
    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()

    self.goToLoginTout.assertValueCount(0)

    let messagesRequest = URLRequest(
      url: try XCTUnwrap(URL(string: "https://www.kickstarter.com/projects/a/b/messages/new"))
    )
    let policy = self.vm.decidePolicy(
      forNavigationAction: WKNavigationActionData(
        navigationType: .linkActivated,
        request: messagesRequest,
        sourceFrame: WKFrameInfoData(mainFrame: true, request: messagesRequest),
        targetFrame: WKFrameInfoData(mainFrame: true, request: messagesRequest)
      )
    )
    XCTAssertEqual(.cancel, policy)

    self.goToLoginTout.assertValueCount(0)
  }

  func testGoToMessageDialog() throws {
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: User.template))

    let project = Project.template
    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()

    self.goToMessageDialogContext.assertValues([])
    self.goToMessageDialogSubject.assertValues([])

    let creatorBioRequest = URLRequest(
      url: try XCTUnwrap(URL(string: "https://www.kickstarter.com/projects/a/b/creator_bio"))
    )
    var policy = self.vm.decidePolicy(
      forNavigationAction: WKNavigationActionData(
        navigationType: .other,
        request: creatorBioRequest,
        sourceFrame: WKFrameInfoData(mainFrame: true, request: creatorBioRequest),
        targetFrame: WKFrameInfoData(mainFrame: true, request: creatorBioRequest)
      )
    )
    XCTAssertEqual(.allow, policy)

    self.goToMessageDialogContext.assertValues([])
    self.goToMessageDialogSubject.assertValues([])

    let messagesRequest = URLRequest(
      url: try XCTUnwrap(URL(string: "https://www.kickstarter.com/projects/a/b/messages/new"))
    )
    policy = self.vm.decidePolicy(
      forNavigationAction: WKNavigationActionData(
        navigationType: .linkActivated,
        request: messagesRequest,
        sourceFrame: WKFrameInfoData(mainFrame: true, request: messagesRequest),
        targetFrame: WKFrameInfoData(mainFrame: true, request: messagesRequest)
      )
    )
    XCTAssertEqual(.cancel, policy)

    self.goToMessageDialogContext.assertValues([.projectPage])
    self.goToMessageDialogSubject.assertValues([.project(id: project.id, name: project.name)])
  }

  func testGoBackToProjectDoesNotEmit_whenRequestURL_IsEqualToProjectURL() throws {
    let project = Project.template
    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()

    self.goBackToProject.assertDidNotEmitValue()

    let projectRequest = URLRequest(
      url: try XCTUnwrap(URL(string: "https://www.kickstarter.com/projects/creator/a-fun-project"))
    )
    _ = self.vm.decidePolicy(
      forNavigationAction: WKNavigationActionData(
        navigationType: .linkActivated,
        request: projectRequest,
        sourceFrame: WKFrameInfoData(mainFrame: true, request: projectRequest),
        targetFrame: WKFrameInfoData(mainFrame: true, request: projectRequest)
      )
    )
    self.goBackToProject.assertDidEmitValue()
  }

  func testGoBackToProjectDoesNotEmit_whenRequestURL_IsNotEqualToProjectURL() throws {
    let project = Project.template
    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()

    self.goBackToProject.assertDidNotEmitValue()

    let linkRequest = URLRequest(
      url: try XCTUnwrap(URL(string: "https://www.kickstarter.com/projects/creator/about"))
    )
    _ = self.vm.decidePolicy(
      forNavigationAction: WKNavigationActionData(
        navigationType: .linkActivated,
        request: linkRequest,
        sourceFrame: WKFrameInfoData(mainFrame: true, request: linkRequest),
        targetFrame: WKFrameInfoData(mainFrame: true, request: linkRequest)
      )
    )
    self.goBackToProject.assertDidNotEmitValue()
  }

  func testGoToSafariBrowser() throws {
    let project = Project.template
    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()

    self.goToSafariBrowser.assertValues([])

    let creatorBioRequest = URLRequest(
      url: try XCTUnwrap(URL(string: "https://www.kickstarter.com/projects/a/b/creator_bio"))
    )
    var policy = self.vm.decidePolicy(
      forNavigationAction: WKNavigationActionData(
        navigationType: .other,
        request: creatorBioRequest,
        sourceFrame: WKFrameInfoData(mainFrame: true, request: creatorBioRequest),
        targetFrame: WKFrameInfoData(mainFrame: true, request: creatorBioRequest)
      )
    )
    XCTAssertEqual(.allow, policy)

    self.goToSafariBrowser.assertValues([])

    let googleRequest = URLRequest(
      url: try XCTUnwrap(URL(string: "http://www.google.com"))
    )
    policy = self.vm.decidePolicy(
      forNavigationAction: WKNavigationActionData(
        navigationType: .linkActivated,
        request: googleRequest,
        sourceFrame: WKFrameInfoData(mainFrame: true, request: googleRequest),
        targetFrame: WKFrameInfoData(mainFrame: true, request: googleRequest)
      )
    )
    XCTAssertEqual(.cancel, policy)

    self.goToSafariBrowser.assertValues([try XCTUnwrap(URL(string: "http://www.google.com"))])
  }

  func testLoadWebViewRequest() throws {
    let project = Project.template
    let creatorBioRequest = AppEnvironment.current.apiService.preparedRequest(
      forURL: try XCTUnwrap(URL(string: "\(project.urls.web.project)/creator_bio"))
    )

    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()

    self.loadWebViewRequest.assertValues([creatorBioRequest])

    let googleRequest = URLRequest(
      url: try XCTUnwrap(URL(string: "https://www.google.com"))
    )
    let policy = self.vm.decidePolicy(
      forNavigationAction: WKNavigationActionData(
        navigationType: .linkActivated,
        request: googleRequest,
        sourceFrame: WKFrameInfoData(mainFrame: true, request: googleRequest),
        targetFrame: WKFrameInfoData(mainFrame: true, request: googleRequest)
      )
    )
    XCTAssertEqual(.cancel, policy)

    self.loadWebViewRequest.assertValues([creatorBioRequest])
  }
}

private final class Recorder<Value> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(self.values.count, count, file: file, line: line) }
  func assertDidNotEmitValue(file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(self.values.isEmpty, file: file, line: line) }
  func assertDidEmitValue(file: StaticString = #filePath, line: UInt = #line) { XCTAssertFalse(self.values.isEmpty, file: file, line: line) }
  func assertValues(_ expected: [Value], file: StaticString = #filePath, line: UInt = #line) where Value: Equatable { XCTAssertEqual(self.values, expected, file: file, line: line) }
}
