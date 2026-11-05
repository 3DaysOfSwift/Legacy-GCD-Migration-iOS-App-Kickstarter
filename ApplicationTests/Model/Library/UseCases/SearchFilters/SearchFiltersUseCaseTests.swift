@testable import Kickstarter_iOS
@testable import KsApi


import Combine
import XCTest

@MainActor
final class SearchFiltersUseCaseTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  private lazy var searchFeature = SearchFeature(provider: AsyncSearchProjectsProvider())
  private var useCase: SearchFiltersUseCase!
  private var selectionObservation: MainActorObservation?

  private let selectedSort = FilterRecorder<DiscoveryParams.Sort>()
  private let selectedCategory = FilterRecorder<KsApi.Category?>()
  private let selectedState = FilterRecorder<DiscoveryParams.State>()
  private let selectedPercentRaisedBucket = FilterRecorder<DiscoveryParams.PercentRaisedBucket?>()
  private let selectedLocation = FilterRecorder<Location?>()
  private let selectedAmountRaisedBucket = FilterRecorder<DiscoveryParams.AmountRaisedBucket?>()
  private let selectedGoalBucket = FilterRecorder<DiscoveryParams.GoalBucket?>()
  private let selectedToggles = FilterRecorder<SearchFilterToggles>()
  private let showFilters = FilterRecorder<SearchFilterModalType>()


  override func setUp() async throws {
    try await super.setUp()

    MainActor.assumeIsolated {
    self.useCase = SearchFiltersUseCase(searchFeature: self.searchFeature)

    self.selectionObservation = self.searchFeature.filterSelection.observe { [weak self] change in
      guard let self else { return }
      switch change {
      case let .category(value): self.selectedCategory.record(value.category)
      case let .sort(value): self.selectedSort.record(value)
      case let .state(value): self.selectedState.record(value)
      case let .percent(value): self.selectedPercentRaisedBucket.record(value)
      case let .location(value): self.selectedLocation.record(value)
      case let .amount(value): self.selectedAmountRaisedBucket.record(value)
      case let .goal(value): self.selectedGoalBucket.record(value)
      case let .toggles(value): self.selectedToggles.record(value)
      }
    }
    self.useCase.uiOutputs.onShowFilters = { [weak self] in self?.showFilters.record($0) }
    }
  }

  func assert_selectedSort_isDefault() {
    self.selectedSort.assertLastValue(.magic, "Selected sort should be default value")
  }

  func assert_selectedProjectState_isDefault() {
    self.selectedState.assertLastValue(.all, "Selected project state should be default value")
  }

  func assert_selectedCategory_isDefault() {
    self.selectedCategory.assertLastValue(nil, "Selected category should be default value")
  }

  func assert_selectedPercentRaisedBucket_isDefault() {
    self.selectedPercentRaisedBucket.assertLastValue(nil, "Selected % raised should be default value")
  }

  func assert_selectedLocation_isDefault() {
    self.selectedLocation.assertLastValue(nil, "Selected location should be default value")
  }

  func assert_selectedAmountRaisedBucket_isDefault() {
    self.selectedAmountRaisedBucket.assertLastValue(nil, "Selected amount raised should be default value")
  }

  func assert_selectedGoalBucket_isDefault() {
    self.selectedAmountRaisedBucket.assertLastValue(nil, "Selected amount raised should be default value")
  }

  func assert_toggles_areDefaults() {
    if let toggles = self.selectedToggles.lastValue {
      XCTAssertFalse(toggles.following)
      XCTAssertFalse(toggles.projectsWeLove)
      XCTAssertFalse(toggles.recommended)
      XCTAssertFalse(toggles.savedProjects)
    } else {
      XCTFail("Expected some toggles to be set")
    }
  }

  func test_allFilters_onInitialSignal_areDefaults() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.assertAllFilters_areSetToDefaults()
  }

  func test_sort_onInitialSignal_isRecommended() {
    self.selectedSort.assertDidNotEmitValue()

    self.searchFeature.filterSelection.publishInitialSelection()

    self.selectedSort.assertLastValue(.magic)
  }

  func test_tappedSort_showsSortOptions() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.showFilters.assertDidNotEmitValue()

    self.useCase.inputs.tappedButton(forFilterType: .sort)

    self.showFilters.assertDidEmitValue()

    if let type = self.showFilters.lastValue {
      XCTAssertEqual(type, .sort, "Tapping sort button should show sort options")
      XCTAssertGreaterThan(
        self.useCase.uiOutputs.searchFilters.sort.sortOptions.count,
        0,
        "There should be multiple sort options"
      )
    }

    XCTAssertEqual(
      self.useCase.uiOutputs.searchFilters.sort.selectedSort,
      .magic,
      "First option, magic, should be selected by default"
    )
  }

  func test_tappedCategories_showsCategoryFilters() {
    self.searchFeature.filterSelection.publishInitialSelection()
    self.searchFeature.publishCategories([
      .art,
      .illustration,
      .documentary,
      .tabletopGames
    ])

    self.showFilters.assertDidNotEmitValue()

    self.useCase.inputs.tappedButton(forFilterType: .category)

    self.showFilters.assertDidEmitValue()

    if let type = self.showFilters.lastValue {
      XCTAssertEqual(type, .category, "Tapping category button should show category filters")
      XCTAssertEqual(
        self.useCase.uiOutputs.searchFilters.category.categories.count,
        4,
        "The sheet should show the categories that were loaded"
      )
    }

    XCTAssertEqual(
      self.useCase.uiOutputs.searchFilters.category.selectedCategory,
      .none,
      "No category should be selected by default"
    )
  }

  func test_tappedProjectState_showsAllOptions() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.showFilters.assertDidNotEmitValue()

    self.useCase.inputs.tappedButton(forFilterType: .projectState)

    self.showFilters.assertDidEmitValue()

    if let type = self.showFilters.lastValue {
      XCTAssertEqual(type, .allFilters, "Tapping project state button should show all options")
      XCTAssertGreaterThan(
        self.useCase.uiOutputs.searchFilters.projectState.stateOptions.count,
        0,
        "There should be multiple project state options"
      )
    }

    XCTAssertEqual(
      self.useCase.uiOutputs.searchFilters.projectState.selectedProjectState,
      .all,
      "First option, All, should be selected by default"
    )
  }

  func test_tappedPercentRaised_showsPercentRaised() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.showFilters.assertDidNotEmitValue()

    self.useCase.inputs.tappedButton(forFilterType: .percentRaised)

    self.showFilters.assertDidEmitValue()

    if let type = self.showFilters.lastValue {
      XCTAssertEqual(type, .percentRaised, "Tapping percent raised button should percent raised options")
      XCTAssertGreaterThan(
        self.useCase.uiOutputs.searchFilters.percentRaised.buckets.count,
        0,
        "There should be multiple percent raised options"
      )
    }

    XCTAssertEqual(
      self.useCase.uiOutputs.searchFilters.percentRaised.selectedBucket,
      nil,
      "No option should be selected by default"
    )
  }

  func test_tappedAllFilters_showsAllOptions() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.showFilters.assertDidNotEmitValue()

    self.useCase.inputs.tappedButton(forFilterType: .allFilters)

    self.showFilters.assertDidEmitValue()

    if let type = self.showFilters.lastValue {
      XCTAssertEqual(type, .allFilters, "Tapping all filter button should show all filters")
    }
  }

  func test_tappedLocation_showsLocation() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.searchFeature.publishDefaultLocations(threeLocations)
    self.searchFeature.publishSuggestedLocations(threeLocations)

    self.showFilters.assertDidNotEmitValue()

    self.useCase.inputs.tappedButton(forFilterType: .location)

    self.showFilters.assertDidEmitValue()

    if let type = self.showFilters.lastValue {
      XCTAssertEqual(type, .location, "Tapping percent raised button should percent raised options")
      XCTAssertEqual(
        self.useCase.uiOutputs.searchFilters.location.defaultLocations.count,
        3,
        "There should be three default locations set"
      )
      XCTAssertEqual(
        self.useCase.uiOutputs.searchFilters.location.suggestedLocations.count,
        3,
        "There should be three suggested locations set"
      )
    }

    self.assert_selectedLocation_isDefault()
  }

  func testLookupRefreshAndClearPreserveSelectedFilters() {
    self.searchFeature.filterSelection.publishInitialSelection()
    let location = threeLocations[0]
    self.useCase.inputs.selectedFilter(.category(.rootCategory(.art)))
    self.useCase.inputs.selectedFilter(.location(location))
    let filters = self.useCase.uiOutputs.searchFilters

    self.searchFeature.publishCategories([.art, .illustration])
    self.searchFeature.publishDefaultLocations(threeLocations)
    self.searchFeature.publishSuggestedLocations([location])
    XCTAssertEqual(filters.category.categories, [.art, .illustration])
    XCTAssertEqual(filters.location.defaultLocations, threeLocations)
    XCTAssertEqual(filters.location.suggestedLocations, [location])

    self.searchFeature.publishCategories([])
    self.searchFeature.publishSuggestedLocations([])
    XCTAssertTrue(filters.category.categories.isEmpty)
    XCTAssertTrue(filters.location.suggestedLocations.isEmpty)
    XCTAssertEqual(filters.location.defaultLocations, threeLocations)
    XCTAssertEqual(filters.category.selectedCategory, .rootCategory(.art))
    XCTAssertEqual(filters.location.selectedLocation, location)
    XCTAssertEqual(filters.filterCount, 2)
    XCTAssertEqual(self.searchFeature.queryParameters(for: "art").location, location)
  }

  func testRepeatedLookupOutputsRetainPresentationNotifications() {
    let filters = self.useCase.uiOutputs.searchFilters
    var notifications = 0
    let observation = filters.objectWillChange.sink { notifications += 1 }
    defer { observation.cancel() }

    self.searchFeature.publishCategories([.art])
    self.searchFeature.publishCategories([.art])
    self.searchFeature.publishDefaultLocations([])
    self.searchFeature.publishSuggestedLocations([])

    XCTAssertEqual(notifications, 4, "Do not silently deduplicate legacy presentation updates")
    XCTAssertEqual(filters.category.categories, [.art])
  }

  func testReleasedAdapterStopsUpdatingRetainedPresentationModel() {
    self.searchFeature.filterSelection.publishInitialSelection()
    let filters = self.useCase.uiOutputs.searchFilters
    weak var weakAdapter = self.useCase
    self.useCase = nil
    XCTAssertNil(weakAdapter)

    self.searchFeature.publishCategories([.art])
    self.searchFeature.publishDefaultLocations(threeLocations)
    self.searchFeature.publishSuggestedLocations(threeLocations)
    self.searchFeature.selectFilter(.category(.rootCategory(.art)))

    XCTAssertTrue(filters.category.categories.isEmpty)
    XCTAssertTrue(filters.location.defaultLocations.isEmpty)
    XCTAssertTrue(filters.location.suggestedLocations.isEmpty)
    XCTAssertEqual(filters.category.selectedCategory, .none)
    XCTAssertEqual(self.searchFeature.queryParameters(for: "art").category, .art)
  }

  func test_tappedAmountRaised_showsAmountRaised() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.showFilters.assertDidNotEmitValue()

    self.useCase.inputs.tappedButton(forFilterType: .amountRaised)

    self.showFilters.assertDidEmitValue()

    if let type = self.showFilters.lastValue {
      XCTAssertEqual(type, .amountRaised, "Tapping amount raised button should amount raised options")
      XCTAssertGreaterThan(
        self.useCase.uiOutputs.searchFilters.amountRaised.buckets.count,
        0,
        "There should be multiple amount raised options"
      )
    }

    XCTAssertEqual(
      self.useCase.uiOutputs.searchFilters.amountRaised.selectedBucket,
      nil,
      "No option should be selected by default"
    )
  }

  func test_tappedGoal_showsGoal() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.showFilters.assertDidNotEmitValue()

    self.useCase.inputs.tappedButton(forFilterType: .goal)

    self.showFilters.assertDidEmitValue()

    if let type = self.showFilters.lastValue {
      XCTAssertEqual(type, .goal, "Tapping goal button should show goal options")
      XCTAssertGreaterThan(
        self.useCase.uiOutputs.searchFilters.goal.buckets.count,
        0,
        "There should be multiple goal options"
      )
    }

    XCTAssertEqual(
      self.useCase.uiOutputs.searchFilters.goal.selectedBucket,
      nil,
      "No option should be selected by default"
    )
  }

  func test_selectingCategory_updatesCategory() {
    self.searchFeature.filterSelection.publishInitialSelection()

    let categories: [KsApi.Category] = [
      .art,
      .illustration,
      .documentary,
      .tabletopGames
    ]

    self.searchFeature.publishCategories(categories)

    self.showFilters.assertDidNotEmitValue()
    self.assert_selectedCategory_isDefault()

    self.useCase.inputs.tappedButton(forFilterType: .category)
    self.showFilters.assertDidEmitValue()

    self.useCase.inputs.selectedFilter(.category(.rootCategory(.art)))

    guard let newCategory = self.selectedCategory.lastValue else {
      XCTFail("There should be a new selected category")
      return
    }

    XCTAssertEqual(newCategory, categories[0], "Should have selected the first category in the list")
  }

  func test_selectingSort_updatesSort() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.showFilters.assertDidNotEmitValue()
    self.selectedSort.assertLastValue(.magic)

    self.useCase.inputs.tappedButton(forFilterType: .sort)
    self.showFilters.assertDidEmitValue()

    self.useCase.inputs.selectedFilter(.sort(.endingSoon))

    guard let newSelectedSort = self.selectedSort.lastValue else {
      XCTFail("There should be a new selected sort option")
      return
    }

    XCTAssertEqual(newSelectedSort, .endingSoon, "Sort value should change when new sort is selected")
  }

  func test_selectingState_updatesState() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.assert_selectedProjectState_isDefault()

    self.useCase.inputs.selectedFilter(.projectState(.late_pledge))

    guard let newSelectedState = self.selectedState.lastValue else {
      XCTFail("There should be a new selected state")
      return
    }

    XCTAssertEqual(newSelectedState, .late_pledge, "State value should change when new state is selected")
  }

  func test_selectingPercentRaisedBucket_updatesBucket() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.assert_selectedPercentRaisedBucket_isDefault()

    self.useCase.inputs.selectedFilter(.percentRaised(.bucket_1))

    guard let newSelectedBucket = self.selectedPercentRaisedBucket.lastValue else {
      XCTFail("There should be a new selected bucket")
      return
    }

    XCTAssertEqual(newSelectedBucket, .bucket_1, "Percent raised value should change when bucket is selected")
  }

  func test_selectingAmountRaisedBucket_updatesBucket() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.assert_selectedAmountRaisedBucket_isDefault()

    self.useCase.inputs.selectedFilter(.amountRaised(.bucket_3))

    guard let newSelectedBucket = self.selectedAmountRaisedBucket.lastValue else {
      XCTFail("There should be a new selected bucket")
      return
    }

    XCTAssertEqual(newSelectedBucket, .bucket_3, "Amount raised value should change when bucket is selected")
  }

  func test_selectingLocation_updatesLocation() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.assert_selectedLocation_isDefault()

    let location = threeLocations[1]

    self.useCase.inputs.selectedFilter(.location(location))

    guard let newSelectedLocation = self.selectedLocation.lastValue else {
      XCTFail("There should be a new selected location")
      return
    }

    XCTAssertEqual(
      newSelectedLocation,
      location,
      "Selected location value should change when location is selected"
    )
  }

  func test_selectingToggles_updatesToggles() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.assert_toggles_areDefaults()

    self.useCase.inputs.selectedFilter(.following(true))
    if let toggles = self.selectedToggles.lastValue {
      XCTAssertTrue(toggles.following)
      XCTAssertFalse(toggles.projectsWeLove)
      XCTAssertFalse(toggles.recommended)
      XCTAssertFalse(toggles.savedProjects)
    } else {
      XCTFail()
    }

    self.useCase.inputs.selectedFilter(.projectsWeLove(true))
    if let toggles = self.selectedToggles.lastValue {
      XCTAssertTrue(toggles.following)
      XCTAssertTrue(toggles.projectsWeLove)
      XCTAssertFalse(toggles.recommended)
      XCTAssertFalse(toggles.savedProjects)
    } else {
      XCTFail()
    }

    self.useCase.inputs.selectedFilter(.recommended(true))
    if let toggles = self.selectedToggles.lastValue {
      XCTAssertTrue(toggles.following)
      XCTAssertTrue(toggles.projectsWeLove)
      XCTAssertTrue(toggles.recommended)
      XCTAssertFalse(toggles.savedProjects)
    } else {
      XCTFail()
    }

    self.useCase.inputs.selectedFilter(.savedProjects(true))
    if let toggles = self.selectedToggles.lastValue {
      XCTAssertTrue(toggles.following)
      XCTAssertTrue(toggles.projectsWeLove)
      XCTAssertTrue(toggles.recommended)
      XCTAssertTrue(toggles.savedProjects)
    } else {
      XCTFail()
    }
  }

  func test_selectingSort_updatesSortPill() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.selectedSort.assertLastValue(.magic)

    if let sortPill = self.useCase.uiOutputs.searchFilters.sortPill {
      XCTAssertEqual(
        sortPill.isHighlighted,
        false,
        "Sort pill should not be highlighted when default sort is selected"
      )
    } else {
      XCTFail("Expected sort pill to be set")
    }

    self.useCase.inputs.selectedFilter(.sort(.endingSoon))

    if let sortPill = self.useCase.uiOutputs.searchFilters.sortPill {
      XCTAssertEqual(
        sortPill.isHighlighted,
        true,
        "Sort pill should be highlighted when a non-default sort is selected"
      )
    } else {
      XCTFail("Expected sort pill to be set")
    }
  }

  func test_selectingCategory_updatesCategoryPill() {
    self.searchFeature.filterSelection.publishInitialSelection()
    self.searchFeature.publishCategories([
      .art,
      .illustration,
      .documentary,
      .tabletopGames
    ])

    self.assert_selectedCategory_isDefault()

    guard let categoryPill = self.useCase.uiOutputs.searchFilters.categoryPill else {
      XCTFail("Category pill is missing.")
      return
    }

    XCTAssertEqual(
      categoryPill.isHighlighted, false,
      "Category pill should not be highlighted when no category is selected"
    )

    guard case let .dropdown(title) = categoryPill.buttonType else {
      XCTFail("Category pill is not a dropdown")
      return
    }

    XCTAssertEqual(
      title, "Category",
      "Category pill should have placeholder text when no category is selected"
    )

    self.useCase.inputs.selectedFilter(.category(.subcategory(
      rootCategory: .art,
      subcategory: .illustration
    )))

    guard let newCategoryPill = self.useCase.uiOutputs.searchFilters.categoryPill else {
      XCTFail("Category pill is missing.")
      return
    }

    XCTAssertEqual(
      newCategoryPill.isHighlighted,
      true,
      "Category pill should be highlighted category is selected"
    )

    guard case let .dropdown(newTitle) = newCategoryPill.buttonType else {
      XCTFail("Category pill is not a dropdown")
      return
    }

    XCTAssertEqual(
      newTitle,
      "Illustration",
      "Category pill should have selected category title when category is selected"
    )
  }

  func test_selectingPercentRaised_updatesPercentRaisedPill() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.assert_selectedPercentRaisedBucket_isDefault()

    if let pill = self.useCase.uiOutputs.searchFilters.percentRaisedPill {
      XCTAssertEqual(
        pill.isHighlighted,
        false,
        "Percent raised pill should not be highlighted when no bucket is selected"
      )
    } else {
      XCTFail("Expected percent raised pill to be set")
    }

    self.useCase.inputs.selectedFilter(.percentRaised(.bucket_2))

    if let pill = self.useCase.uiOutputs.searchFilters.percentRaisedPill {
      XCTAssertEqual(
        pill.isHighlighted,
        true,
        "Percent raised pill should be highlighted when a non-default option is selected"
      )

      guard case let .dropdown(title) = pill.buttonType else {
        XCTFail("Pill is not a dropdown")
        return
      }

      XCTAssertEqual(
        title,
        DiscoveryParams.PercentRaisedBucket.bucket_2.pillTitle,
        "Dropdown should have description of selected % raised option in its title"
      )

    } else {
      XCTFail("Expected percent raised pill to be set")
    }
  }

  func test_selectingAmountRaised_updatesAmountRaisedPill() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.assert_selectedAmountRaisedBucket_isDefault()

    if let pill = self.useCase.uiOutputs.searchFilters.amountRaisedPill {
      XCTAssertEqual(
        pill.isHighlighted,
        false,
        "Amount raised pill should not be highlighted when no bucket is selected"
      )
    } else {
      XCTFail("Expected percent raised pill to be set")
    }

    self.useCase.inputs.selectedFilter(.amountRaised(.bucket_3))

    if let pill = self.useCase.uiOutputs.searchFilters.amountRaisedPill {
      XCTAssertEqual(
        pill.isHighlighted,
        true,
        "Amount raised pill should be highlighted when a non-default option is selected"
      )

      guard case let .dropdown(title) = pill.buttonType else {
        XCTFail("Pill is not a dropdown")
        return
      }

      XCTAssertEqual(
        title,
        DiscoveryParams.AmountRaisedBucket.bucket_3.pillTitle,
        "Dropdown should have description of selected amount raised option in its title"
      )

    } else {
      XCTFail("Expected percent raised pill to be set")
    }
  }

  func test_selectingLocation_updatesLocationPill() {
    self.searchFeature.filterSelection.publishInitialSelection()

    self.assert_selectedLocation_isDefault()

    if let pill = self.useCase.uiOutputs.searchFilters.locationPill {
      XCTAssertEqual(
        pill.isHighlighted,
        false,
        "Percent raised pill should not be highlighted when no location is selected"
      )
    } else {
      XCTFail("Expected location pill to be set")
    }

    let location = threeLocations[0]

    self.useCase.inputs.selectedFilter(.location(location))

    if let pill = self.useCase.uiOutputs.searchFilters.locationPill {
      XCTAssertEqual(
        pill.isHighlighted,
        true,
        "Location pill should be highlighted when a non-default option is selected"
      )

      guard case let .dropdown(title) = pill.buttonType else {
        XCTFail("Pill is not a dropdown")
        return
      }

      XCTAssertEqual(
        title,
        location.displayableName,
        "Dropdown should have description of selected location in its title"
      )

    } else {
      XCTFail("Expected location pill to be set")
    }
  }

  func test_userLoggedIn_showsUserTogglePills() {
    withEnvironment(currentUser: User.template) {
      self.searchFeature.filterSelection.publishInitialSelection()

      XCTAssertNotNil(self.useCase.uiOutputs.searchFilters.followingPill)
      XCTAssertNotNil(self.useCase.uiOutputs.searchFilters.projectsWeLovePill)
      XCTAssertNotNil(self.useCase.uiOutputs.searchFilters.recommendedPill)
      XCTAssertNotNil(self.useCase.uiOutputs.searchFilters.savedPill)
    }
  }

  func test_userLoggedOut_showsAnonymousTogglePills() {
    withEnvironment(currentUser: nil) {
      self.searchFeature.filterSelection.publishInitialSelection()

      XCTAssertNil(self.useCase.uiOutputs.searchFilters.followingPill)
      XCTAssertNotNil(self.useCase.uiOutputs.searchFilters.projectsWeLovePill)
      XCTAssertNil(self.useCase.uiOutputs.searchFilters.recommendedPill)
      XCTAssertNil(self.useCase.uiOutputs.searchFilters.savedPill)
    }
  }

  func assert_selectedToggle_updatesTogglePill(
    _ type: SearchFilterPill.FilterType,
    onEvent event: SearchFilterEvent
  ) {
    withEnvironment(currentUser: User.template) {
      self.searchFeature.filterSelection.publishInitialSelection()

      self.assert_toggles_areDefaults()

      if let pill = self.useCase.uiOutputs.searchFilters.pills.first(where: { $0.filterType == type }) {
        XCTAssertEqual(
          pill.isHighlighted,
          false,
          "Toggle pill should not be highlighted when toggle is off"
        )
      } else {
        XCTFail("Expected toggle pill to be set")
      }

      self.useCase.inputs.selectedFilter(event)

      if let pill = self.useCase.uiOutputs.searchFilters.pills.first(where: { $0.filterType == type }) {
        XCTAssertEqual(
          pill.isHighlighted,
          true,
          "Toggle pill should be highlighted when a non-default option is selected"
        )

      } else {
        XCTFail("Expected toggle pill to be set")
      }
    }
  }

  func test_selectingToggles_updatesTogglePills() {
    self.assert_selectedToggle_updatesTogglePill(.following, onEvent: .following(true))

    self.useCase.inputs.resetFilters(for: .allFilters)
    self.assert_selectedToggle_updatesTogglePill(.projectsWeLove, onEvent: .projectsWeLove(true))

    self.useCase.inputs.resetFilters(for: .allFilters)
    self.assert_selectedToggle_updatesTogglePill(.recommended, onEvent: .recommended(true))

    self.useCase.inputs.resetFilters(for: .allFilters)
    self.assert_selectedToggle_updatesTogglePill(.saved, onEvent: .savedProjects(true))
  }

  func test_tappingOnToggles_changesToggleValue_insteadOfShowingFilters() {
    withEnvironment(currentUser: User.template) {
      self.searchFeature.filterSelection.publishInitialSelection()
      self.assert_toggles_areDefaults()

      self.useCase.inputs.tappedButton(forFilterType: .following)
      self.useCase.inputs.tappedButton(forFilterType: .projectsWeLove)
      self.useCase.inputs.tappedButton(forFilterType: .recommended)
      self.useCase.inputs.tappedButton(forFilterType: .saved)

      if let toggles = self.selectedToggles.lastValue {
        XCTAssertTrue(toggles.following)
        XCTAssertTrue(toggles.projectsWeLove)
        XCTAssertTrue(toggles.recommended)
        XCTAssertTrue(toggles.savedProjects)
      }

      self.useCase.inputs.tappedButton(forFilterType: .following)
      self.useCase.inputs.tappedButton(forFilterType: .projectsWeLove)
      self.useCase.inputs.tappedButton(forFilterType: .recommended)
      self.useCase.inputs.tappedButton(forFilterType: .saved)

      if let toggles = self.selectedToggles.lastValue {
        XCTAssertFalse(toggles.following)
        XCTAssertFalse(toggles.projectsWeLove)
        XCTAssertFalse(toggles.recommended)
        XCTAssertFalse(toggles.savedProjects)
      }

      self.showFilters.assertDidNotEmitValue("Tapping on a toggle filter shouldn't show any filter modals")
    }
  }

  func setAllFilters_toNonDefault_andAssert() {
    self.searchFeature.publishCategories([
      .art,
      .documentary,
      .documentarySpanish
    ])

    self.useCase.inputs.selectedFilter(.category(.rootCategory(.art)))
    self.selectedCategory.assertLastValue(.art)

    self.useCase.inputs.selectedFilter(.projectState(.late_pledge))
    self.selectedState.assertLastValue(.late_pledge)

    self.useCase.inputs.selectedFilter(.percentRaised(.bucket_2))
    self.selectedPercentRaisedBucket.assertLastValue(.bucket_2)

    self.useCase.inputs.selectedFilter(.following(true))
    self.useCase.inputs.selectedFilter(.projectsWeLove(true))
    self.useCase.inputs.selectedFilter(.savedProjects(true))
    self.useCase.inputs.selectedFilter(.recommended(true))

    for type in SearchFilterModalType.allCases {
      if type == .sort {
        // Sort is a special case and not a "filter" per se
        return
      }
      XCTAssertTrue(
        self.useCase.uiOutputs.searchFilters.has(filter: type),
        "Expected setAllFilters_toNonDefault_andAssert to set non-default value for \(type)"
      )
    }
  }

  func assertAllFilters_areSetToDefaults() {
    self.assert_selectedCategory_isDefault()
    self.assert_selectedProjectState_isDefault()
    self.assert_selectedPercentRaisedBucket_isDefault()
    self.assert_selectedLocation_isDefault()
    self.assert_selectedAmountRaisedBucket_isDefault()
    self.assert_toggles_areDefaults()

    for type in SearchFilterModalType.allCases {
      if type == .sort {
        // Sort is a special case and not a "filter" per se
        return
      }
      XCTAssertFalse(
        self.useCase.uiOutputs.searchFilters.has(filter: type),
        "Expected default value to be set for \(type)"
      )
    }
  }

  func test_clearQueryText_resetsSort_andClearsFilters() {
    self.searchFeature.filterSelection.publishInitialSelection()
    self.searchFeature.publishCategories([
      .art
    ])

    self.assert_selectedSort_isDefault()
    self.assertAllFilters_areSetToDefaults()

    self.useCase.inputs.selectedFilter(.sort(.endingSoon))
    self.setAllFilters_toNonDefault_andAssert()

    self.useCase.inputs.clearedQueryText()

    self.assert_selectedSort_isDefault()
    self.assertAllFilters_areSetToDefaults()
  }

  func test_resetAllFilters_resetsAllFilters() {
    self.searchFeature.filterSelection.publishInitialSelection()
    self.searchFeature.publishCategories([
      .art,
      .documentary,
      .documentarySpanish
    ])

    self.setAllFilters_toNonDefault_andAssert()

    XCTAssertTrue(self.useCase.searchFilters.canReset(filter: .allFilters))

    self.useCase.resetFilters(for: .allFilters)

    self.assertAllFilters_areSetToDefaults()
  }

  func test_resetFiltersForType_resetsOnlySpecificFilters() {
    self.searchFeature.filterSelection.publishInitialSelection()

    for type in SearchFilterModalType.allCases {
      XCTAssertFalse(
        self.useCase.uiOutputs.searchFilters.canReset(filter: type),
        "Reset should be disabled because no filters were set"
      )
    }

    let filterTypes = [SearchFilterModalType.category, SearchFilterModalType.percentRaised]

    for type in filterTypes {
      self.setAllFilters_toNonDefault_andAssert()

      XCTAssertTrue(self.useCase.uiOutputs.searchFilters.has(filter: type))
      XCTAssertTrue(self.useCase.uiOutputs.searchFilters.canReset(filter: type))
      self.useCase.inputs.resetFilters(for: type)
      XCTAssertFalse(
        self.useCase.uiOutputs.searchFilters.has(filter: type),
        "Resetting filter of type \(type) should have set it back to its default value"
      )

      // Make sure the other filters didn't get reset, too
      for otherFilterType in filterTypes {
        if otherFilterType == type {
          continue
        }
        XCTAssertTrue(
          self.useCase.uiOutputs.searchFilters.canReset(filter: otherFilterType),
          "Resetting a filter of type \(type) should not have reset the filter of type \(otherFilterType)"
        )
      }
    }
  }
}

private let threeLocations = [
  Location(
    country: "US",
    displayableName: "Somerville, MA",
    id: 1,
    localizedName: "Somerville, MA",
    name: "Somerville, MA"
  ),
  Location(
    country: "US",
    displayableName: "Cambridge, MA",
    id: 2,
    localizedName: "Cambridge, MA",
    name: "Cambridge, MA"
  ),
  Location(
    country: "US",
    displayableName: "Allston, MA",
    id: 3,
    localizedName: "Allston, MA",
    name: "Allston, MA"
  )
]

private final class FilterRecorder<Value> {
  private(set) var values: [Value] = []
  var lastValue: Value? { self.values.last }
  func record(_ value: Value) { self.values.append(value) }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, message, file: file, line: line)
  }
  func assertDidEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(self.values.isEmpty, message, file: file, line: line)
  }
  func assertLastValue(_ value: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) where Value: Equatable {
    XCTAssertEqual(self.values.last, value, message, file: file, line: line)
  }
}
