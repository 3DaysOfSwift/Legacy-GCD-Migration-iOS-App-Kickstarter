@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class DiscoveryNavigationHeaderViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  fileprivate var vm: DiscoveryNavigationHeaderViewModel!

  private let animateArrowToDown = HeaderRecorder<Bool>()
  private let arrowOpacity = HeaderRecorder<CGFloat>()
  private let arrowOpacityAnimated = HeaderRecorder<Bool>()
  private let debugContainerViewIsHidden = HeaderRecorder<Bool>()
  private let debugImageViewIsDimmed = HeaderRecorder<Bool>()
  private let dividerIsHidden = HeaderRecorder<Bool>()
  private let exploreLabelIsHidden = HeaderRecorder<Bool>()
  private let logoutWithParams = HeaderRecorder<DiscoveryParams>()
  private let primaryLabelOpacity = HeaderRecorder<CGFloat>()
  private let primaryLabelOpacityAnimated = HeaderRecorder<Bool>()
  private let primaryLabelText = HeaderRecorder<String>()
  private let dismissDiscoveryFilters = HeaderRecorder<()>()
  private let notifyDelegateFilterSelectedParams = HeaderRecorder<DiscoveryParams>()
  private let secondaryLabelText = HeaderRecorder<String>()
  private let secondaryLabelIsHidden = HeaderRecorder<Bool>()
  private let titleAccessibilityHint = HeaderRecorder<String>()
  private let titleAccessibilityLabel = HeaderRecorder<String>()
  private let showDiscoveryFiltersRow = HeaderRecorder<SelectableRow>()
  private let favoriteButtonAccessibilityLabel = HeaderRecorder<String>()
  private let favoriteViewIsDimmed = HeaderRecorder<Bool>()
  private let favoriteViewIsHidden = HeaderRecorder<Bool>()
  private let showFavoriteOnboardingAlert = HeaderRecorder<String>()
  private let updateFavoriteButtonSelected = HeaderRecorder<Bool>()
  private let updateFavoriteButtonAnimated = HeaderRecorder<Bool>()

  let initialParams = .defaults
    |> DiscoveryParams.lens.includePOTD .~ true

  let categoryParams = .defaults |> DiscoveryParams.lens.category .~ .art
  let subcategoryParams = .defaults |> DiscoveryParams.lens.category .~ .documentary
  let starredParams = .defaults |> DiscoveryParams.lens.starred .~ true

  let selectableRow = SelectableRow(isSelected: false, params: .defaults)

  private var pendingDismissals: [@MainActor () -> Void] = []

  internal override func setUp() async throws {
    try await super.setUp()
    self.vm = DiscoveryNavigationHeaderViewModel(scheduleDismissal: { [weak self] action in
      self?.pendingDismissals.append(action)
    })
    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .animateArrowToDown(value): self.animateArrowToDown.record(value)
      case let .debugContainerViewIsHidden(value): self.debugContainerViewIsHidden.record(value)
      case let .debugImageViewIsDimmed(value): self.debugImageViewIsDimmed.record(value)
      case let .dividerIsHidden(value): self.dividerIsHidden.record(value)
      case let .exploreLabelIsHidden(value): self.exploreLabelIsHidden.record(value)
      case let .favoriteButtonAccessibilityLabel(value): self.favoriteButtonAccessibilityLabel.record(value)
      case let .favoriteViewIsDimmed(value): self.favoriteViewIsDimmed.record(value)
      case let .favoriteViewIsHidden(value): self.favoriteViewIsHidden.record(value)
      case let .notifyDelegateFilterSelectedParams(value): self.notifyDelegateFilterSelectedParams.record(value)
      case let .primaryLabelText(value): self.primaryLabelText.record(value)
      case let .secondaryLabelIsHidden(value): self.secondaryLabelIsHidden.record(value)
      case let .secondaryLabelText(value): self.secondaryLabelText.record(value)
      case let .showDiscoveryFilters(value): self.showDiscoveryFiltersRow.record(value)
      case let .showFavoriteOnboardingAlert(value): self.showFavoriteOnboardingAlert.record(value)
      case let .titleButtonAccessibilityHint(value): self.titleAccessibilityHint.record(value)
      case let .titleButtonAccessibilityLabel(value): self.titleAccessibilityLabel.record(value)
      case .dismissDiscoveryFilters: self.dismissDiscoveryFilters.record(())
      case let .arrowOpacityAnimated(value, animated): self.arrowOpacity.record(value); self.arrowOpacityAnimated.record(animated)
      case let .primaryLabelOpacityAnimated(value, animated): self.primaryLabelOpacity.record(value); self.primaryLabelOpacityAnimated.record(animated)
      case let .updateFavoriteButton(selected, animated): self.updateFavoriteButtonSelected.record(selected); self.updateFavoriteButtonAnimated.record(animated)
      case .primaryLabelFont: break
      }
    }
  }

  private func advanceDismissals() {
    let actions = self.pendingDismissals
    self.pendingDismissals.removeAll()
    actions.forEach { $0() }
  }

  func testShowFilters() {
    let initialRow = SelectableRow(isSelected: true, params: initialParams)
    let starredRow = self.selectableRow |> SelectableRow.lens.params .~ self.starredParams
    let artRow = self.selectableRow |> SelectableRow.lens.params .~ self.categoryParams

    self.vm.viewDidLoad()
    self.vm.configureWith(params: self.initialParams)

    self.showDiscoveryFiltersRow.assertValueCount(0)
    self.dismissDiscoveryFilters.assertValueCount(0)

    self.vm.titleButtonTapped()

    self.showDiscoveryFiltersRow.assertValues([initialRow])

    self.vm.filtersSelected(row: starredRow)

    self.showDiscoveryFiltersRow.assertValues([initialRow], "Show Filters does not emit on selection.")

    self.advanceDismissals()
    self.dismissDiscoveryFilters.assertValueCount(1)

    self.vm.titleButtonTapped()

    self.showDiscoveryFiltersRow.assertValues([initialRow, starredRow])

    self.vm.titleButtonTapped()

    self.showDiscoveryFiltersRow.assertValues(
      [initialRow, starredRow],
      "Show filters does not emit on close."
    )

    self.vm.titleButtonTapped()

    self.showDiscoveryFiltersRow.assertValues([initialRow, starredRow, starredRow])

    self.vm.filtersSelected(row: artRow)
    self.vm.titleButtonTapped()

    self.showDiscoveryFiltersRow.assertValues([initialRow, starredRow, starredRow, artRow])
  }

  func testRepeatedDismissalsOnlyDeliverLatest() {
    self.vm.viewDidLoad()
    self.vm.configureWith(params: self.initialParams)
    self.vm.titleButtonTapped()
    self.vm.filtersSelected(row: self.selectableRow)
    self.vm.titleButtonTapped()
    self.vm.titleButtonTapped()

    self.dismissDiscoveryFilters.assertValueCount(0)
    self.advanceDismissals()
    self.dismissDiscoveryFilters.assertValueCount(1)
  }

  func testShowFilters_BeforeApiReturns() {
    let initialRow = SelectableRow(isSelected: true, params: initialParams)

    self.vm.viewDidLoad()
    self.vm.configureWith(params: self.initialParams)

    self.showDiscoveryFiltersRow.assertValueCount(0)
    self.dismissDiscoveryFilters.assertValueCount(0)

    // Tap title before the categories are fetched
    self.vm.titleButtonTapped()
    self.advanceDismissals()

    self.showDiscoveryFiltersRow.assertValues(
      [initialRow],
      "Filters are shown even before categories are fetched."
    )
    self.dismissDiscoveryFilters.assertValueCount(0, "Dismissing is not emitted.")

    // Wait enough time for categories to come back

    self.showDiscoveryFiltersRow.assertValues(
      [initialRow],
      "Nothing new is emitted once categories are fetched."
    )
    self.dismissDiscoveryFilters.assertValueCount(0, "Dismissing is not emitted.")

    // Tap title again to dismiss
    self.vm.titleButtonTapped()
    self.advanceDismissals()

    self.showDiscoveryFiltersRow.assertValues([initialRow], "Nothing new is emitted when dismissing.")
    self.dismissDiscoveryFilters.assertValueCount(1, "Dismiss is emitted.")

    // Tap title again to present
    self.vm.titleButtonTapped()
    self.advanceDismissals()

    self.showDiscoveryFiltersRow.assertValues(
      [initialRow, initialRow],
      "Filters are shown again."
    )
    self.dismissDiscoveryFilters.assertValueCount(1, "Dismissing is not emitted.")
  }

  func testTitleData() {
    self.arrowOpacity.assertValueCount(0)
    self.primaryLabelOpacity.assertValueCount(0)

    self.vm.viewDidLoad()

    self.arrowOpacity.assertValues([0.0])
    self.arrowOpacityAnimated.assertValues([false])
    self.primaryLabelOpacity.assertValues([0.0])
    self.primaryLabelOpacityAnimated.assertValues([false])
    self.animateArrowToDown.assertValueCount(0)
    self.dividerIsHidden.assertValueCount(0)
    self.primaryLabelText.assertValueCount(0)
    self.secondaryLabelText.assertValueCount(0)
    self.secondaryLabelIsHidden.assertValueCount(0)
    self.titleAccessibilityHint.assertValueCount(0)
    self.titleAccessibilityLabel.assertValueCount(0)

    self.vm.configureWith(params: self.initialParams)

    self.arrowOpacity.assertValues([0.0, 1.0])
    self.arrowOpacityAnimated.assertValues([false, true])
    self.primaryLabelOpacity.assertValues([0.0, 1.0])
    self.primaryLabelOpacityAnimated.assertValues([false, true])
    self.animateArrowToDown.assertValues([true])
    self.dividerIsHidden.assertValues([true])
    self.primaryLabelText.assertValues([Strings.All_Projects()])
    self.secondaryLabelText.assertValues([""])
    self.secondaryLabelIsHidden.assertValues([true])
    self.titleAccessibilityHint.assertValues([Strings.Opens_filters()])
    self.titleAccessibilityLabel.assertValues([Strings.Filter_by_all_projects()])

    self.vm.titleButtonTapped()

    self.arrowOpacity.assertValues([0.0, 1.0])
    self.arrowOpacityAnimated.assertValues([false, true])
    self.primaryLabelOpacity.assertValues([0.0, 1.0, 1.0])
    self.primaryLabelOpacityAnimated.assertValues([false, true, true])
    self.animateArrowToDown.assertValues([true, false])
    self.dividerIsHidden.assertValues([true])
    self.primaryLabelText.assertValues([Strings.All_Projects(), Strings.All_Projects()])
    self.secondaryLabelText.assertValues(["", ""])
    self.secondaryLabelIsHidden.assertValues([true])
    self.titleAccessibilityHint.assertValues([Strings.Opens_filters(), Strings.Closes_filters()])
    self.titleAccessibilityLabel.assertValues([
      Strings.Filter_by_all_projects(),
      Strings.Filter_by_all_projects()
    ])

    self.vm.filtersSelected(row: self.selectableRow |> SelectableRow.lens.params .~ self.starredParams)

    self.arrowOpacity.assertValues([0.0, 1.0])
    self.arrowOpacityAnimated.assertValues([false, true])
    self.primaryLabelOpacity.assertValues([0.0, 1.0, 1.0, 1.0])
    self.primaryLabelOpacityAnimated.assertValues([false, true, true, true])
    self.animateArrowToDown.assertValues([true, false, true])
    self.dividerIsHidden.assertValues([true])
    self.primaryLabelText.assertValues([
      Strings.All_Projects(), Strings.All_Projects(),
      Strings.Saved()
    ])
    self.secondaryLabelText.assertValues(["", "", ""])
    self.secondaryLabelIsHidden.assertValues([true])
    self.titleAccessibilityHint.assertValues([
      Strings.Opens_filters(), Strings.Closes_filters(),
      Strings.Opens_filters()
    ])
    self.titleAccessibilityLabel.assertValues([
      Strings.Filter_by_all_projects(),
      Strings.Filter_by_all_projects(), Strings.Filter_by_saved_projects()
    ])

    self.vm.titleButtonTapped()

    self.arrowOpacity.assertValues([0.0, 1.0])
    self.arrowOpacityAnimated.assertValues([false, true])
    self.primaryLabelOpacity.assertValues([0.0, 1.0, 1.0, 1.0, 1.0])
    self.primaryLabelOpacityAnimated.assertValues([false, true, true, true, true])
    self.animateArrowToDown.assertValues([true, false, true, false])
    self.dividerIsHidden.assertValues([true])
    self.primaryLabelText.assertValues([
      Strings.All_Projects(), Strings.All_Projects(),
      Strings.Saved(), Strings.Saved()
    ])
    self.secondaryLabelText.assertValues(["", "", "", ""])
    self.secondaryLabelIsHidden.assertValues([true])
    self.titleAccessibilityHint.assertValues([
      Strings.Opens_filters(), Strings.Closes_filters(),
      Strings.Opens_filters(), Strings.Closes_filters()
    ])
    self.titleAccessibilityLabel.assertValues([
      Strings.Filter_by_all_projects(),
      Strings.Filter_by_all_projects(), Strings.Filter_by_saved_projects(),
      Strings.Filter_by_saved_projects()
    ])

    self.vm.filtersSelected(
      row: self.selectableRow |> SelectableRow.lens.params .~ self.categoryParams
    )

    self.arrowOpacity.assertValues([0.0, 1.0])
    self.arrowOpacityAnimated.assertValues([false, true])
    self.primaryLabelOpacity.assertValues([0.0, 1.0, 1.0, 1.0, 1.0, 1.0])
    self.primaryLabelOpacityAnimated.assertValues([false, true, true, true, true, true])
    self.animateArrowToDown.assertValues([true, false, true, false, true])
    self.dividerIsHidden.assertValues([true])
    self.primaryLabelText.assertValues([
      Strings.All_Projects(), Strings.All_Projects(),
      Strings.Saved(), Strings.Saved(), Strings.All_Art_Projects()
    ])
    self.secondaryLabelText.assertValues(["", "", "", "", ""])
    self.secondaryLabelIsHidden.assertValues([true])
    self.titleAccessibilityHint.assertValues([
      Strings.Opens_filters(), Strings.Closes_filters(),
      Strings.Opens_filters(), Strings.Closes_filters(), Strings.Opens_filters()
    ])
    self.titleAccessibilityLabel.assertValues([
      Strings.Filter_by_all_projects(),
      Strings.Filter_by_all_projects(), Strings.Filter_by_saved_projects(),
      Strings.Filter_by_saved_projects(),
      Strings.Filter_by_category_name(category_name: self.categoryParams.category?.name ?? "")
    ])

    self.vm.titleButtonTapped()

    self.arrowOpacity.assertValues([0.0, 1.0])
    self.arrowOpacityAnimated.assertValues([false, true])
    self.primaryLabelOpacity.assertValues([0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
    self.primaryLabelOpacityAnimated.assertValues([false, true, true, true, true, true, true])
    self.animateArrowToDown.assertValues([true, false, true, false, true, false])
    self.dividerIsHidden.assertValues([true])
    self.primaryLabelText.assertValues([
      Strings.All_Projects(), Strings.All_Projects(),
      Strings.Saved(), Strings.Saved(), Strings.All_Art_Projects(),
      Strings.All_Art_Projects()
    ])
    self.secondaryLabelText.assertValues(["", "", "", "", "", ""])
    self.secondaryLabelIsHidden.assertValues([true])
    self.titleAccessibilityHint.assertValues([
      Strings.Opens_filters(), Strings.Closes_filters(),
      Strings.Opens_filters(), Strings.Closes_filters(), Strings.Opens_filters(), Strings.Closes_filters()
    ])
    self.titleAccessibilityLabel.assertValues([
      Strings.Filter_by_all_projects(),
      Strings.Filter_by_all_projects(), Strings.Filter_by_saved_projects(),
      Strings.Filter_by_saved_projects(),
      Strings.Filter_by_category_name(category_name: self.categoryParams.category?.name ?? ""),
      Strings.Filter_by_category_name(category_name: self.categoryParams.category?.name ?? "")
    ])

    self.vm.filtersSelected(
      row: self.selectableRow |> SelectableRow.lens.params .~ self.subcategoryParams
    )

    self.arrowOpacity.assertValues([0.0, 1.0])
    self.arrowOpacityAnimated.assertValues([false, true])
    self.primaryLabelOpacity.assertValues([0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.6])
    self.primaryLabelOpacityAnimated.assertValues([false, true, true, true, true, true, true, true])
    self.animateArrowToDown.assertValues([true, false, true, false, true, false, true])
    self.dividerIsHidden.assertValues([true, false])
    self.primaryLabelText.assertValues([
      Strings.All_Projects(), Strings.All_Projects(),
      Strings.Saved(), Strings.Saved(), Strings.All_Art_Projects(),
      Strings.All_Art_Projects(), "Film & Video"
    ])
    self.secondaryLabelText.assertValues(["", "", "", "", "", "", "Documentary"])
    self.secondaryLabelIsHidden.assertValues([true, false])
    self.titleAccessibilityHint.assertValues([
      Strings.Opens_filters(), Strings.Closes_filters(),
      Strings.Opens_filters(), Strings.Closes_filters(), Strings.Opens_filters(), Strings.Closes_filters(),
      Strings.Opens_filters()
    ])
    self.titleAccessibilityLabel.assertValues([
      Strings.Filter_by_all_projects(),
      Strings.Filter_by_all_projects(), Strings.Filter_by_saved_projects(),
      Strings.Filter_by_saved_projects(),
      Strings.Filter_by_category_name(category_name: self.categoryParams.category?.name ?? ""),
      Strings.Filter_by_category_name(category_name: self.categoryParams.category?.name ?? ""),
      Strings.Filter_by_subcategory_name_in_category_name(
        subcategory_name: self.subcategoryParams.category?.name ?? "",
        category_name: self.subcategoryParams.category?._parent?.name ?? ""
      )
    ])
  }

  func testExploreLabelIsHidden_ifSelectedFilterIsNotDefault() {
    self.vm.viewDidLoad()
    self.vm.configureWith(params: self.initialParams)

    self.vm.filtersSelected(
      row: self.selectableRow |> SelectableRow.lens.params .~ self.categoryParams
    )

    self.exploreLabelIsHidden.assertValues([true])
  }

  func testExploreLabelIsNotHidden_ifSelectedFilterIsDefault() {
    self.vm.viewDidLoad()
    self.vm.configureWith(params: self.initialParams)

    self.vm.filtersSelected(row: self.selectableRow)

    self.exploreLabelIsHidden.assertValues([false])
  }

  func testNotifyFilterSelectedParams() {
    self.vm.viewDidLoad()
    self.vm.configureWith(params: self.initialParams)

    self.notifyDelegateFilterSelectedParams.assertValueCount(0)

    self.vm.filtersSelected(row: self.selectableRow)

    self.notifyDelegateFilterSelectedParams.assertValues([DiscoveryParams.defaults])

    self.vm.filtersSelected(
      row: self.selectableRow |> SelectableRow.lens.params .~ self.categoryParams
    )

    self.notifyDelegateFilterSelectedParams.assertValues([DiscoveryParams.defaults, self.categoryParams])
  }

  func testFavoriting() {
    let artSelectableRow = self.selectableRow |> SelectableRow.lens.params .~ self.categoryParams

    self.vm.viewDidLoad()
    self.vm.configureWith(params: self.initialParams)

    self.favoriteViewIsHidden.assertValues([true])

    self.vm.titleButtonTapped()

    self.favoriteViewIsHidden.assertValues([true])
    self.favoriteViewIsDimmed.assertValueCount(0)
    self.updateFavoriteButtonAnimated.assertValueCount(0)
    self.updateFavoriteButtonSelected.assertValueCount(0)
    self.favoriteButtonAccessibilityLabel.assertValueCount(0)

    self.vm.filtersSelected(row: artSelectableRow)

    self.favoriteViewIsHidden.assertValues([true, false])
    self.favoriteViewIsDimmed.assertValues([false])
    self.updateFavoriteButtonAnimated.assertValues([false])
    self.updateFavoriteButtonSelected.assertValues([false])
    self.showFavoriteOnboardingAlert.assertValueCount(0)
    self.favoriteButtonAccessibilityLabel.assertValues([
      Strings.discovery_favorite_categories_buttons_favorite_a11y_label()
    ])

    self.vm.favoriteButtonTapped()

    self.favoriteViewIsHidden.assertValues([true, false])
    self.favoriteViewIsDimmed.assertValues([false])
    self.updateFavoriteButtonAnimated.assertValues([false, true])
    self.updateFavoriteButtonSelected.assertValues([false, true])
    self.showFavoriteOnboardingAlert.assertValues(["All Art Projects saved."])
    self.favoriteButtonAccessibilityLabel.assertValues([
      Strings.discovery_favorite_categories_buttons_favorite_a11y_label(),
      Strings.discovery_favorite_categories_buttons_unfavorite_a11y_label()
    ])

    self.vm.titleButtonTapped()

    self.favoriteViewIsHidden.assertValues([true, false])
    self.favoriteViewIsDimmed.assertValues([false, true])
    self.updateFavoriteButtonAnimated.assertValues([false, true])
    self.updateFavoriteButtonSelected.assertValues([false, true])
    self.showFavoriteOnboardingAlert.assertValues(["All Art Projects saved."])
    self.favoriteButtonAccessibilityLabel.assertValues([
      Strings.discovery_favorite_categories_buttons_favorite_a11y_label(),
      Strings.discovery_favorite_categories_buttons_unfavorite_a11y_label()
    ])

    self.vm.titleButtonTapped()

    self.favoriteViewIsHidden.assertValues([true, false])
    self.favoriteViewIsDimmed.assertValues([false, true, false])
    self.updateFavoriteButtonAnimated.assertValues([false, true])
    self.updateFavoriteButtonSelected.assertValues([false, true])
    self.showFavoriteOnboardingAlert.assertValues(["All Art Projects saved."])
    self.favoriteButtonAccessibilityLabel.assertValues([
      Strings.discovery_favorite_categories_buttons_favorite_a11y_label(),
      Strings.discovery_favorite_categories_buttons_unfavorite_a11y_label()
    ])

    self.vm.favoriteButtonTapped()

    self.favoriteViewIsHidden.assertValues([true, false])
    self.favoriteViewIsDimmed.assertValues([false, true, false])
    self.updateFavoriteButtonAnimated.assertValues([false, true, true])
    self.updateFavoriteButtonSelected.assertValues([false, true, false])
    self.showFavoriteOnboardingAlert.assertValues(["All Art Projects saved."], "Alert does not emit again.")
    self.favoriteButtonAccessibilityLabel.assertValues([
      Strings.discovery_favorite_categories_buttons_favorite_a11y_label(),
      Strings.discovery_favorite_categories_buttons_unfavorite_a11y_label(),
      Strings.discovery_favorite_categories_buttons_favorite_a11y_label()
    ])

    self.vm.titleButtonTapped()

    self.favoriteViewIsHidden.assertValues([true, false])
    self.favoriteViewIsDimmed.assertValues([false, true, false, true])
    self.updateFavoriteButtonAnimated.assertValues([false, true, true])
    self.updateFavoriteButtonSelected.assertValues([false, true, false])
    self.showFavoriteOnboardingAlert.assertValues(["All Art Projects saved."], "Alert does not emit again.")
    self.favoriteButtonAccessibilityLabel.assertValues([
      Strings.discovery_favorite_categories_buttons_favorite_a11y_label(),
      Strings.discovery_favorite_categories_buttons_unfavorite_a11y_label(),
      Strings.discovery_favorite_categories_buttons_favorite_a11y_label()
    ])

    self.vm.filtersSelected(row: self.selectableRow)

    self.favoriteViewIsHidden.assertValues([true, false, true])
    self.favoriteViewIsDimmed.assertValues([false, true, false, true])
    self.updateFavoriteButtonAnimated.assertValues([false, true, true])
    self.updateFavoriteButtonSelected.assertValues([false, true, false])
    self.showFavoriteOnboardingAlert.assertValues(["All Art Projects saved."], "Alert does not emit again.")
    self.favoriteButtonAccessibilityLabel.assertValues([
      Strings.discovery_favorite_categories_buttons_favorite_a11y_label(),
      Strings.discovery_favorite_categories_buttons_unfavorite_a11y_label(),
      Strings.discovery_favorite_categories_buttons_favorite_a11y_label()
    ])
  }

  func testEnvironmentButtonIsNotHidden_Alpha() {
    withEnvironment(mainBundle: MockBundle(bundleIdentifier: KickstarterBundleIdentifier.alpha.rawValue)) {
      self.vm.viewDidLoad()

      self.debugContainerViewIsHidden.assertValue(false)
    }
  }

  func testEnvironmentButtonIsNotHidden_Beta() {
    withEnvironment(mainBundle: MockBundle(bundleIdentifier: KickstarterBundleIdentifier.beta.rawValue)) {
      self.vm.viewDidLoad()

      self.debugContainerViewIsHidden.assertValue(false)
    }
  }

  func testEnvironmentButtonIsHidden_Release() {
    withEnvironment(mainBundle: MockBundle(bundleIdentifier: KickstarterBundleIdentifier.release.rawValue)) {
      self.vm.viewDidLoad()

      self.debugContainerViewIsHidden.assertValue(true)
    }
  }

  func testDebugButtonIsHidden_Unknown() {
    withEnvironment(mainBundle: MockBundle(bundleIdentifier: "unknown")) {
      self.vm.viewDidLoad()

      self.debugContainerViewIsHidden.assertValue(true)
    }
  }

  func testDebugImageViewIsDimmed_whenDebugContainerViewIsNotHidden() {
    withEnvironment(mainBundle: MockBundle(bundleIdentifier: KickstarterBundleIdentifier.alpha.rawValue)) {
      self.vm.viewDidLoad()
      self.vm.configureWith(params: self.initialParams)

      self.debugContainerViewIsHidden.assertValue(false)
      self.debugImageViewIsDimmed.assertValues([false])

      self.vm.titleButtonTapped()

      self.debugImageViewIsDimmed.assertValues([false, true])

      self.vm.titleButtonTapped()

      self.debugImageViewIsDimmed.assertValues([false, true, false])
    }
  }

  func testDebugImageViewIsDimmed_whenDebugcountainerViewIsHidden() {
    withEnvironment(mainBundle: MockBundle(bundleIdentifier: KickstarterBundleIdentifier.release.rawValue)) {
      self.vm.viewDidLoad()
      self.vm.configureWith(params: self.initialParams)

      self.debugContainerViewIsHidden.assertValue(true)
      self.debugImageViewIsDimmed.assertDidNotEmitValue()

      self.vm.titleButtonTapped()

      self.debugImageViewIsDimmed.assertDidNotEmitValue()

      self.vm.titleButtonTapped()

      self.debugImageViewIsDimmed.assertDidNotEmitValue()
    }
  }
}

private final class HeaderRecorder<Value> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(file: StaticString = #filePath, line: UInt = #line) {
    self.assertValueCount(0, file: file, line: line)
  }
}

private extension HeaderRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
  func assertValue(_ expected: Value, file: StaticString = #filePath, line: UInt = #line) {
    self.assertValues([expected], file: file, line: line)
  }
}
