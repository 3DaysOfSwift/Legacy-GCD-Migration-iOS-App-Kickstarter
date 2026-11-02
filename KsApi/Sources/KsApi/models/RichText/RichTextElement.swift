import Foundation
import GraphAPI

/// Represents a single block-level element in a RichText list. Used to make implementing
/// the different views in SwiftUI more easily and with a consistent interface.
public indirect enum RichTextElement: Sendable, Equatable {
  case text(Text, HeaderLevel?)
  case listItemOpen
  case listItemClose
  case listItem(Text)
  case audio(Audio)
  case photo(Photo)
  case video(Video)
  case oembed(OEmbed)
  case unknown

  public struct Text: Sendable, Equatable {
    public let text: String
    public let link: URL?
    public let styles: [Style]
    public let children: [RichTextElement]

    public init(text: String, link: URL? = nil, styles: [Style] = [], children: [RichTextElement] = []) {
      self.text = text
      self.link = link
      self.styles = styles
      self.children = children
    }

    public enum Style: String, Sendable, Equatable {
      case strong = "STRONG"
      case emphasis = "EMPHASIS"
      case heading1 = "HEADING_1"
      case heading2 = "HEADING_2"
      case heading3 = "HEADING_3"
      case heading4 = "HEADING_4"

      public init?(rawValue: String) {
        switch rawValue {
        case "STRONG":
          self = .strong
        case "EMPHASIS":
          self = .emphasis
        case "HEADING_1":
          self = .heading1
        case "HEADING_2":
          self = .heading2
        case "HEADING_3":
          self = .heading3
        case "HEADING_4":
          self = .heading4
        default:
          assertionFailure("unknown style type: \(rawValue)")
          return nil
        }
      }
    }
  }

  public enum HeaderLevel: String, Sendable, Equatable {
    case one = "HEADING_1"
    case two = "HEADING_2"
    case three = "HEADING_3"
    case four = "HEADING_4"

    /// Create a HeaderLevel from an array of style strings from GraphQL, if
    /// one is present
    public init?(styles: [String]?) {
      for style in styles ?? [] {
        if let level = HeaderLevel(rawValue: style) {
          self = level
          return
        }
      }
      return nil
    }
  }

  public struct Audio: Sendable, Equatable {
    public let altText: String?
    public let assetID: String?
    public let caption: String?
    public let url: String?

    public init(altText: String?, assetID: String?, caption: String?, url: String?) {
      self.altText = altText
      self.assetID = assetID
      self.caption = caption
      self.url = url
    }
  }

  public struct Photo: Sendable, Equatable {
    public let altText: String?
    public let assetID: String?
    public let caption: String?
    public let url: String?

    /// The link this photo should navigate to when tapped. `RichTextPhoto` itself has no
    /// `link` field; the server represents a linkable image as a `RichText` node whose `link`
    /// wraps a `RichTextPhoto` child, so this is populated during normalization from the
    /// enclosing text's link rather than from the photo's own GraphQL fields.
    public let link: URL?

    public init(altText: String?, assetID: String?, caption: String?, url: String?, link: URL?) {
      self.altText = altText
      self.assetID = assetID
      self.caption = caption
      self.url = url
      self.link = link
    }
  }

  public struct VideoFormat: Sendable, Equatable {
    public let encoding: String
    public let height: String
    public let width: String
    public let profile: String
    public let url: String

    public init(encoding: String, height: String, width: String, profile: String, url: String) {
      self.encoding = encoding
      self.height = height
      self.width = width
      self.profile = profile
      self.url = url
    }
  }

  public struct Video: Sendable, Equatable {
    public let altText: String?
    public let assetID: String?
    public let caption: String?
    public let url: String?
    public let posterURL: String?
    public let formats: [VideoFormat]

    public init(altText: String?, assetID: String?, caption: String?, url: String?, posterURL: String?, formats: [VideoFormat]) {
      self.altText = altText
      self.assetID = assetID
      self.caption = caption
      self.url = url
      self.posterURL = posterURL
      self.formats = formats
    }
  }

  public struct OEmbed: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let version: String
    public let title: String
    public let type: String

    public let iframeUrl: String?
    public let originalUrl: String?

    public init(width: Int, height: Int, version: String, title: String, type: String, iframeUrl: String?, originalUrl: String?) {
      self.width = width
      self.height = height
      self.version = version
      self.title = title
      self.type = type
      self.iframeUrl = iframeUrl
      self.originalUrl = originalUrl
    }
  }
}
