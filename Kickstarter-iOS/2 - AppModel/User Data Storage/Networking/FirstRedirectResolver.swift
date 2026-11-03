import Foundation
import KsApi

/// The SDK requires a delegate to stop redirects. It has no mutable state or UI
/// callbacks; native URLSession async transport owns completion and cancellation.
public final class FirstRedirectResolver: NSObject, URLSessionTaskDelegate {
  public static func resolve(_ url: URL) async throws -> URL? {
    let (_, response) = try await NetworkingManager.data(
      for: URLRequest(url: url), delegate: FirstRedirectResolver()
    )
    try Task.checkCancellation()
    return self.destination(in: response)
  }
  static func destination(in response: URLResponse) -> URL? {
    guard let response = response as? HTTPURLResponse,
      [301, 302, 303, 307, 308].contains(response.statusCode),
      let location = response.value(forHTTPHeaderField: "Location"), !location.isEmpty,
      let base = response.url else { return nil }
    return URL(string: location, relativeTo: base)?.absoluteURL
  }
  public func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
