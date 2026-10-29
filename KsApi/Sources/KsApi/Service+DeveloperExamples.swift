import GraphAPI

extension Service {
  @MainActor public func richTextExampleProjects() async throws -> RichTextExampleProjectsQuery.Data
  {
    try await self.cancellableQuery(RichTextExampleProjectsQuery(storyRichText: true))
  }
  @MainActor public func richTextExampleProject(slug: String) async throws
    -> RichTextExampleProjectBySlugQuery.Data
  {
    try await self.cancellableQuery(
      RichTextExampleProjectBySlugQuery(slug: slug, storyRichText: true))
  }
}
