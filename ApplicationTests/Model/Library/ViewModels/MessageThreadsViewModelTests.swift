@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class MessageThreadsViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = MessagingFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncMessagingProvider(service: AppEnvironment.current.apiService) },
    sleep: { _ in }
  )
  private lazy var vm = MessageThreadsViewModel(feature: self.feature)

  func testLoadingRefreshingAndSwitchingMailbox() async {
    self.vm.configureWith(project: nil, refTag: nil)
    self.vm.viewDidLoad()
    XCTAssertFalse(self.vm.loadingFooterIsHidden)
    XCTAssertEqual(self.vm.mailboxName, Strings.messages_navigation_inbox())
    await self.settle()
    XCTAssertTrue(self.vm.loadingFooterIsHidden)
    XCTAssertFalse(self.vm.messageThreads.isEmpty)
    XCTAssertFalse(self.vm.emptyStateIsVisible)
    self.vm.refresh()
    XCTAssertTrue(self.vm.messageThreads.isEmpty)
    XCTAssertTrue(self.vm.isRefreshing)
    await self.settle()
    XCTAssertFalse(self.vm.isRefreshing)
    XCTAssertFalse(self.vm.messageThreads.isEmpty)
    self.vm.switchTo(mailbox: .sent)
    XCTAssertEqual(self.vm.mailboxName, Strings.messages_navigation_sent())
    XCTAssertTrue(self.vm.messageThreads.isEmpty)
    await self.settle()
    XCTAssertFalse(self.vm.messageThreads.isEmpty)
    XCTAssertTrue(self.vm.loadingFooterIsHidden)
  }

  func testEmptyStateAndNavigation() async {
    await withEnvironment(apiService: MockService(fetchMessageThreadsResponse: [])) {
      var search = 0
      var chooser = 0
      self.vm.onSearch = { search += 1 }
      self.vm.onMailboxChooser = { chooser += 1 }
      self.vm.viewDidLoad()
      await self.settle()
      XCTAssertTrue(self.vm.emptyStateIsVisible)
      self.vm.willDisplayRow(0, outOf: 1)
      XCTAssertTrue(self.vm.loadingFooterIsHidden)
      self.vm.searchButtonPressed()
      self.vm.mailboxButtonPressed()
      XCTAssertEqual(search, 1)
      XCTAssertEqual(chooser, 1)
    }
  }

  private func settle() async {
    await self.feature.waitForOperations()
    await self.vm.waitForPresentation()
  }

  override func tearDown() async throws {
    self.feature.reset()
    await self.feature.waitForOperations()
    try await super.tearDown()
  }
}
