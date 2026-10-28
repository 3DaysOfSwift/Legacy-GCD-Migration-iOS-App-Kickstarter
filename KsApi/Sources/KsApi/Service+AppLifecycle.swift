extension Service {
  @MainActor public func applicationConfiguration() async throws -> Config {
    try await self.discussionResponse(route: .config)
  }
  @MainActor public func applicationSurvey(id: Int) async throws -> SurveyResponse {
    try await self.discussionResponse(route: .surveyResponse(surveyResponseId: id))
  }
  @MainActor public func registerApplicationPushToken(_ token: String) async throws {
    let _: VoidEnvelope = try await self.discussionResponse(route: .registerPushToken(token))
  }
}
