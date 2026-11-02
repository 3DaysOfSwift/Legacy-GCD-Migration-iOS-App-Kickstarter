import GraphAPI

/// A single row in the Report Project info list, representing either an expandable
/// group (parent node) or a selectable flagging action (leaf node).
public struct ReportProjectInfoListItem: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let subtitle: String

  /// The flagging kind submitted when this leaf node is selected.
  private let flaggingKindValue: String?
  public var flaggingKind: GraphAPI.NonDeprecatedFlaggingKind? {
    self.flaggingKindValue.flatMap(GraphAPI.NonDeprecatedFlaggingKind.init(rawValue:))
  }

  /// Placeholder text for the form text field shown when this option is selected.
  public let placeholder: String?

  /// Child rows revealed when this parent row is expanded. `nil` for leaf nodes.
  public var subItems: [ReportProjectInfoListItem]?

  public init(
    id: String,
    title: String,
    subtitle: String,
    flaggingKind: GraphAPI.NonDeprecatedFlaggingKind? = nil,
    placeholder: String? = nil,
    subItems: [ReportProjectInfoListItem]? = nil
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.flaggingKindValue = flaggingKind?.rawValue
    self.placeholder = placeholder
    self.subItems = subItems
  }
}
