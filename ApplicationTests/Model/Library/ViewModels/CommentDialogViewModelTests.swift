@testable import Kickstarter_iOS
@testable import KsApi


import XCTest

@MainActor
internal final class CommentDialogViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  internal let vm = CommentDialogViewModel(feature: DiscussionFeature(sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }), makeProvider: {
    AsyncDiscussionProvider(service: AppEnvironment.current.apiService)
  }), sleep: { try Task.checkCancellation() })

  private let bodyTextViewText = CommentRecording<String>()
  private var postButtonEnabled = CommentRecording<Bool>()
  private var loadingViewIsHidden = CommentRecording<Bool>()
  private var presentError = CommentRecording<String>()
  private let notifyPresenterCommentWasPostedSuccesfully = CommentRecording<Comment>()
  private let notifyPresenterDialogWantsDismissal = CommentRecording<()>()
  private let showKeyboard = CommentRecording<Bool>()

  internal override func setUp() async throws {
    try await super.setUp()

    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .body(value): self.bodyTextViewText.append(value)
      case let .postEnabled(value): self.postButtonEnabled.append(value)
      case let .loadingHidden(value): self.loadingViewIsHidden.append(value)
      case let .posted(value): self.notifyPresenterCommentWasPostedSuccesfully.append(value)
      case .dismiss: self.notifyPresenterDialogWantsDismissal.append(())
      case let .keyboard(value): self.showKeyboard.append(value)
      case let .error(value): self.presentError.append(value)
      case .subtitle: break
      }
    }
  }

  func testBodyTextViewText_WithoutRecipient() async {
    self.vm
      .configureWith(project: .template, update: nil, recipientName: nil, context: .projectComments)
    self.vm.viewWillAppear()

    self.bodyTextViewText.assertValueCount(0)
  }

  func testBodyTextViewText_WithRecipient() async {
    let author = ActivityCommentAuthor.template
    self.vm.configureWith(
      project: .template,
      update: nil,
      recipientName: author.name,
      context: .projectComments
    )
    self.vm.viewWillAppear()

    self.bodyTextViewText.assertValues(["@\(author.name): "])
  }

  internal func testPostingFlow_Project() async {
    await withEnvironment(
      apiService: MockService(postCommentResult: .success(.template)),
      currentUser: .template
    ) {
      self.vm
        .configureWith(project: .template, update: nil, recipientName: nil, context: .projectComments)
      self.vm.viewWillAppear()

      self.postButtonEnabled.assertValues([false], "Button is not enabled initially.")
      self.loadingViewIsHidden.assertValues([true], "Loading view starts hidden")

      self.vm.commentBodyChanged("h")
      self.postButtonEnabled.assertValues([false, true], "Button enabled after typing comment body.")

      self.vm.commentBodyChanged("")
      self.postButtonEnabled.assertValues([false, true, false], "Button disabled after clearing body.")

      self.vm.commentBodyChanged("h")
      self.vm.commentBodyChanged("he")
      self.vm.commentBodyChanged("hel")
      self.vm.commentBodyChanged("hell")
      self.vm.commentBodyChanged("hello")

      self.postButtonEnabled.assertValues(
        [false, true, false, true],
        "Button re-enabled after typing comment body."
      )

      self.vm.postButtonPressed()

      await self.vm.waitForMutations()

      self.loadingViewIsHidden.assertValues(
        [true, false, true],
        "Comment is posting and then done after pressing button."
      )
      self.notifyPresenterCommentWasPostedSuccesfully
        .assertValueCount(
          2,
          "Comment posts successfully. Two comments are posted, one optimistically and another when network returns response."
        )
      self.notifyPresenterDialogWantsDismissal
        .assertValueCount(
          2,
          "Dialog is dismissed after posting of comment. Two dismissals because of two comments being posted, not ideal."
        )

      XCTAssertEqual(
        [],
        self.segmentTrackingClient.events, "Koala event is tracked."
      )
      XCTAssertEqual(
        [],
        self.segmentTrackingClient.properties(forKey: "type", as: String.self)
      )
    }
  }

  internal func testPostingFlow_Update() async {
    await withEnvironment(
      apiService: MockService(postCommentResult: .success(.template)),
      currentUser: .template
    ) {
      self.vm.configureWith(
        project: .template, update: .template, recipientName: nil,
        context: .updateComments
      )
      self.vm.viewWillAppear()

      self.postButtonEnabled.assertValues([false], "Button is not enabled initially.")
      self.loadingViewIsHidden.assertValues([true], "Loading view starts hidden")

      self.vm.commentBodyChanged("h")
      self.postButtonEnabled.assertValues([false, true], "Button enabled after typing comment body.")

      self.vm.commentBodyChanged("")
      self.postButtonEnabled.assertValues([false, true, false], "Button disabled after clearing body.")

      self.vm.commentBodyChanged("h")
      self.vm.commentBodyChanged("he")
      self.vm.commentBodyChanged("hel")
      self.vm.commentBodyChanged("hell")
      self.vm.commentBodyChanged("hello")

      self.postButtonEnabled.assertValues(
        [false, true, false, true],
        "Button re-enabled after typing comment body."
      )

      self.vm.postButtonPressed()

      await self.vm.waitForMutations()

      self.loadingViewIsHidden.assertValues(
        [true, false, true],
        "Comment is posting and then done after pressing button."
      )
      self.notifyPresenterCommentWasPostedSuccesfully
        .assertValueCount(
          2,
          "Comment posts successfully. Two comments are posted, one optimistically and another when network returns response."
        )
      self.notifyPresenterDialogWantsDismissal
        .assertValueCount(
          2,
          "Dialog is dismissed after posting of comment. Two dismissals because of two comments being posted, not ideal."
        )

      XCTAssertEqual(
        [],
        self.segmentTrackingClient.events, "Koala event is tracked."
      )
      XCTAssertEqual(
        [],
        self.segmentTrackingClient.properties(forKey: "type", as: String.self)
      )
    }
  }

  internal func testPostingErrorFlow() async {
    await withEnvironment(
      apiService: MockService(postCommentResult: .failure(.couldNotParseJSON)),
      currentUser: .template
    ) {
      self.vm
        .configureWith(project: .template, update: nil, recipientName: nil, context: .projectComments)
      self.vm.viewWillAppear()
      self.vm.commentBodyChanged("hello")

      self.vm.postButtonPressed()

      await self.vm.waitForMutations()

      self.presentError.assertValues(["Something went wrong, please try again."], "Error message is emitted.")
      self.loadingViewIsHidden.assertValues(
        [true, false, true],
        "Comment is posting and then done after pressing button."
      )

      self.notifyPresenterCommentWasPostedSuccesfully
        .assertValueCount(
          1,
          "Comment does not post successfuly. However, because comments are posted optimistically, we still count this as successful post. See //FIXME in view model for more info."
        )
      self.notifyPresenterDialogWantsDismissal
        .assertValueCount(
          1,
          "Comment dialog does not dismiss automatically. However, because comments are posted optimistically, we still dismiss the dialog. See //FIXME in view model for more info."
        )
    }
  }

  internal func testPostingErrorFlow_WithMissingErrorMessage() async {
    await withEnvironment(
      apiService: MockService(postCommentResult: .failure(.couldNotParseJSON)),
      currentUser: .template
    ) {
      self.vm
        .configureWith(project: .template, update: nil, recipientName: nil, context: .projectComments)
      self.vm.viewWillAppear()
      self.vm.commentBodyChanged("hello")

      self.vm.postButtonPressed()

      await self.vm.waitForMutations()

      self.presentError
        .assertValueCount(
          1,
          "Error message is emitted. Not displayed to user. See //FIXME in view model for more info."
        )

      XCTAssertEqual([], self.segmentTrackingClient.events)
    }
  }

  internal func testCancellingFlow() async {
    self.vm
      .configureWith(project: .template, update: nil, recipientName: nil, context: .projectComments)
    self.vm.viewWillAppear()

    self.vm.cancelButtonPressed()
    self.notifyPresenterDialogWantsDismissal.assertValueCount(1)

    XCTAssertEqual([], self.segmentTrackingClient.events)
  }

  func testShowKeyboard() async {
    self.vm
      .configureWith(project: .template, update: nil, recipientName: nil, context: .projectComments)
    self.vm.viewWillAppear()

    self.showKeyboard.assertValues([true])

    self.vm.viewWillDisappear()

    self.showKeyboard.assertValues([true, false])
  }
}

private final class CommentRecording<Value> {
  private(set) var values: [Value] = []
  func append(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
}
private extension CommentRecording where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
