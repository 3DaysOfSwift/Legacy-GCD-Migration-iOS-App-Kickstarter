@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class MessageDialogViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = MessagingFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncMessagingProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm: MessageDialogViewModel = MessageDialogViewModel(feature: self.feature)

  fileprivate let loadingViewIsHidden = Recorder<Bool>()
  fileprivate let postButtonEnabled = Recorder<Bool>()
  fileprivate let notifyPresenterCommentWasPostedSuccesfully = Recorder<Message>()
  fileprivate let notifyPresenterDialogWantsDismissal = Recorder<Void>()
  fileprivate let recipientName = Recorder<String>()
  fileprivate let keyboardIsVisible = Recorder<Bool>()
  fileprivate let showAlertMessage = Recorder<String>()

  override func setUp() async throws {
    try await super.setUp()

    self.vm.onLoadingHidden = { [weak self] in self?.loadingViewIsHidden.record($0) }
    self.vm.onPostEnabled = { [weak self] in self?.postButtonEnabled.record($0) }
    self.vm.onPosted = { [weak self] in self?.notifyPresenterCommentWasPostedSuccesfully.record($0) }
    self.vm.onDismiss = { [weak self] in self?.notifyPresenterDialogWantsDismissal.record(()) }
    self.vm.onRecipient = { [weak self] in self?.recipientName.record($0) }
    self.vm.onKeyboardVisibility = { [weak self] in self?.keyboardIsVisible.record($0) }
    self.vm.onError = { [weak self] in self?.showAlertMessage.record($0) }
  }

  func testRecipientName() async {
    let thread = MessageThread.template
    self.vm.configureWith(messageSubject: .messageThread(thread), context: .messages)
    self.vm.viewDidLoad()

    self.recipientName.assertValues([thread.participant.name])
  }

  func testButtonEnabled() async {
    self.vm.configureWith(messageSubject: .messageThread(.template), context: .messages)
    self.vm.viewDidLoad()
    self.postButtonEnabled.assertValues([false])

    self.vm.bodyTextChanged("hello")
    self.postButtonEnabled.assertValues([false, true])

    self.vm.bodyTextChanged("hello world")
    self.postButtonEnabled.assertValues([false, true])

    self.vm.bodyTextChanged("")
    self.postButtonEnabled.assertValues([false, true, false])

    self.vm.bodyTextChanged("  ")
    self.postButtonEnabled.assertValues([false, true, false])

    self.vm.bodyTextChanged("hello world")
    self.postButtonEnabled.assertValues([false, true, false, true])
  }

  func testKeyboardIsVisible() async {
    self.vm.configureWith(messageSubject: .messageThread(.template), context: .messages)
    self.vm.viewDidLoad()
    self.keyboardIsVisible.assertValues([true])

    self.vm.cancelButtonPressed()
    self.keyboardIsVisible.assertValues([true, false])

    self.vm.viewDidLoad()
    self.keyboardIsVisible.assertValues([true, false, true])

    self.vm.bodyTextChanged("HELLO")
    self.vm.postButtonPressed()
    await self.settleMessaging()

    self.keyboardIsVisible.assertValues([true, false, true, false])
  }

  func testPostingMessageToThread() async {
    XCTAssertEqual([], self.segmentTrackingClient.events)

    self.vm.configureWith(messageSubject: .messageThread(.template), context: .messages)
    self.vm.viewDidLoad()

    self.vm.bodyTextChanged("HELLO")

    self.loadingViewIsHidden.assertValues([true])
    self.notifyPresenterCommentWasPostedSuccesfully.assertValueCount(0)
    self.notifyPresenterDialogWantsDismissal.assertValueCount(0)

    self.vm.postButtonPressed()

    self.loadingViewIsHidden.assertValues([true, false])
    self.notifyPresenterCommentWasPostedSuccesfully.assertValueCount(0)
    self.notifyPresenterDialogWantsDismissal.assertValueCount(0)

    await self.settleMessaging()

    self.loadingViewIsHidden.assertValues([true, false, true])
    self.notifyPresenterCommentWasPostedSuccesfully.assertValueCount(1)
    self.notifyPresenterDialogWantsDismissal.assertValueCount(1)
  }

  func testPostingMessageToCreator() async {
    let project = Project.template
    self.vm.configureWith(
      messageSubject: .project(id: project.id, name: project.name),
      context: .messages
    )
    self.vm.viewDidLoad()
    self.vm.bodyTextChanged("HELLO")

    self.loadingViewIsHidden.assertValues([true])
    self.notifyPresenterCommentWasPostedSuccesfully.assertValueCount(0)
    self.notifyPresenterDialogWantsDismissal.assertValueCount(0)
    self.recipientName.assertValues(["The Project"])

    self.vm.postButtonPressed()

    self.loadingViewIsHidden.assertValues([true, false])
    self.notifyPresenterCommentWasPostedSuccesfully.assertValueCount(0)
    self.notifyPresenterDialogWantsDismissal.assertValueCount(0)

    await self.settleMessaging()

    self.loadingViewIsHidden.assertValues([true, false, true])
    self.notifyPresenterCommentWasPostedSuccesfully.assertValueCount(1)
    self.notifyPresenterDialogWantsDismissal.assertValueCount(1)
  }

  override func tearDown() async throws {
    self.feature.reset()
    await self.feature.waitForOperations()

    try await super.tearDown()
  }

  private func settleMessaging() async {
    await self.vm.waitForSend()
  }
}

private final class Recorder<Value> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, file: file, line: line)
  }
  func assertValues(_ expected: [Value], file: StaticString = #filePath, line: UInt = #line) where Value: Equatable {
    XCTAssertEqual(self.values, expected, file: file, line: line)
  }
}
