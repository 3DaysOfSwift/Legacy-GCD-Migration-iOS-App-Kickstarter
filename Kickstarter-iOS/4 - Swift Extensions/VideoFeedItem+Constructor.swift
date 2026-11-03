import Foundation
import GraphAPI
import KsApi

/// Maps a `VideoFeedQuery` graph node to a `VideoFeedItem` to display in the video feed.
@MainActor
extension VideoFeedItem {
  init(node: VideoFeedQuery.Data.VideoFeed.Node) {
    self.init(response: VideoFeedResponse(node))
  }

  init(response: VideoFeedResponse) {
    self.init(
      id: response.id, pid: response.pid, slug: response.slug, projectURL: response.url,
      title: response.name, creator: response.creatorName,
      creatorImageURL: response.creatorImageURL.flatMap(URL.init(string:)),
      statsText: Self.statsTextInUserPreferredCurrency(
        pledgedAmount: response.pledged, currencyCode: response.currency, backersCount: response.backers),
      badges: response.badges.map {
        .init(type: .init(graphType: GraphAPI.BadgeTypeEnum(rawValue: $0.type)), text: $0.text, icon: $0.icon)
      },
      videoURL: response.videoURL.flatMap(URL.init(string:)),
      videoPreviewImageURL: response.previewURL.flatMap(URL.init(string:)),
      projectId: response.id, isSaved: response.isWatched, sharesCount: response.shares,
      watchesCount: response.watches, percentFunded: response.percentFunded
    )
  }

  /// Formats using a converted pledge amount in the user's preferred currency and a given backers count.
  static func statsTextInUserPreferredCurrency(
    pledgedAmount: Double,
    currencyCode: String,
    backersCount: Int
  ) -> String {
    let pledgedFormatted = Format.currency(
      pledgedAmount,
      currencyCode: currencyCode,
      omitCurrencyCode: true,
      maximumFractionDigits: 0,
      minimumFractionDigits: 0
    )

    return Strings.video_feed_campaign_subtitle(
      pledged: pledgedFormatted,
      backers: backersCount.toString()
    )
  }

}

private extension VideoFeedItem.BadgeType {
  init(graphType: GraphAPI.BadgeTypeEnum?) {
    switch graphType {
    case .projectWeLove:
      self = .projectWeLove
    case .daysLeft:
      self = .daysLeft
    case .justLaunched:
      self = .justLaunched
    case .trending:
      self = .trending
    default:
      self = .unknown
    }
  }
}
