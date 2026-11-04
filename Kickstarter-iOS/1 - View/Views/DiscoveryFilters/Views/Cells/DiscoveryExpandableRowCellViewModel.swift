import KsApi
import UIKit

@MainActor
public final class DiscoveryExpandableRowCellViewModel {
  public struct Display {
    let row: ExpandableRow
    let categoryId: Int?
    let accessibilityHint: String
    let accessibilityLabel: String
    let title: String
    let count: String
    let countHidden: Bool
    let countAlpha: CGFloat
  }

  private var configuration: (row: ExpandableRow, categoryId: Int?)?
  public init() {}

  public func configureWith(row: ExpandableRow, categoryId: Int?) {
    self.configuration = (row, categoryId)
  }

  public func willDisplay() -> Display? {
    guard let (row, categoryId) = self.configuration else { return nil }
    let name = row.params.category?.name ?? ""
    let count = row.params.category?.totalProjectCount ?? 0
    return Display(
      row: row,
      categoryId: categoryId,
      accessibilityHint: row.isExpanded ? Strings.Collapses_subcategories() : Strings.Expands_subcategories(),
      accessibilityLabel: Strings.Filter_name_project_count_live_projects(filter_name: name, project_count: count),
      title: name,
      count: Format.wholeNumber(count),
      countHidden: row.params.category?.totalProjectCount == .some(0),
      countAlpha: categoryId == nil || row.isExpanded ? 1.0 : 0.4
    )
  }
}
