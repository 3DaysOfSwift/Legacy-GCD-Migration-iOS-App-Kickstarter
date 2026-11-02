import GraphAPI

/// Raw display inputs; localized currency formatting remains in the UI adapter.
public struct VideoFeedResponse: Sendable {
  public let id: String
  public let pid: Int
  public let slug: String
  public let url: String
  public let name: String
  public let creatorName: String
  public let creatorImageURL: String?
  public let videoURL: String?
  public let previewURL: String?
  public let pledged: Double
  public let currency: String
  public let backers: Int
  public let isWatched: Bool
  public let shares: Int
  public let watches: Int
  public let percentFunded: Int
  public let badges: [Badge]

  public struct Badge: Sendable {
    public let type: String
    public let text: String
    public let icon: String?
  }

  public init(_ node: GraphAPI.VideoFeedQuery.Data.VideoFeed.Node) {
    let project = node.project
    self.id = project.id
    self.pid = project.pid
    self.slug = project.slug
    self.url = project.url
    self.name = project.name
    self.creatorName = project.creator?.name ?? ""
    self.creatorImageURL = project.creator?.imageUrl
    self.videoURL = project.verticalVideo?.videoSources?.hls?.src
    self.previewURL = project.verticalVideo?.previewImageUrl
    self.pledged = (project.pledged.amount.flatMap(Double.init) ?? 0) * Double(project.fxRate)
    self.currency = project.fxRateCurrency.rawValue
    self.backers = project.backersCount
    self.isWatched = project.isWatched
    self.shares = project.sharesCount
    self.watches = project.watchesCount ?? 0
    self.percentFunded = project.percentFunded
    self.badges = node.badges.map { Badge(type: $0.type.rawValue, text: $0.text, icon: $0.icon) }
  }
}
