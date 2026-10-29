import Apollo
import Foundation
import GraphAPI
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import ReactiveSwift
import XCTest

@MainActor
final class SearchRequestCancellationTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testSynchronousSuccessAndDuplicateCallbackCompleteOnce() async throws {
    let expected = try self.fixture()
    let token = CancellationProbe()
    let actual = try await CancellableGraphQLRequest.fetch { completion in
      completion(.success(self.response(expected)))
      completion(.failure(ProbeError.failed))
      return token
    }
    XCTAssertEqual(actual.projects?.totalCount, expected.projects?.totalCount)
    XCTAssertEqual(token.count, 0)
  }

  func testGraphQLErrorTakesPrecedenceOverPartialData() async throws {
    let data = try self.fixture()
    do {
      _ = try await CancellableGraphQLRequest.fetch { completion in
        completion(.success(GraphQLResult(
          data: data, extensions: nil,
          errors: [GraphQLError(["message": "Denied"])], source: .server, dependentKeys: nil
        )))
        return CancellationProbe()
      }
      XCTFail("Expected GraphQL failure, not partial success")
    } catch let error as ErrorEnvelope {
      XCTAssertEqual(error.ksrCode, .GraphQLError)
      XCTAssertEqual(error.errorMessages, ["Denied"])
    }
  }

  func testMissingDataAndTransportFailureKeepLegacyErrorMapping() async {
    for response: Result<GraphQLResult<GraphAPI.SearchQuery.Data>, Error> in [
      .success(self.response(nil)), .failure(ProbeError.failed)
    ] {
      do {
        _ = try await CancellableGraphQLRequest.fetch { completion in
          completion(response)
          return CancellationProbe()
        }
        XCTFail("Expected error")
      } catch let error as ErrorEnvelope {
        XCTAssertEqual(error.ksrCode, .JSONParsingFailed)
      } catch {
        XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testCancellationBeforeInvocationDoesNotStartRequest() async {
    let task = Task<GraphAPI.SearchQuery.Data, Error> { @MainActor in
      try await CancellableGraphQLRequest.fetch { _ in
        XCTFail("An already-cancelled task must not start transport")
        return CancellationProbe()
      }
    }
    task.cancel()
    await self.assertCancelled(task)
  }

  func testCancellationDuringRequestCancelsTokenAndIgnoresLateCallback() async {
    let started = expectation(description: "request started")
    let token = CancellationProbe()
    var callback: GraphQLResultHandler<GraphAPI.SearchQuery.Data>?
    let task = Task { @MainActor in
      try await CancellableGraphQLRequest.fetch { completion in
        callback = completion
        started.fulfill()
        return token
      }
    }
    defer { task.cancel() }
    await fulfillment(of: [started], timeout: 2)
    task.cancel()
    await self.assertCancelled(task)
    callback?(.failure(ProbeError.failed))
    XCTAssertEqual(token.count, 1)
  }

  func testLocationPayloadCancellationCancelsTokenAndRejectsLateCallback() async throws {
    let started = expectation(description: "location request started")
    let token = CancellationProbe()
    var callback: GraphQLResultHandler<GraphAPI.LocationsByTermQuery.Data>?
    let task = Task { @MainActor in
      try await CancellableGraphQLRequest.fetch { completion in
        callback = completion
        started.fulfill()
        return token
      }
    }
    defer { task.cancel() }
    await fulfillment(of: [started], timeout: 2)
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      XCTAssertEqual(token.count, 1)
    }
    callback?(.failure(ProbeError.failed))
    XCTAssertEqual(token.count, 1)
  }

  func testCancellationBeforeTokenRegistrationCancelsLateToken() async {
    // Exercise the registration race directly without a scheduling-dependent sleep.
    let pending = PendingGraphQLRequest<GraphAPI.SearchQuery.Data>()
    let token = CancellationProbe()
    do {
      let _: GraphAPI.SearchQuery.Data = try await withCheckedThrowingContinuation { continuation in
        XCTAssertTrue(pending.install(continuation))
        pending.cancel()
        pending.install(token)
        pending.complete(.failure(ProbeError.failed))
        pending.cancel()
      }
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      XCTAssertEqual(token.count, 1)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testCancellationBeforeContinuationRegistrationResumesIt() async {
    let pending = PendingGraphQLRequest<GraphAPI.SearchQuery.Data>()
    pending.cancel()
    do {
      let _: GraphAPI.SearchQuery.Data = try await withCheckedThrowingContinuation { continuation in
        XCTAssertFalse(pending.install(continuation))
      }
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      // Successful completion of this await establishes no orphaned continuation.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testAsyncProviderUsesMockDataAndRecoversAfterFailure() async throws {
    let expected = try self.fixture()
    let provider = AsyncSearchProjectsProvider()
    await self.withEnvironment(apiService: MockService()) {
      do {
        _ = try await provider.fetchPage(parameters: .defaults, cursor: nil)
        XCTFail("Expected missing mock response to fail")
      } catch {
        XCTAssertTrue(error is ErrorEnvelope)
      }
    }
    await self.withEnvironment(apiService: MockService(fetchGraphQLResponses: [
      (GraphAPI.SearchQuery.self, expected)
    ])) {
      do {
        let data = try await provider.fetchPage(parameters: .defaults, cursor: nil)
        XCTAssertEqual(data.projects?.totalCount, expected.projects?.totalCount)
      } catch {
        XCTFail("Expected recovery: \(error)")
      }
    }
  }

  func testLiveProviderAdapterPublishesThroughFeature() async throws {
    let expected = try self.fixture()
    await self.withEnvironment(
      apiService: MockService(fetchGraphQLResponses: [(GraphAPI.SearchQuery.self, expected)]),
      scheduler: QueueScheduler.main
    ) {
      let feature = SearchFeature(provider: AsyncSearchProjectsProvider())
      let loaded = self.expectation(description: "async Feature result")
      let observation = feature.paginatedResults.observeValues { projects in
        XCTAssertEqual(projects.count, 5)
        loaded.fulfill()
      }
      defer { observation?.dispose() }
      await feature.search(parameters: .defaults)
      await self.fulfillment(of: [loaded], timeout: 2)
      XCTAssertEqual(feature.projects.count, 5)
      XCTAssertNil(feature.searchError)
    }
  }

  private func assertCancelled(_ task: Task<GraphAPI.SearchQuery.Data, Error>) async {
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testFeatureReplacementCancelsTransportAndSuppressesLateResult() async throws {
    let expected = try self.fixture()
    let firstStarted = expectation(description: "first transport")
    let secondStarted = expectation(description: "replacement transport")
    let firstCancelled = expectation(description: "obsolete transport cancelled")
    let loaded = expectation(description: "replacement result")
    let firstToken = CancellationProbe(onCancel: { firstCancelled.fulfill() })
    var callbacks: [GraphQLResultHandler<GraphAPI.SearchQuery.Data>] = []
    let provider = AsyncSearchProjectsProvider { _, _ in
      try await CancellableGraphQLRequest.fetch { completion in
        callbacks.append(completion)
        if callbacks.count == 1 {
          firstStarted.fulfill()
          return firstToken
        }
        secondStarted.fulfill()
        return CancellationProbe()
      }
    }
    await self.withEnvironment(debounceInterval: .seconds(0), scheduler: QueueScheduler.main) {
      let feature = SearchFeature(provider: provider)
      var resultEvents = 0
      let observation = feature.paginatedResults.observeValues { _ in
        resultEvents += 1
        loaded.fulfill()
      }
      defer {
        observation?.dispose()
        for callback in callbacks { callback(.failure(ProbeError.failed)) }
      }
      var parameters = DiscoveryParams.defaults
      parameters.query = "old"
      let firstTask = feature.requestSearch(parameters: parameters)
      await self.fulfillment(of: [firstStarted], timeout: 2)
      parameters.query = "new"
      let secondTask = feature.requestSearch(parameters: parameters)
      await self.fulfillment(of: [firstCancelled, secondStarted], timeout: 2)
      guard callbacks.count == 2 else {
        XCTFail("Expected exactly two transports")
        return
      }
      callbacks[1](.success(self.response(expected)))
      await self.fulfillment(of: [loaded], timeout: 2)
      callbacks[0](.success(self.response(nil)))
      XCTAssertEqual(firstToken.count, 1)
      XCTAssertEqual(resultEvents, 1)
      XCTAssertEqual(feature.parameters?.query, "new")
      XCTAssertEqual(feature.projects.count, 5)
      XCTAssertNil(feature.searchError)
      await firstTask.value
      await secondTask.value
    }
  }

  func testMappedResponseReturnsSnapshotAndIgnoresDuplicateCompletion() async throws {
    let data = try self.fixture()
    let token = CancellationProbe()
    let count: Int? = try await CancellableGraphQLRequest.fetch(start: { completion in
      completion(.success(self.response(data)))
      completion(.failure(ProbeError.failed))
      return token
    }, map: { $0.projects?.totalCount })
    XCTAssertEqual(count, data.projects?.totalCount)
    XCTAssertEqual(token.count, 0)
  }

  func testMappedResponsePreservesConversionFailure() async throws {
    let data = try self.fixture()
    do {
      let _: Int = try await CancellableGraphQLRequest.fetch(start: { completion in
        completion(.success(self.response(data)))
        return CancellationProbe()
      }, map: { _ in throw ProbeError.failed })
      XCTFail("Expected conversion failure")
    } catch ProbeError.failed {
      // The conversion error reaches the caller unchanged.
    }
  }

  func testMappedResponseRejectsGraphQLErrorBeforeConversion() async throws {
    let data = try self.fixture()
    do {
      let _: Int = try await CancellableGraphQLRequest.fetch(start: { completion in
        completion(.success(GraphQLResult(
          data: data, extensions: nil,
          errors: [GraphQLError(["message": "Denied"])], source: .server, dependentKeys: nil
        )))
        return CancellationProbe()
      }, map: { _ in
        XCTFail("Partial GraphQL data must not be converted into success")
        return 0
      })
      XCTFail("Expected GraphQL failure")
    } catch let error as ErrorEnvelope {
      XCTAssertEqual(error.ksrCode, .GraphQLError)
      XCTAssertEqual(error.errorMessages, ["Denied"])
    }
  }

  func testMappedResponseCancellationRejectsLateSuccess() async throws {
    let data = try self.fixture()
    let started = expectation(description: "mapped request started")
    let token = CancellationProbe()
    var callback: GraphQLResultHandler<GraphAPI.SearchQuery.Data>?
    let task = Task<Int?, Error> { @MainActor in
      try await CancellableGraphQLRequest.fetch(start: { completion in
        callback = completion
        started.fulfill()
        return token
      }, map: { $0.projects?.totalCount })
    }
    defer { task.cancel() }
    await fulfillment(of: [started], timeout: 2)
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      XCTAssertEqual(token.count, 1)
    }
    callback?(.success(self.response(data)))
    XCTAssertEqual(token.count, 1)
  }

  private func fixture() throws -> GraphAPI.SearchQuery.Data {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: "SearchQuery_FiveResults", withExtension: "json"
    ))
    return try testGraphObject(fromResource: url)
  }

  private func response(
    _ data: GraphAPI.SearchQuery.Data?
  ) -> GraphQLResult<GraphAPI.SearchQuery.Data> {
    GraphQLResult(data: data, extensions: nil, errors: nil, source: .server, dependentKeys: nil)
  }
}

private enum ProbeError: Error { case failed }

/// Cancellation can arrive from any executor; the probe follows that contract.
private final class CancellationProbe: Cancellable {
  private let lock = NSLock()
  private var cancellationCount = 0
  private let onCancel: (() -> Void)?
  init(onCancel: (() -> Void)? = nil) { self.onCancel = onCancel }
  var count: Int {
    self.lock.lock()
    defer { self.lock.unlock() }
    return self.cancellationCount
  }
  func cancel() {
    self.lock.lock()
    self.cancellationCount += 1
    self.lock.unlock()
    self.onCancel?()
  }
}
