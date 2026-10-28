import Foundation
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveSwift
import XCTest

@MainActor
final class MessagingFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let provider = ControlledMessagingProvider()
  private let session = SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) },
                                       currentUser: { .template }, updateUser: { _ in })
  private lazy var feature = MessagingFeature(sessionFeature: self.session, makeProvider: { self.provider })

  override func tearDown() async throws {
    self.feature.reset()
    self.provider.releaseAll()
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  private func page(_ ids: [Int], cursor: String = "next") -> MessageThreadsEnvelope {
    .init(messageThreads: ids.map { id in
      let source = MessageThread.template
      return MessageThread(backing: source.backing, closed: source.closed, id: id,
                           lastMessage: source.lastMessage, participant: source.participant,
                           project: source.project, unreadMessagesCount: source.unreadMessagesCount)
    },
          urls: .init(api: .init(moreMessageThreads: cursor)))
  }

  func testMailboxSharesPendingPagesAndPreservesConcatenation() async throws {
    let route = UUID()
    let first = self.feature.requestMailbox(route: route, mailbox: .inbox, project: nil)
    let duplicate = self.feature.requestMailbox(route: route, mailbox: .inbox, project: nil)
    await self.provider.pages.waitFor(1)
    XCTAssertEqual(self.provider.pages.count, 1)
    try self.provider.pages.finish(0, .success(self.page([1, 2])))
    await first.value; await duplicate.value
    let next = self.feature.requestNextPage(route: route)
    let repeated = self.feature.requestNextPage(route: route)
    await self.provider.pages.waitFor(2)
    XCTAssertEqual(self.provider.cursors, [nil, "next"])
    try self.provider.pages.finish(1, .success(self.page([2, 3])))
    await next?.value; await repeated?.value
    XCTAssertEqual(self.feature.snapshot(route: route).threads.map(\.id), [1, 2, 2, 3])
    XCTAssertFalse(self.feature.snapshot(route: route).isLoading)
  }

  func testMailboxChangeRejectsLatePageAndEmptyPageStopsPagination() async throws {
    let route = UUID()
    let old = self.feature.requestMailbox(route: route, mailbox: .inbox, project: nil)
    await self.provider.pages.waitFor(1)
    let current = self.feature.requestMailbox(route: route, mailbox: .sent, project: nil)
    await self.provider.pages.waitFor(2)
    try self.provider.pages.finish(1, .success(self.page([])))
    await current.value
    try self.provider.pages.finish(0, .success(self.page([99])))
    await old.value
    XCTAssertTrue(self.feature.snapshot(route: route).threads.isEmpty)
    XCTAssertNil(self.feature.requestNextPage(route: route))
  }

  func testRefreshSupersedesNextPageAndFailureAllowsExplicitRetry() async throws {
    let route = UUID()
    let initial = self.feature.requestMailbox(route: route, mailbox: .inbox, project: nil)
    await self.provider.pages.waitFor(1)
    try self.provider.pages.finish(0, .success(self.page([1])))
    await initial.value
    let old = self.feature.requestNextPage(route: route)
    await self.provider.pages.waitFor(2)
    let refresh = self.feature.requestMailbox(route: route, mailbox: .inbox, project: nil, refresh: true)
    await self.provider.pages.waitFor(3)
    try self.provider.pages.finish(2, .failure(ErrorEnvelope.couldNotParseJSON))
    await refresh.value
    try self.provider.pages.finish(1, .success(self.page([2])))
    await old?.value
    XCTAssertNotNil(self.feature.snapshot(route: route).error)
    XCTAssertTrue(self.feature.snapshot(route: route).threads.isEmpty)
    let retry = self.feature.requestMailbox(route: route, mailbox: .inbox, project: nil, refresh: true)
    await self.provider.pages.waitFor(4)
    try self.provider.pages.finish(3, .success(self.page([3])))
    await retry.value
    XCTAssertEqual(self.feature.snapshot(route: route).threads.map(\.id), [3])
    XCTAssertNil(self.feature.snapshot(route: route).error)
  }

  func testMailboxRoutesDoNotCancelEachOther() async throws {
    let firstRoute = UUID(), secondRoute = UUID()
    let first = self.feature.requestMailbox(route: firstRoute, mailbox: .inbox, project: nil)
    await self.provider.pages.waitFor(1)
    let second = self.feature.requestMailbox(route: secondRoute, mailbox: .sent, project: .template)
    await self.provider.pages.waitFor(2)
    try self.provider.pages.finish(1, .success(self.page([2])))
    try self.provider.pages.finish(0, .success(self.page([1])))
    await first.value; await second.value
    XCTAssertEqual(self.feature.snapshot(route: firstRoute).threads.map(\.id), [1])
    XCTAssertEqual(self.feature.snapshot(route: secondRoute).threads.map(\.id), [2])
  }

  func testClearedSearchRejectsTransportThatIgnoresCancellation() async throws {
    let vm = MessagesSearchViewModel(feature: self.feature)
    var values: [[MessageThread]] = []
    let observation = vm.outputs.messageThreads.observeValues { values.append($0) }
    defer { observation?.dispose() }
    vm.configureWith(project: nil); vm.viewDidLoad()
    vm.searchTextChanged("old")
    await self.scheduler.advance()
    await self.provider.searches.waitFor(1)
    vm.clearSearchText()
    try self.provider.searches.finish(0, .success(self.page([99])))
    await self.feature.waitForOperations()
    await self.scheduler.advance()
    XCTAssertTrue(values.isEmpty)
    vm.searchTextChanged("new")
    await self.scheduler.advance()
    await self.provider.searches.waitFor(2)
    try self.provider.searches.finish(1, .success(self.page([2])))
    await self.feature.waitForOperations()
    XCTAssertEqual(values.last?.map(\.id), [2])
    XCTAssertEqual(self.provider.queries, ["old", "new"])
  }

  func testDisappearingBeforeDebounceDoesNotStartHiddenSearch() async {
    await withEnvironment(debounceInterval: .seconds(1)) {
      let vm = MessagesSearchViewModel(feature: self.feature)
      vm.configureWith(project: nil); vm.viewDidLoad()
      vm.searchTextChanged("hidden")
      vm.viewWillDisappear()
      await self.scheduler.advance(by: .seconds(2))
      await self.feature.waitForOperations()
      XCTAssertEqual(self.provider.searches.count, 0)
    }
  }

  func testNewQueryCancelsOldBeforeDebounceAndLateErrorCannotStopNewSearch() async throws {
    let vm = MessagesSearchViewModel(feature: self.feature)
    var searching: [Bool] = []
    let observation = vm.outputs.isSearching.observeValues { searching.append($0) }
    defer { observation?.dispose() }
    vm.configureWith(project: nil); vm.viewDidLoad()
    vm.searchTextChanged("first")
    await self.scheduler.advance()
    await self.provider.searches.waitFor(1)
    vm.searchTextChanged("second")
    await self.scheduler.advance()
    await self.provider.searches.waitFor(2)
    try self.provider.searches.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await Task.yield()
    XCTAssertEqual(searching.last, true)
    try self.provider.searches.finish(1, .success(self.page([2])))
    await self.feature.waitForOperations()
    XCTAssertEqual(searching.last, false)
  }

  func testSendOrderDuplicateSharingAndDisposedObserversDoNotDropWrites() async throws {
    let subject = MessageSubject.project(id: 42, name: "Fixture")
    let first = self.feature.sendResult(body: "A", subject: subject).start()
    let duplicate = self.feature.sendResult(body: "A", subject: subject).start()
    let second = self.feature.sendResult(body: "B", subject: subject).start()
    let third = self.feature.sendResult(body: "A", subject: subject).start()
    first.dispose(); duplicate.dispose(); second.dispose(); third.dispose()
    await self.provider.sends.waitFor(1)
    XCTAssertEqual(self.provider.bodies, ["A"])
    try self.provider.sends.finish(0, .success(.template))
    await self.provider.sends.waitFor(2)
    XCTAssertEqual(self.provider.bodies, ["A", "B"])
    try self.provider.sends.finish(1, .success(.template))
    await self.provider.sends.waitFor(3)
    XCTAssertEqual(self.provider.bodies, ["A", "B", "A"])
    try self.provider.sends.finish(2, .success(.template))
    await self.feature.waitForOperations()
  }

  func testFailedSendDoesNotRetryAndNextCommandCanSucceed() async throws {
    let subject = MessageSubject.project(id: 42, name: "Fixture")
    let failed = self.feature.requestSend(body: "A", subject: subject)
    let next = self.feature.requestSend(body: "B", subject: subject)
    await self.provider.sends.waitFor(1)
    try self.provider.sends.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do { _ = try await failed.value; XCTFail("Expected failure") } catch { XCTAssertTrue(error is ErrorEnvelope) }
    await self.provider.sends.waitFor(2)
    try self.provider.sends.finish(1, .success(.template))
    _ = try await next.value
    XCTAssertEqual(self.provider.bodies, ["A", "B"])
  }

  func testSessionChangeRejectsLateSendAndDoesNotAdmitQueuedOldAccountCommand() async throws {
    let subject = MessageSubject.project(id: 42, name: "Fixture")
    let first = self.feature.requestSend(body: "A", subject: subject)
    let queued = self.feature.requestSend(body: "B", subject: subject)
    await self.provider.sends.waitFor(1)
    self.session.sessionChanged()
    try self.provider.sends.finish(0, .success(.template))
    for task in [first, queued] {
      do { _ = try await task.value; XCTFail("Old session escaped") }
      catch { XCTAssertTrue(error is CancellationError) }
    }
    XCTAssertEqual(self.provider.bodies, ["A"])
  }

  func testMarkReadSharesPendingWriteAndRejectsOldSession() async throws {
    let first = self.feature.requestMarkRead(.template)
    let second = self.feature.requestMarkRead(.template)
    await self.provider.reads.waitFor(1)
    XCTAssertEqual(self.provider.reads.count, 1)
    self.session.sessionChanged()
    try self.provider.reads.finish(0, .success(.template))
    for task in [first, second] {
      do { _ = try await task.value; XCTFail("Old read status escaped") }
      catch { XCTAssertTrue(error is CancellationError) }
    }
  }

  func testCancelDialogKeepsSendButSuppressesLateSuccess() async throws {
    let vm = MessageDialogViewModel(feature: self.feature)
    var posted = 0
    let observation = vm.outputs.notifyPresenterCommentWasPostedSuccesfully.observeValues { _ in posted += 1 }
    defer { observation?.dispose() }
    vm.configureWith(messageSubject: .project(id: 1, name: "Fixture"), context: .messages)
    vm.viewDidLoad(); vm.bodyTextChanged("Hello"); vm.postButtonPressed()
    await self.provider.sends.waitFor(1)
    vm.cancelButtonPressed()
    try self.provider.sends.finish(0, .success(.template))
    await self.feature.waitForOperations()
    await self.scheduler.advance()
    XCTAssertEqual(self.provider.bodies, ["Hello"])
    XCTAssertEqual(posted, 0)
  }

  func testSessionChangeDuringPresentationDelaySuppressesSuccess() async throws {
    let producer = self.feature.delayedResult(self.feature.sendResult(
      body: "Hello", subject: .project(id: 1, name: "Fixture")
    ))
    var delivered = 0
    let observation = producer.startWithResult { if case .success = $0 { delivered += 1 } }
    defer { observation.dispose() }
    await self.provider.sends.waitFor(1)
    try self.provider.sends.finish(0, .success(.template))
    await self.feature.waitForOperations()
    self.session.sessionChanged()
    await self.scheduler.advance()
    XCTAssertEqual(delivered, 0)
  }

  func testThreadReadRejectsSameUserReplacementSession() async throws {
    let task = Task { try await self.feature.thread(id: 42) }
    await self.provider.threads.waitFor(1)
    self.session.sessionChanged()
    let value = try await MockService().messageThread(id: 42)
    try self.provider.threads.finish(0, .success(value))
    do { _ = try await task.value; XCTFail("Old session escaped") }
    catch { XCTAssertTrue(error is CancellationError) }
  }

  func testReleasedReadCannotDeliverLateFailure() async throws {
    let route = UUID()
    var events = 0
    let observation = self.feature.readResult(route: route) {
      try await self.feature.thread(id: 42)
    }.start { event in
      switch event {
      case .value, .failed: events += 1
      case .completed, .interrupted: break
      }
    }
    defer { observation.dispose() }
    await self.provider.threads.waitFor(1)
    self.feature.release(route: route)
    try self.provider.threads.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.feature.waitForOperations()
    XCTAssertEqual(events, 0)
  }
}

@MainActor
private final class ControlledMessagingProvider: MessagingProvider {
  let pages = AccountRequestGate<MessageThreadsEnvelope>()
  let searches = AccountRequestGate<MessageThreadsEnvelope>()
  let sends = AccountRequestGate<Message>()
  let reads = AccountRequestGate<MessageThread>()
  let threads = AccountRequestGate<MessageThreadEnvelope>()
  private(set) var bodies: [String] = []
  private(set) var queries: [String] = []
  private(set) var cursors: [String?] = []
  func page(mailbox: Mailbox, project: Project?, cursor: String?) async throws -> MessageThreadsEnvelope {
    self.cursors.append(cursor)
    return try await self.pages.request()
  }
  func search(query: String, project: Project?) async throws -> MessageThreadsEnvelope {
    self.queries.append(query)
    return try await self.searches.request()
  }
  func thread(id: Int) async throws -> MessageThreadEnvelope { try await self.threads.request() }
  func thread(backing: Backing) async throws -> MessageThreadEnvelope? { try await self.threads.request() }
  func backing(id: Int) async throws -> Backing { .template }
  func backing(project: Project, user: User) async throws -> Backing { .template }
  func markRead(_ thread: MessageThread) async throws -> MessageThread { try await self.reads.request() }
  func send(body: String, subject: MessageSubject) async throws -> Message {
    self.bodies.append(body)
    return try await self.sends.request()
  }
  func releaseAll() {
    self.pages.releaseAll(); self.searches.releaseAll(); self.sends.releaseAll()
    self.reads.releaseAll(); self.threads.releaseAll()
  }
}
