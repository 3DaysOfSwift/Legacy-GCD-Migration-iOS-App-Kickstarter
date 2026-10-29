import GraphAPI
import Prelude
import XCTest

@testable import Kickstarter_Framework
@testable import KsApi
@testable import Library

@MainActor
final class PaginationExampleViewModelTests: XCTestCase {
  func testLoadRefreshAndPaginationDisplayExistingMessages() async throws {
    let provider = ExamplesPresentationProvider()
    let vm = PaginationExampleViewModel(feature: provider.feature())
    await vm.load()
    XCTAssertEqual(vm.projects.map(\.id), [Project.template.id])
    XCTAssertEqual(vm.statusText, "Got 1 results; more are available")
    XCTAssertTrue(vm.showProgressView)
    await vm.loadNextPage()
    XCTAssertEqual(vm.projects.count, 2)
    await vm.refresh()
    XCTAssertEqual(vm.projects.count, 1)
    XCTAssertEqual(provider.parameters.last?.staffPicks, true)
    XCTAssertEqual(provider.parameters.last?.sort, .magic)
  }
  func testFailureAndRetryAreVisible() async {
    let provider = ExamplesPresentationProvider()
    provider.pageResult = .failure(ErrorEnvelope.graphError("Offline"))
    let vm = PaginationExampleViewModel(feature: provider.feature())
    await vm.load()
    XCTAssertEqual(vm.statusText, "Error: Offline")
    XCTAssertFalse(vm.showProgressView)
    provider.pageResult = .success(.template |> DiscoveryEnvelope.lens.projects .~ [])
    await vm.refresh()
    XCTAssertEqual(vm.statusText, "No results")
  }
  func testTerminalPageStopsSpinnerAndDoesNotStartAnotherRequest() async {
    let provider = ExamplesPresentationProvider()
    let vm = PaginationExampleViewModel(feature: provider.feature())
    await vm.load()
    provider.pageResult = .success(.template |> DiscoveryEnvelope.lens.projects .~ [])
    await vm.loadNextPage()
    XCTAssertEqual(vm.projects.count, 1)
    XCTAssertEqual(vm.statusText, "Loaded all results")
    XCTAssertFalse(vm.showProgressView)
    let requestCount = provider.parameters.count
    await vm.loadNextPage()
    XCTAssertEqual(provider.parameters.count, requestCount)
  }
}

@MainActor
final class ExamplesPresentationProvider: DeveloperExamplesProvider {
  var pageResult: Result<DiscoveryEnvelope, Error> = .success(
    .template |> DiscoveryEnvelope.lens.projects .~ [.template])
  var listResult: Result<[DeveloperExamplesFeature.ProjectItem], Error> = .success([])
  var lookup: () async throws -> DeveloperExamplesFeature.ProjectItem? = { nil }
  var parameters: [DiscoveryParams] = []
  var listCount = 0
  var lookupCount = 0
  func feature() -> DeveloperExamplesFeature {
    DeveloperExamplesFeature(
      sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }
      ),
      makeProvider: { self })
  }
  func page(parameters: DiscoveryParams, cursor: String?) async throws -> DiscoveryEnvelope {
    self.parameters.append(parameters)
    return try self.pageResult.get()
  }
  func projects() async throws -> [DeveloperExamplesFeature.ProjectItem] {
    self.listCount += 1
    return try self.listResult.get()
  }
  func project(slug: String) async throws -> DeveloperExamplesFeature.ProjectItem? {
    self.lookupCount += 1
    return try await self.lookup()
  }
}
