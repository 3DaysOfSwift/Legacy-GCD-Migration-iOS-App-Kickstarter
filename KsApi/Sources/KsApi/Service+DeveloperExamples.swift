import GraphAPI

extension Service {
  @MainActor public func richTextExampleProjects() async throws -> [RichTextExampleResponse] {
    try await self.cancellableQuery(
      RichTextExampleProjectsQuery(storyRichText: true),
      map: { RichTextExampleResponse.projects($0) })
  }

  @MainActor public func richTextExampleProject(slug: String) async throws -> RichTextExampleResponse? {
    try await self.cancellableQuery(
      RichTextExampleProjectBySlugQuery(slug: slug, storyRichText: true),
      map: { RichTextExampleResponse.project($0) })
  }
}
