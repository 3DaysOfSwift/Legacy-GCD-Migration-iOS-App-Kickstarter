@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


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

  func testMailboxPresentationPagesAndRejectsLateResultAfterSwitch() async throws {
    let vm = MessageThreadsViewModel(feature: self.feature)
    vm.configureWith(project: .template, refTag: nil)
    vm.viewDidLoad()
    await self.provider.pages.waitFor(1)
    try self.provider.pages.finish(0, .success(self.page([1, 2])))
    await vm.waitForPresentation()
    XCTAssertEqual(vm.messageThreads.map(\.id), [1, 2])
    XCTAssertTrue(vm.loadingFooterIsHidden)

    vm.willDisplayRow(1, outOf: 2)
    await self.provider.pages.waitFor(2)
    XCTAssertFalse(vm.loadingFooterIsHidden)
    vm.switchTo(mailbox: .sent)
    XCTAssertTrue(vm.messageThreads.isEmpty)
    await self.provider.pages.waitFor(3)
    try self.provider.pages.finish(2, .success(self.page([4])))
    await vm.waitForPresentation()
    try self.provider.pages.finish(1, .success(self.page([99])))
    await Task.yield()
    XCTAssertEqual(vm.messageThreads.map(\.id), [4])
    XCTAssertTrue(vm.loadingFooterIsHidden)
    XCTAssertFalse(vm.emptyStateIsVisible)
  }

  func testClearedSearchRejectsTransportThatIgnoresCancellation() async throws {
    let vm = MessagesSearchViewModel(feature: self.feature, sleep: { _ in })
    vm.configureWith(project: nil); vm.viewDidLoad()
    vm.searchTextChanged("old")
    await self.scheduler.advance()
    await self.provider.searches.waitFor(1)
    vm.clearSearchText()
    try self.provider.searches.finish(0, .success(self.page([99])))
    await self.feature.waitForOperations()
    await self.scheduler.advance()
    XCTAssertTrue(vm.messageThreads.isEmpty)
    vm.searchTextChanged("new")
    await self.scheduler.advance()
    await self.provider.searches.waitFor(2)
    try self.provider.searches.finish(1, .success(self.page([2])))
    await self.feature.waitForOperations()
    await vm.waitForSearch()
    XCTAssertEqual(vm.messageThreads.map(\.id), [2])
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
    let vm = MessagesSearchViewModel(feature: self.feature, sleep: { _ in })
    vm.configureWith(project: nil); vm.viewDidLoad()
    vm.searchTextChanged("first")
    await self.scheduler.advance()
    await self.provider.searches.waitFor(1)
    vm.searchTextChanged("second")
    await self.scheduler.advance()
    await self.provider.searches.waitFor(2)
    try self.provider.searches.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await Task.yield()
    XCTAssertTrue(vm.isSearching)
    try self.provider.searches.finish(1, .success(self.page([2])))
    await self.feature.waitForOperations()
    await vm.waitForSearch()
    XCTAssertFalse(vm.isSearching)
  }

  func testSendOrderDuplicateSharingAndDisposedObserversDoNotDropWrites() async throws {
    let subject = MessageSubject.project(id: 42, name: "Fixture")
    let first = self.feature.requestSend(body: "A", subject: subject)
    let duplicate = self.feature.requestSend(body: "A", subject: subject)
    let second = self.feature.requestSend(body: "B", subject: subject)
    let third = self.feature.requestSend(body: "A", subject: subject)
    let observer = Task { _ = await first.result }
    observer.cancel()
    await self.provider.sends.waitFor(1)
    XCTAssertEqual(self.provider.bodies, ["A"])
    try self.provider.sends.finish(0, .success(.template))
    await self.provider.sends.waitFor(2)
    XCTAssertEqual(self.provider.bodies, ["A", "B"])
    try self.provider.sends.finish(1, .success(.template))
    await self.provider.sends.waitFor(3)
    XCTAssertEqual(self.provider.bodies, ["A", "B", "A"])
    try self.provider.sends.finish(2, .success(.template))
    for command in [first, duplicate, second, third] { _ = try await command.value }
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
    vm.onPosted = { _ in posted += 1 }
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
    let delay = AccountRequestGate<Void>()
    defer { delay.releaseAll() }
    let vm = MessageDialogViewModel(feature: self.feature, sleep: { _ in try await delay.request() })
    var delivered = 0
    vm.onPosted = { _ in delivered += 1 }
    vm.configureWith(messageSubject: .project(id: 1, name: "Fixture"), context: .messages)
    vm.viewDidLoad(); vm.bodyTextChanged("Hello"); vm.postButtonPressed()
    await self.provider.sends.waitFor(1)
    try self.provider.sends.finish(0, .success(.template))
    await delay.waitFor(1)
    self.session.sessionChanged()
    try delay.finish(0, .success(()))
    await vm.waitForSend()
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

  func testCancelledReadCannotDeliverLateFailure() async throws {
    var events = 0
    let task = Task {
      do {
        _ = try await self.feature.thread(id: 42)
        guard !Task.isCancelled else { return }
        events += 1
      } catch {
        guard !Task.isCancelled else { return }
        events += 1
      }
    }
    await self.provider.threads.waitFor(1)
    task.cancel()
    try self.provider.threads.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await task.value
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
