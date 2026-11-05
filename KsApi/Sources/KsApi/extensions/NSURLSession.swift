import Combine
import Foundation
import Prelude

private func parseJSONData(_ data: Data) -> Any? {
  return (try? JSONSerialization.jsonObject(with: data, options: []))
}

internal extension URLSession {
  private func isValidResponse(response: HTTPURLResponse) -> Bool {
    guard (200..<300).contains(response.statusCode),
          let headers = response.allHeaderFields as? [String: String],
          let contentType = headers["Content-Type"], contentType.hasPrefix("application/json") else {
      return false
    }

    return true
  }

  func combine_dataResponse(
    _ request: URLRequest,
    uploading file: (url: URL, name: String)? = nil
  ) -> AnyPublisher<
    Data,
    ErrorEnvelope
  > {
    let producer = file != nil ? self
      .combine_requestWithFileUpload(request, uploading: file!.url, named: file!.name) :
      DataTaskPublisher(request: request, session: self).eraseToAnyPublisher()

    return producer
      .mapError { _ in ErrorEnvelope.couldNotParseErrorEnvelopeJSON }
      .flatMap { (data: Data, response: URLResponse) -> AnyPublisher<Data, ErrorEnvelope> in
        guard let response = response as? HTTPURLResponse else {
          fatalError()
        }

        guard self.isValidResponse(response: response) else {
          if let json = parseJSONData(data) as? [String: Any] {
            do {
              let envelope: ErrorEnvelope = try ErrorEnvelope.decodeJSONDictionary(json)
              return Fail<Data, ErrorEnvelope>(error: envelope).eraseToAnyPublisher()
            } catch {
              return Fail<Data, ErrorEnvelope>(error: .couldNotDecodeJSON(error)).eraseToAnyPublisher()
            }

          } else {
            return Fail<Data, ErrorEnvelope>(error: .couldNotParseErrorEnvelopeJSON).eraseToAnyPublisher()
          }
        }
        return Just(data).setFailureType(to: ErrorEnvelope.self).eraseToAnyPublisher()

      }.eraseToAnyPublisher()
  }


}

private let boundary = "k1ck574r73r154c0mp4ny"

extension URLSession {
  private func requestWithFileUpload(
    _ request: URLRequest,
    uploading file: URL,
    named name: String
  ) -> URLRequest {
    var mutableRequest = request

    guard
      let data = try? Data(contentsOf: file),
      let mime = file.imageMime ?? data.imageMime,
      let multipartHead = (
        "--\(boundary)\r\n"
          + "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(file.lastPathComponent)\"\r\n"
          + "Content-Type: \(mime)\r\n\r\n"
      ).data(using: .utf8),
      let multipartTail = "--\(boundary)--\r\n".data(using: .utf8)
    else { fatalError() }

    var body = Data()
    body.append(multipartHead)
    body.append(data)
    body.append(multipartTail)

    mutableRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    mutableRequest.httpBody = body

    return mutableRequest
  }

  private func combine_requestWithFileUpload(
    _ request: URLRequest,
    uploading file: URL,
    named name: String
  ) -> AnyPublisher<
    (data: Data, response: URLResponse),
    URLError
  > {
    let finalRequest = self.requestWithFileUpload(request, uploading: file, named: name)

    let subject = PassthroughSubject<(Data, URLResponse), Error>()

    return DataTaskPublisher(request: finalRequest, session: self).eraseToAnyPublisher()
  }
}
