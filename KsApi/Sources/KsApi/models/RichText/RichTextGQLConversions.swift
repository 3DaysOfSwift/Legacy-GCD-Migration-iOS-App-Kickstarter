import Foundation
import GraphAPI

extension RichTextComponentFragment {
  public func asRichTextElements() -> [RichTextElement] {
    (self.items ?? []).map { $0.asRichTextElement }.withNormalizedNestedElements()
  }
}

extension RichTextComponentFragment.Item {
  public var asRichTextElement: RichTextElement {
    if let x = asRichText { return x.asRichTextElement }
    if let x = asRichTextHeader { return x.asRichTextElement }
    if let x = asRichTextListItem { return x.asRichTextElement }
    if let x = asRichTextListOpen { return x.asRichTextElement }
    if let x = asRichTextListClose { return x.asRichTextElement }
    if let x = asRichTextPhoto { return x.asRichTextElement }
    if let x = asRichTextAudio { return x.asRichTextElement }
    if let x = asRichTextVideo { return x.asRichTextElement }
    if let x = asRichTextOembed { return x.asRichTextElement }
    assertionFailure("Could not detect a usable rich text element")
    return RichTextElement.unknown
  }
}

extension RichTextComponentFragment.Item.AsRichText.Child {
  public var asRichTextElement: RichTextElement {
    if let x = asRichText { return x.asRichTextElement }
    if let x = asRichTextHeader { return x.asRichTextElement }
    if let x = asRichTextListItem { return x.asRichTextElement }
    if let x = asRichTextListOpen { return x.asRichTextElement }
    if let x = asRichTextListClose { return x.asRichTextElement }
    if let x = asRichTextPhoto { return x.asRichTextElement }
    if let x = asRichTextAudio { return x.asRichTextElement }
    if let x = asRichTextVideo { return x.asRichTextElement }
    if let x = asRichTextOembed { return x.asRichTextElement }
    assertionFailure("Could not detect a usable rich text element")
    return RichTextElement.unknown
  }
}

extension RichTextComponentFragment.Item.AsRichTextHeader.Child {
  public var asRichTextElement: RichTextElement {
    if let x = asRichText { return x.asRichTextElement }
    if let x = asRichTextHeader { return x.asRichTextElement }
    if let x = asRichTextListItem { return x.asRichTextElement }
    if let x = asRichTextListOpen { return x.asRichTextElement }
    if let x = asRichTextListClose { return x.asRichTextElement }
    if let x = asRichTextPhoto { return x.asRichTextElement }
    if let x = asRichTextAudio { return x.asRichTextElement }
    if let x = asRichTextVideo { return x.asRichTextElement }
    if let x = asRichTextOembed { return x.asRichTextElement }
    assertionFailure("Could not detect a usable rich text element")
    return RichTextElement.unknown
  }
}

extension RichTextComponentFragment.Item.AsRichTextListItem.Child {
  public var asRichTextElement: RichTextElement {
    if let x = asRichText { return x.asRichTextElement }
    if let x = asRichTextHeader { return x.asRichTextElement }
    if let x = asRichTextListItem { return x.asRichTextElement }
    if let x = asRichTextListOpen { return x.asRichTextElement }
    if let x = asRichTextListClose { return x.asRichTextElement }
    if let x = asRichTextPhoto { return x.asRichTextElement }
    if let x = asRichTextAudio { return x.asRichTextElement }
    if let x = asRichTextVideo { return x.asRichTextElement }
    if let x = asRichTextOembed { return x.asRichTextElement }
    assertionFailure("Could not detect a usable rich text element")
    return RichTextElement.unknown
  }
}

extension RichTextComponentFragment.Item.AsRichText {
  public var asRichTextElement: RichTextElement {
    let children = (children ?? []).map { $0.asRichTextElement }
    return .text(makeText(text: text, link: link, styles: styles, children: children), nil)
  }
}

extension RichTextComponentFragment.Item.AsRichText.Child.AsRichText {
  public var asRichTextElement: RichTextElement {
    .text(makeText(text: text, link: link, styles: styles, children: []), nil)
  }
}

extension RichTextComponentFragment.Item.AsRichText.Child.AsRichTextHeader {
  public var asRichTextElement: RichTextElement {
    .text(makeText(text: text, link: link, styles: styles, children: []), .init(styles: styles))
  }
}

extension RichTextComponentFragment.Item.AsRichText.Child.AsRichTextListItem {
  public var asRichTextElement: RichTextElement {
    .listItem(makeText(text: text, link: link, styles: styles, children: []))
  }
}

extension RichTextComponentFragment.Item.AsRichTextHeader {
  public var asRichTextElement: RichTextElement {
    let children = (children ?? []).map { $0.asRichTextElement }
    return .text(makeText(text: text, link: link, styles: styles, children: children), .init(styles: styles))
  }
}

extension RichTextComponentFragment.Item.AsRichTextHeader.Child.AsRichText {
  public var asRichTextElement: RichTextElement {
    .text(makeText(text: text, link: link, styles: styles, children: []), nil)
  }
}

extension RichTextComponentFragment.Item.AsRichTextHeader.Child.AsRichTextHeader {
  public var asRichTextElement: RichTextElement {
    .text(makeText(text: text, link: link, styles: styles, children: []), .init(styles: styles))
  }
}

extension RichTextComponentFragment.Item.AsRichTextHeader.Child.AsRichTextListItem {
  public var asRichTextElement: RichTextElement {
    .listItem(makeText(text: text, link: link, styles: styles, children: []))
  }
}

extension RichTextComponentFragment.Item.AsRichTextListItem {
  public var asRichTextElement: RichTextElement {
    let children = (children ?? []).map { $0.asRichTextElement }
    return .listItem(makeText(text: text, link: link, styles: styles, children: children))
  }
}

extension RichTextComponentFragment.Item.AsRichTextListItem.Child.AsRichText {
  public var asRichTextElement: RichTextElement {
    .text(makeText(text: text, link: link, styles: styles, children: []), nil)
  }
}

extension RichTextComponentFragment.Item.AsRichTextListItem.Child.AsRichTextHeader {
  public var asRichTextElement: RichTextElement {
    .text(makeText(text: text, link: link, styles: styles, children: []), .init(styles: styles))
  }
}

extension RichTextComponentFragment.Item.AsRichTextListItem.Child.AsRichTextListItem {
  public var asRichTextElement: RichTextElement {
    .listItem(makeText(text: text, link: link, styles: styles, children: []))
  }
}

extension RichTextComponentFragment.Item.AsRichTextListOpen {
  public var asRichTextElement: RichTextElement {
    .listItemOpen
  }
}

extension RichTextComponentFragment.Item.AsRichText.Child.AsRichTextListOpen {
  public var asRichTextElement: RichTextElement {
    .listItemOpen
  }
}

extension RichTextComponentFragment.Item.AsRichTextHeader.Child.AsRichTextListOpen {
  public var asRichTextElement: RichTextElement {
    .listItemOpen
  }
}

extension RichTextComponentFragment.Item.AsRichTextListItem.Child.AsRichTextListOpen {
  public var asRichTextElement: RichTextElement {
    .listItemOpen
  }
}

extension RichTextComponentFragment.Item.AsRichTextListClose {
  public var asRichTextElement: RichTextElement {
    .listItemClose
  }
}

extension RichTextComponentFragment.Item.AsRichText.Child.AsRichTextListClose {
  public var asRichTextElement: RichTextElement {
    .listItemClose
  }
}

extension RichTextComponentFragment.Item.AsRichTextHeader.Child.AsRichTextListClose {
  public var asRichTextElement: RichTextElement {
    .listItemClose
  }
}

extension RichTextComponentFragment.Item.AsRichTextListItem.Child.AsRichTextListClose {
  public var asRichTextElement: RichTextElement {
    .listItemClose
  }
}

extension RichTextComponentFragment.Item.AsRichTextAudio {
  public var asRichTextElement: RichTextElement {
    .audio(RichTextElement.Audio(
      altText: altText,
      assetID: asset?.id,
      caption: caption,
      url: url
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichText.Child.AsRichTextAudio {
  public var asRichTextElement: RichTextElement {
    .audio(RichTextElement.Audio(
      altText: altText,
      assetID: asset?.id,
      caption: caption,
      url: url
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichTextHeader.Child.AsRichTextAudio {
  public var asRichTextElement: RichTextElement {
    .audio(RichTextElement.Audio(
      altText: altText,
      assetID: asset?.id,
      caption: caption,
      url: url
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichTextListItem.Child.AsRichTextAudio {
  public var asRichTextElement: RichTextElement {
    .audio(RichTextElement.Audio(
      altText: altText,
      assetID: asset?.id,
      caption: caption,
      url: url
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichTextPhoto {
  public var asRichTextElement: RichTextElement {
    .photo(RichTextElement.Photo(
      altText: altText,
      assetID: asset?.id,
      caption: caption,
      url: asset?.url,
      link: nil
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichText.Child.AsRichTextPhoto {
  public var asRichTextElement: RichTextElement {
    .photo(RichTextElement.Photo(
      altText: altText,
      assetID: asset?.id,
      caption: caption,
      url: asset?.url,
      link: nil
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichTextHeader.Child.AsRichTextPhoto {
  public var asRichTextElement: RichTextElement {
    .photo(RichTextElement.Photo(
      altText: altText,
      assetID: asset?.id,
      caption: caption,
      url: asset?.url,
      link: nil
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichTextListItem.Child.AsRichTextPhoto {
  public var asRichTextElement: RichTextElement {
    .photo(RichTextElement.Photo(
      altText: altText,
      assetID: asset?.id,
      caption: caption,
      url: asset?.url,
      link: nil
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichTextVideo {
  public var asRichTextElement: RichTextElement {
    .video(RichTextElement.Video(
      altText: altText,
      assetID: asset?.id,
      caption: caption,
      url: url,
      posterURL: asset?.poster,
      formats: makeVideoFormats(asset?.formats)
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichText.Child.AsRichTextVideo {
  public var asRichTextElement: RichTextElement {
    .video(RichTextElement.Video(
      altText: altText,
      assetID: asset?.id,
      caption: caption,
      url: url,
      posterURL: asset?.poster,
      formats: makeVideoFormats(asset?.formats)
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichTextHeader.Child.AsRichTextVideo {
  public var asRichTextElement: RichTextElement {
    .video(RichTextElement.Video(
      altText: altText,
      assetID: asset?.id,
      caption: caption,
      url: url,
      posterURL: asset?.poster,
      formats: makeVideoFormats(asset?.formats)
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichTextListItem.Child.AsRichTextVideo {
  public var asRichTextElement: RichTextElement {
    .video(RichTextElement.Video(
      altText: altText,
      assetID: asset?.id,
      caption: caption,
      url: url,
      posterURL: asset?.poster,
      formats: makeVideoFormats(asset?.formats)
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichTextOembed {
  public var asRichTextElement: RichTextElement {
    .oembed(RichTextElement.OEmbed(
      width: width,
      height: height,
      version: version,
      title: title,
      type: type,
      iframeUrl: iframeUrl,
      originalUrl: originalUrl
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichText.Child.AsRichTextOembed {
  public var asRichTextElement: RichTextElement {
    .oembed(RichTextElement.OEmbed(
      width: width,
      height: height,
      version: version,
      title: title,
      type: type,
      iframeUrl: iframeUrl,
      originalUrl: originalUrl
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichTextHeader.Child.AsRichTextOembed {
  public var asRichTextElement: RichTextElement {
    .oembed(RichTextElement.OEmbed(
      width: width,
      height: height,
      version: version,
      title: title,
      type: type,
      iframeUrl: iframeUrl,
      originalUrl: originalUrl
    ))
  }
}

extension RichTextComponentFragment.Item.AsRichTextListItem.Child.AsRichTextOembed {
  public var asRichTextElement: RichTextElement {
    .oembed(RichTextElement.OEmbed(
      width: width,
      height: height,
      version: version,
      title: title,
      type: type,
      iframeUrl: iframeUrl,
      originalUrl: originalUrl
    ))
  }
}

private func makeVideoFormats(
  _ formats: [RichTextItemFragment.AsRichTextVideo.Asset.Format?]?
) -> [RichTextElement.VideoFormat] {
  (formats ?? []).compactMap { format in
    guard let format else { return nil }
    return RichTextElement.VideoFormat(
      encoding: format.encoding,
      height: format.height,
      width: format.width,
      profile: format.profile,
      url: format.url
    )
  }
}

private func makeTextElement(
  text: String?,
  link: String?,
  styles: [RichTextElement.Text.Style]?,
  children: [RichTextElement]
) -> RichTextElement.Text {
  RichTextElement.Text(
    text: text ?? "",
    link: link.flatMap { URL(string: $0) },
    styles: styles ?? [],
    children: children
  )
}

private func makeText(
  text: String?,
  link: String?,
  styles: [String]?,
  children: [RichTextElement]
) -> RichTextElement.Text {
  makeTextElement(
    text: text,
    link: link,
    styles: styles?.compactMap(RichTextElement.Text.Style.init(rawValue:)),
    children: children
  )
}
