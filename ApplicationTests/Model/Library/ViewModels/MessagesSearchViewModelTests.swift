@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class MessagesSearchViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = MessagingFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncMessagingProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = MessagesSearchViewModel(feature: self.feature, sleep: { _ in })

  func testSearchAndClear() async {
    self.vm.configureWith(project: nil)
    self.vm.viewDidLoad()
    self.vm.viewWillAppear()
    self.vm.searchTextChanged("hello")
    XCTAssertTrue(self.vm.isSearching)
    await self.vm.waitForSearch()
    XCTAssertFalse(self.vm.isSearching)
    XCTAssertFalse(self.vm.messageThreads.isEmpty)
    self.vm.clearSearchText()
    XCTAssertTrue(self.vm.messageThreads.isEmpty)
    XCTAssertFalse(self.vm.isSearching)
  }

  func testClearBeforeRequestCompletesAndNavigation() async {
    var navigated: MessageThread?
    self.vm.onMessageThread = { navigated = $0 }
    self.vm.viewDidLoad()
    self.vm.searchTextChanged("hello")
    self.vm.clearSearchText()
    await self.vm.waitForSearch()
    XCTAssertTrue(self.vm.messageThreads.isEmpty)
    XCTAssertFalse(self.vm.isSearching)
    let thread = MessageThread.template
    self.vm.tappedMessageThread(thread)
    XCTAssertEqual(navigated, thread)
  }

  func testDisappearingCancelsPendingSearch() async {
    self.vm.viewDidLoad()
    self.vm.searchTextChanged("hello")
    self.vm.viewWillDisappear()
    await self.vm.waitForSearch()
    XCTAssertTrue(self.vm.messageThreads.isEmpty)
    XCTAssertFalse(self.vm.isSearching)
  }
}
