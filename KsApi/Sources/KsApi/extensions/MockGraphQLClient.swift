import Apollo
import ApolloAPI
import Combine
import Foundation

class MockGraphQLClient: ApolloClientType {
  // MARK: - Base Properties

  var client: ApolloClient {
    let url = URL(string: "https://kickstarter.com")!

    return ApolloClient(url: url)
  }

  static let shared = MockGraphQLClient()


}

/** Implementation of optional `fetch` and `perform` with `result` useful for mocking data.
 */
extension ApolloClientType {
  public func fetchWithResult<Query: GraphQLQuery, Data: Decodable>(
    query _: Query,
    result: Result<Data, ErrorEnvelope>?
  ) -> AnyPublisher<Data, ErrorEnvelope> {
    return producer(for: result)
  }

  public func performWithResult<Mutation: GraphQLMutation, Data: Decodable>(
    mutation _: Mutation,
    result: Result<Data, ErrorEnvelope>?
  ) -> AnyPublisher<Data, ErrorEnvelope> {
    return producer(for: result)
  }


}

private func producer<T, E>(for property: Result<T, E>?) -> AnyPublisher<T, E> {
  switch property {
  case let .success(data): return CurrentValueSubject(data).eraseToAnyPublisher()
  case let .failure(error): return Fail(error: error).eraseToAnyPublisher()
  case .none: return Empty(completeImmediately: false).eraseToAnyPublisher()
  }
}

private extension Result {
  var value: Success? {
    switch self {
    case let .success(value): return value
    case .failure: return nil
    }
  }

  var error: Failure? {
    switch self {
    case .success: return nil
    case let .failure(error): return error
    }
  }
}
