import GraphAPI
import XCTest

@testable import Kickstarter_Framework
@testable import KsApi
@testable import Library

@MainActor
final class RichTextExampleProjectsViewModelTests: XCTestCase {
  private var item: DeveloperExamplesFeature.ProjectItem {
    .init(id: "one", name: "Example", richText: .init(items: []))
  }
  func testListFailureRetryAndReturnFromProjectUsesCachedList() async {
    let provider = ExamplesPresentationProvider()
    provider.listResult = .failure(
      NSError(
        domain: "Example", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Offline"]))
    let vm = RichTextExampleProjectsViewModel(feature: provider.feature())
    XCTAssertTrue(vm.isLoading)
    await vm.loadProjects()
    XCTAssertFalse(vm.isLoading)
    XCTAssertEqual(vm.errorMessage, "Offline")
    provider.listResult = .success([self.item])
    await vm.loadProjects()
    XCTAssertEqual(vm.projects, [self.item])
    XCTAssertNil(vm.errorMessage)
    vm.suspend()
    await vm.loadProjects()
    XCTAssertEqual(provider.listCount, 2)
  }
  func testInvalidAndMissingSlugsShowExistingErrorAndEditingClearsIt() async {
    let provider = ExamplesPresentationProvider()
    let vm = RichTextExampleProjectsViewModel(feature: provider.feature())
    await vm.submit(input: "", onSelect: { _ in XCTFail("Invalid slug selected") }).value
    XCTAssertTrue(vm.slugError)
    XCTAssertEqual(provider.lookupCount, 0)
    vm.clearLookup()
    XCTAssertFalse(vm.slugError)
    await vm.submit(input: "owner/project", onSelect: { _ in XCTFail("Missing project selected") })
      .value
    XCTAssertTrue(vm.slugError)
    XCTAssertEqual(provider.lookupCount, 1)
  }
  func testEquivalentSubmissionsSelectOnce() async {
    let provider = ExamplesPresentationProvider()
    let item = self.item
    provider.lookup = { item }
    let vm = RichTextExampleProjectsViewModel(feature: provider.feature())
    var selections: [String] = []
    let first = vm.submit(input: "owner/project", onSelect: { selections.append($0.id) })
    let second = vm.submit(input: "owner/project", onSelect: { selections.append($0.id) })
    XCTAssertEqual(first, second)
    await first.value
    await second.value
    XCTAssertEqual(provider.lookupCount, 1)
    XCTAssertEqual(selections, ["one"])
  }
  func testEditingAndClosingPreventLateNavigationOrError() async {
    let provider = ExamplesPresentationProvider()
    let vm = RichTextExampleProjectsViewModel(feature: provider.feature())
    for closing in [false, true] {
      let started = expectation(description: "Lookup suspended")
      var continuation: CheckedContinuation<DeveloperExamplesFeature.ProjectItem?, Never>?
      provider.lookup = {
        await withCheckedContinuation {
          continuation = $0
          started.fulfill()
        }
      }
      let task = vm.submit(
        input: "owner/project", onSelect: { _ in XCTFail("Obsolete navigation") })
      await fulfillment(of: [started], timeout: 2)
      if closing { vm.suspend() } else { vm.clearLookup() }
      continuation?.resume(returning: closing ? nil : self.item)
      await task.value
      XCTAssertFalse(vm.slugError)
    }
  }
}
