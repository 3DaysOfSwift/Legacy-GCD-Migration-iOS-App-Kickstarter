import Foundation
import Prelude
import ReactiveExtensions

extension Service {
  // MARK: - Swift.Codable

  func decodeModelToResult<T: Decodable>(data json: Data, ofType type: T.Type) -> Result<T?, ErrorEnvelope> {
    do {
      let decodedObject = try JSONDecoder().decode(type, from: json)
      return .success(decodedObject)
    } catch {
      return .failure(.couldNotDecodeJSON(error))
    }
  }
}
