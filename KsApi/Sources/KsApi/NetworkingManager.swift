import Foundation

/// Native URLSession boundary. Services prepare requests and decode domain values;
/// this type owns only suspended transport and its system cancellation semantics.
public enum NetworkingManager {
  // Internal access is limited to retained service publisher compatibility adapters.
  static let session = URLSession(configuration: .default)

  public static func data(
    for request: URLRequest,
    delegate: (any URLSessionTaskDelegate)? = nil
  ) async throws -> (Data, URLResponse) {
    try await session.data(for: request, delegate: delegate)
  }

  public static func data(from url: URL) async throws -> Data {
    try await self.data(for: URLRequest(url: url)).0
  }
}
