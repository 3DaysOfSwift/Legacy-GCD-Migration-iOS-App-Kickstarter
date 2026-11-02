import GraphAPI

public struct RichTextExampleResponse: Sendable, Identifiable, Hashable {
  public let id: String
  public let name: String
  public let richText: [RichTextElement]

  public init(id: String, name: String, richText: RichTextComponentFragment) {
    self.id = id
    self.name = name
    self.richText = richText.asRichTextElements()
  }

  public func hash(into hasher: inout Hasher) { hasher.combine(self.id) }

  public static func projects(_ data: RichTextExampleProjectsQuery.Data) -> [Self] {
    (data.projects?.nodes ?? []).compactMap { $0 }.map {
      Self(id: $0.id, name: $0.name, richText: $0.storyRichText.fragments.richTextComponentFragment)
    }
  }

  public static func project(_ data: RichTextExampleProjectBySlugQuery.Data) -> Self? {
    data.project.map {
      Self(id: $0.id, name: $0.name, richText: $0.storyRichText.fragments.richTextComponentFragment)
    }
  }
}
