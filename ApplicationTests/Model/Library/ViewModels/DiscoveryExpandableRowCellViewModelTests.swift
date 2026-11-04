@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class DiscoveryExpandableRowCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  fileprivate let vm = DiscoveryExpandableRowCellViewModel()

  func testCellAccessibilityHint_WhenCollapsed() {
    let expandableRowNotExpanded = ExpandableRow(
      isExpanded: false,
      params: .defaults |> DiscoveryParams.lens.category .~ .filmAndVideo,
      selectableRows: []
    )

    let categoryId = expandableRowNotExpanded.params.category?.intID

    self.vm.configureWith(row: expandableRowNotExpanded, categoryId: categoryId)
    let display = self.vm.willDisplay()

    XCTAssertEqual(display?.accessibilityHint, Strings.Expands_subcategories())
  }

  func testCellAccessibilityHint_WhenExpanded() {
    let expandableRowExpanded = ExpandableRow(
      isExpanded: true,
      params: .defaults |> DiscoveryParams.lens.category .~ .filmAndVideo,
      selectableRows: []
    )
    let categoryId = expandableRowExpanded.params.category?.intID

    self.vm.configureWith(row: expandableRowExpanded, categoryId: categoryId)
    let display = self.vm.willDisplay()

    XCTAssertEqual(display?.accessibilityHint, Strings.Collapses_subcategories())
  }

  func testCellAccessibilityLabel() {
    let expandableRow = ExpandableRow(
      isExpanded: false,
      params: .defaults |> DiscoveryParams.lens.category .~ .filmAndVideo,
      selectableRows: []
    )
    let categoryId = expandableRow.params.category?.intID

    self.vm.configureWith(row: expandableRow, categoryId: categoryId)
    let display = self.vm.willDisplay()

    XCTAssertEqual(display?.accessibilityLabel,
      Strings.Filter_name_project_count_live_projects(
        filter_name: expandableRow.params.category?.name ?? "",
        project_count: expandableRow.params.category?.totalProjectCount ?? 0
      )
    )
  }

  func testExpandCategoryStyle() {
    let expandableRow = ExpandableRow(
      isExpanded: false,
      params: .defaults |> DiscoveryParams.lens.category .~ .filmAndVideo,
      selectableRows: []
    )
    let categoryId = expandableRow.params.category?.intID

    self.vm.configureWith(row: expandableRow, categoryId: categoryId)
    let display = self.vm.willDisplay()

    XCTAssertEqual(display?.row, expandableRow)
    XCTAssertEqual(display?.categoryId, categoryId)
  }

  func testFilterIsExpanded_Expanded() {
    let expandableRow = ExpandableRow(
      isExpanded: true,
      params: .defaults |> DiscoveryParams.lens.category .~ .games,
      selectableRows: []
    )
    let categoryId = expandableRow.params.category?.intID

    self.vm.configureWith(row: expandableRow, categoryId: categoryId)
    let display = self.vm.willDisplay()

    XCTAssertEqual(display?.row.isExpanded, true)
  }

  func testFilterIsExpanded_NotExpanded() {
    let expandableRow = ExpandableRow(
      isExpanded: false,
      params: .defaults |> DiscoveryParams.lens.category .~ .games,
      selectableRows: []
    )
    let categoryId = expandableRow.params.category?.intID

    self.vm.configureWith(row: expandableRow, categoryId: categoryId)
    let display = self.vm.willDisplay()

    XCTAssertEqual(display?.row.isExpanded, false)
  }

  func testFilterTitleLabelText() {
    let expandableRow = ExpandableRow(
      isExpanded: false,
      params: .defaults |> DiscoveryParams.lens.category .~ .filmAndVideo,
      selectableRows: []
    )
    let categoryId = expandableRow.params.category?.intID

    self.vm.configureWith(row: expandableRow, categoryId: categoryId)
    let display = self.vm.willDisplay()

    XCTAssertEqual(display?.title, expandableRow.params.category?.name ?? "")
  }

  func testProjectsCountLabelAlpha() {
    let expandableRow = ExpandableRow(
      isExpanded: false,
      params: .defaults |> DiscoveryParams.lens.category .~ .filmAndVideo,
      selectableRows: []
    )
    let categoryId = expandableRow.params.category?.intID

    self.vm.configureWith(row: expandableRow, categoryId: categoryId)
    let display = self.vm.willDisplay()

    XCTAssertEqual(display?.countAlpha, 0.4)
  }

  func testProjectsCountLabelHidden() {
    let gamesCategory = .games |> Category.lens.totalProjectCount .~ 10
    let expandableRow = ExpandableRow(
      isExpanded: false,
      params: .defaults |> DiscoveryParams.lens.category .~ gamesCategory,
      selectableRows: []
    )
    let categoryId = expandableRow.params.category?.intID

    self.vm.configureWith(row: expandableRow, categoryId: categoryId)
    let display = self.vm.willDisplay()

    XCTAssertEqual(display?.countHidden, false)
  }

  func testProjectsCountLabelHidden_NoProjects() {
    let gamesCategory = .games |> Category.lens.totalProjectCount .~ 0
    let expandableRow = ExpandableRow(
      isExpanded: false,
      params: .defaults |> DiscoveryParams.lens.category .~ gamesCategory,
      selectableRows: []
    )
    let categoryId = expandableRow.params.category?.intID

    self.vm.configureWith(row: expandableRow, categoryId: categoryId)
    let display = self.vm.willDisplay()

    XCTAssertEqual(display?.countHidden, true)
  }

  func testProjectsCountLabelText() {
    let filmAndVideoCategory = .filmAndVideo |> Category.lens.totalProjectCount .~ 10
    let expandableRow = ExpandableRow(
      isExpanded: false,
      params: .defaults |> DiscoveryParams.lens.category .~ filmAndVideoCategory,
      selectableRows: []
    )
    let categoryId = expandableRow.params.category?.intID

    self.vm.configureWith(row: expandableRow, categoryId: categoryId)
    let display = self.vm.willDisplay()

    XCTAssertEqual(display?.count, Format.wholeNumber(10))
  }
}
