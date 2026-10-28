import Combine
import GraphAPI
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import XCTest

@MainActor
final class ReportProjectInfoViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private var viewModel: ReportProjectInfoViewModel!
  private var cancellables = Set<AnyCancellable>()

  override func setUp() async throws {
    try await super.setUp()
    self.viewModel = ReportProjectInfoViewModel(feature: ProjectReportingFeature(
      sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
      makeProvider: { AsyncProjectReportingProvider(service: AppEnvironment.current.apiService) }
    ))
  }

  override func tearDown() async throws {
    self.cancellables.removeAll()
    try await super.tearDown()
  }

  func testListItems_IsEmpty_BeforeViewDidLoad() {
    XCTAssertTrue(self.viewModel.listItems.isEmpty)
  }

  func testListItems_IsPopulated_AfterSuccessfulFetch() async {
    let expectation = expectation(description: "listItems populated")

    AppEnvironment.pushEnvironment(apiService: MockService(fetchFlaggingOptionsResult: .success(.mock)))

    defer { AppEnvironment.popEnvironment() }

    self.viewModel.$listItems
      .filter { !$0.isEmpty }
      .first()
      .sink { items in
        XCTAssertFalse(items.isEmpty)

        expectation.fulfill()
      }
      .store(in: &self.cancellables)

    self.viewModel.viewDidLoad()

    await fulfillment(of: [expectation], timeout: 1.0)
  }

  func testListItems_IsEmpty_OnError() async {
    let expectation = expectation(description: "fetch completed")

    await withEnvironment(apiService: MockService(fetchFlaggingOptionsResult: .failure(.couldNotParseJSON))) {
      self.viewModel.$isLoading
        .filter { !$0 }
        .dropFirst()
        .first()
        .sink { _ in
          XCTAssertTrue(self.viewModel.listItems.isEmpty)
          expectation.fulfill()
        }
        .store(in: &self.cancellables)

      await self.viewModel.viewDidLoad().value
    }

    await fulfillment(of: [expectation], timeout: 1.0)
  }

  func testIsLoading_IsFalse_BeforeViewDidLoad() {
    XCTAssertFalse(self.viewModel.isLoading)
  }

  func testIsLoading_IsTrue_ThenFalse_AfterViewDidLoad() async {
    let expectation = expectation(description: "loading cycle complete")
    var states: [Bool] = []

    await withEnvironment(apiService: MockService(fetchFlaggingOptionsResult: .success(.mock))) {
      self.viewModel.$isLoading
        .sink { isLoading in
          states.append(isLoading)

          if states.count == 3 { /// false (initial value), true, false
            expectation.fulfill()
          }
        }
        .store(in: &self.cancellables)

      await self.viewModel.viewDidLoad().value
    }

    await fulfillment(of: [expectation], timeout: 1.0)
    XCTAssertEqual(states, [false, true, false])
  }

  func testIsLoading_ReturnsFalse_OnError() async {
    let expectation = expectation(description: "loading ends after error")

    await withEnvironment(apiService: MockService(fetchFlaggingOptionsResult: .failure(.couldNotParseJSON))) {
      self.viewModel.$isLoading
        .filter { !$0 }
        .dropFirst()
        .first()
        .sink { _ in expectation.fulfill() }
        .store(in: &self.cancellables)

      await self.viewModel.viewDidLoad().value
    }

    await fulfillment(of: [expectation], timeout: 1.0)
    XCTAssertFalse(self.viewModel.isLoading)
  }
}

// MARK: - Mock Data

private extension GraphAPI.FlaggingOptionsQuery.Data {
  static var mock: Self {
    .init(flaggingOptions: [
      .init(
        id: "project/post_funding_issues",
        parentId: nil,
        kind: nil,
        nodeType: .case(.group),
        title: "Post-funding issues",
        subtitle: "The project funded but something seems wrong.",
        placeholder: nil
      ),
      .init(
        id: "project/post_funding_issues/items_not_received",
        parentId: "project/post_funding_issues",
        kind: .case(.guidelinesViolation),
        nodeType: .case(.option),
        title: "Items not received",
        subtitle: "You haven't received your reward.",
        placeholder: "Describe what you expected to receive."
      ),
      .init(
        id: "project/post_funding_issues/bait_and_switch",
        parentId: "project/post_funding_issues",
        kind: .case(.guidelinesViolation),
        nodeType: .case(.option),
        title: "Bait and switch",
        subtitle: "The project changed significantly after funding.",
        placeholder: "Describe what changed."
      )
    ])
  }
}
