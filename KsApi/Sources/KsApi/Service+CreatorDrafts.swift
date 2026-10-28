import Foundation

extension Service {
  @MainActor public func creatorDraft(project: Project) async throws -> UpdateDraft {
    try await self.discussionResponse(route: .fetchUpdateDraft(forProject: project))
  }
  @MainActor public func saveCreatorDraft(
    _ draft: UpdateDraft, title: String, body: String, isPublic: Bool
  ) async throws -> UpdateDraft {
    try await self.discussionResponse(route: .updateUpdateDraft(draft, title: title, body: body, isPublic: isPublic))
  }
  @MainActor public func removeCreatorDraftImage(
    _ image: UpdateDraft.Image, draft: UpdateDraft
  ) async throws -> UpdateDraft.Image {
    try await self.discussionResponse(route: .deleteImage(image, fromDraft: draft))
  }
  @MainActor public func addCreatorDraftImage(file: URL, draft: UpdateDraft) async throws -> UpdateDraft.Image {
    let request = try self.preparedRouteRequest(.addImage(fileUrl: file, toDraft: draft))
    return try await Self.uploadDraftImage(file: file, request: request)
  }

  // File reading and multipart construction run off the UI actor. The legacy
  // route/authentication and image field are retained; unreadable files throw.
  @concurrent private static func uploadDraftImage(
    file: URL, request: URLRequest
  ) async throws -> UpdateDraft.Image {
    let prepared = try Self.preparedDraftImageRequest(file: file, request: request)
    let data: Data
    let response: URLResponse
    do { (data, response) = try await URLSession.shared.data(for: prepared) }
    catch {
      try Task.checkCancellation()
      throw ErrorEnvelope.couldNotParseErrorEnvelopeJSON
    }
    try Task.checkCancellation()
    return try Self.decodeDiscoveryResponse(data, response: response)
  }

  internal static func preparedDraftImageRequest(file: URL, request: URLRequest) throws -> URLRequest {
    try Task.checkCancellation()
    guard file.isFileURL else { throw ErrorEnvelope.couldNotParseJSON }
    let image = try Data(contentsOf: file)
    guard !image.isEmpty, let mime = file.imageMime ?? image.imageMime else { throw ErrorEnvelope.couldNotParseJSON }
    let boundary = "kickstarter-\(UUID().uuidString)"
    let filename = file.lastPathComponent.replacingOccurrences(of: "\"", with: "_")
      .replacingOccurrences(of: "\r", with: "_").replacingOccurrences(of: "\n", with: "_")
    var body = Data(("--\(boundary)\r\n" +
      "Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n" +
      "Content-Type: \(mime)\r\n\r\n").utf8)
    body.append(image)
    body.append(Data("\r\n--\(boundary)--\r\n".utf8))
    try Task.checkCancellation()
    var prepared = request
    prepared.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    prepared.httpBody = body
    return prepared
  }
}
