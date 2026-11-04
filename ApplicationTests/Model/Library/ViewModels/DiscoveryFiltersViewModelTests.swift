@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

// A whole bunch of data to play around with in tests.
private let selectableRowTemplate = SelectableRow(
  isSelected: false,
  params: .defaults
)
private let expandableRowTemplate = ExpandableRow(
  isExpanded: false,
  params: .defaults,
  selectableRows: []
)

private let allProjectsRow = selectableRowTemplate |> SelectableRow.lens.params.includePOTD .~ true
private let staffPicksRow = selectableRowTemplate |> SelectableRow.lens.params.staffPicks .~ true
private let starredRow = selectableRowTemplate |> SelectableRow.lens.params.starred .~ true
private let socialRow = selectableRowTemplate |> SelectableRow.lens.params.social .~ true
private let recommendedRow = selectableRowTemplate
  |> SelectableRow.lens.params.recommended .~ true
  |> SelectableRow.lens.params.backed .~ false

private let artSelectableRow = selectableRowTemplate |> SelectableRow.lens.params.category .~ .art
private let documentarySelectableRow = selectableRowTemplate
  |> SelectableRow.lens.params.category .~ .documentary

private let artExpandableRow = expandableRowTemplate
  |> ExpandableRow.lens.params.category .~ .art
  |> ExpandableRow.lens.selectableRows .~ [
    artSelectableRow,
    selectableRowTemplate |> SelectableRow.lens.params.category .~ .illustration
  ]

private let filmExpandableRow = expandableRowTemplate
  |> ExpandableRow.lens.params.category .~ .filmAndVideo
  |> ExpandableRow.lens.selectableRows .~ [
    selectableRowTemplate |> SelectableRow.lens.params.category .~ .filmAndVideo,
    selectableRowTemplate |> SelectableRow.lens.params.category .~ .documentary
  ]

private let categories =
  [
    Category.art,
    Category.filmAndVideo
  ]

@MainActor
internal final class DiscoveryFiltersViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private lazy var vm: DiscoveryFiltersViewModel = {
    let vm = DiscoveryFiltersViewModel()
    vm.onAnimateIn = { [weak self] in self?.animateInView.observer.send(value: ()) }
    vm.onLoading = { [weak self] in self?.loadingIndicatorisVisible.observer.send(value: $0) }
    vm.onCategoryRows = { [weak self] rows, initial, selected in
      self?.loadCategoryRows.observer.send(value: rows)
      self?.loadCategoryRowsInitialId.observer.send(value: initial)
      self?.loadCategoryRowsSelectedId.observer.send(value: selected)
    }
    vm.onTopRows = { [weak self] rows, id in
      self?.loadTopRows.observer.send(value: rows); self?.loadTopRowsInitialId.observer.send(value: id)
    }
    vm.onFavoriteRows = { [weak self] rows, id in
      self?.loadFavoriteRows.observer.send(value: rows); self?.loadFavoriteRowsId.observer.send(value: id)
    }
    vm.onSelectedRow = { [weak self] in self?.notifyDelegateOfSelectedRow.observer.send(value: $0) }
    return vm
  }()

  private var defaultRootCategoriesTemplate: RootCategoriesEnvelope {
    RootCategoriesEnvelope.template
      |> RootCategoriesEnvelope.lens.categories .~ [
        .art,
        .filmAndVideo,
        .illustration,
        .documentary
      ]
  }

  private let animateInView = TestObserver<(), Never>()
  private let loadCategoryRows = TestObserver<[ExpandableRow], Never>()
  private let loadCategoryRowsInitialId = TestObserver<Int?, Never>()
  private let loadCategoryRowsSelectedId = TestObserver<Int?, Never>()
  private let loadingIndicatorisVisible = TestObserver<Bool, Never>()
  private let loadTopRows = TestObserver<[SelectableRow], Never>()
  private let loadTopRowsInitialId = TestObserver<Int?, Never>()
  private let notifyDelegateOfSelectedRow = TestObserver<SelectableRow, Never>()
  private let loadFavoriteRows = TestObserver<[SelectableRow], Never>()
  private let loadFavoriteRowsId = TestObserver<Int?, Never>()

  private let categoriesResponse = RootCategoriesEnvelope.template
    |> RootCategoriesEnvelope.lens.categories .~ categories



  func testCachedCategoriesArrivingBeforeConfigurationAreDisplayed() async {
    AppEnvironment.current.cache[KSCache.ksr_discoveryFiltersCategories] = categories
    defer { AppEnvironment.current.cache.removeAllObjects() }
    self.vm.viewDidLoad()
    self.loadCategoryRows.assertValueCount(0)
    self.vm.configureWith(selectedRow: allProjectsRow)
    self.loadCategoryRows.assertValueCount(1)
    XCTAssertEqual(self.loadCategoryRows.values.first?.count, 2)
  }

  func testAnimateIn() async {
    self.vm.configureWith(selectedRow: allProjectsRow)
    self.vm.viewDidLoad()

    await self.vm.loadCategories()

    self.animateInView.assertValueCount(0)

    self.vm.viewDidAppear()

    self.animateInView.assertValueCount(1)
  }

  func testKSRAnalyticsEventsTrack() async {
    self.vm.configureWith(selectedRow: allProjectsRow)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    await self.vm.loadCategories()

    XCTAssertEqual(
      [],
      self.segmentTrackingClient.events
    )
    self.vm.tapped(expandableRow: filmExpandableRow)

    XCTAssertEqual(
      [],
      self.segmentTrackingClient.events
    )

    self.vm.tapped(selectableRow: documentarySelectableRow)

    XCTAssertEqual(["CTA Clicked"], self.segmentTrackingClient.events)
    XCTAssertEqual(
      [Category.documentary.intID],
      self.segmentTrackingClient.properties(forKey: "discover_subcategory_id", as: Int.self)
    )
    XCTAssertEqual("discover", segmentTrackingClient.properties.last?["context_page"] as? String)
    XCTAssertEqual("subcategory_name", segmentTrackingClient.properties.last?["context_type"] as? String)
    XCTAssertEqual("discover_overlay", segmentTrackingClient.properties.last?["context_location"] as? String)
    XCTAssertEqual("category_home", segmentTrackingClient.properties.last?["discover_ref_tag"] as? String)
    XCTAssertEqual(
      "Documentary",
      segmentTrackingClient.properties.last?["discover_subcategory_name"] as? String
    )
    XCTAssertEqual(
      "Film & Video",
      segmentTrackingClient.properties.last?["discover_category_name"] as? String
    )
    XCTAssertEqual(11, segmentTrackingClient.properties.last?["discover_category_id"] as? Int)
    XCTAssertEqual(30, segmentTrackingClient.properties.last?["discover_subcategory_id"] as? Int)

    self.vm.tapped(selectableRow: socialRow)

    XCTAssertEqual(["CTA Clicked", "CTA Clicked"], self.segmentTrackingClient.events)
    XCTAssertEqual("discover", segmentTrackingClient.properties.last?["context_page"] as? String)
    XCTAssertEqual("social", segmentTrackingClient.properties.last?["context_type"] as? String)
    XCTAssertEqual("discover_overlay", segmentTrackingClient.properties.last?["context_location"] as? String)
    XCTAssertEqual("social_home", segmentTrackingClient.properties.last?["discover_ref_tag"] as? String)

    self.vm.tapped(selectableRow: staffPicksRow)

    XCTAssertEqual(
      ["CTA Clicked", "CTA Clicked", "CTA Clicked"],
      self.segmentTrackingClient.events
    )
    XCTAssertEqual("discover", self.segmentTrackingClient.properties.last?["context_page"] as? String)
    XCTAssertEqual("pwl", self.segmentTrackingClient.properties.last?["context_type"] as? String)
    XCTAssertEqual(
      "discover_overlay",
      self.segmentTrackingClient.properties.last?["context_location"] as? String
    )
    XCTAssertEqual(
      "recommended_home",
      self.segmentTrackingClient.properties.last?["discover_ref_tag"] as? String
    )

    self.vm.tapped(selectableRow: starredRow)

    XCTAssertEqual(
      ["CTA Clicked", "CTA Clicked", "CTA Clicked", "CTA Clicked"],
      self.segmentTrackingClient.events
    )
    XCTAssertEqual("discover", self.segmentTrackingClient.properties.last?["context_page"] as? String)
    XCTAssertEqual("watched", self.segmentTrackingClient.properties.last?["context_type"] as? String)
    XCTAssertEqual(
      "discover_overlay",
      self.segmentTrackingClient.properties.last?["context_location"] as? String
    )
    XCTAssertEqual("starred_home", self.segmentTrackingClient.properties.last?["discover_ref_tag"] as? String)

    self.vm.tapped(selectableRow: recommendedRow)

    XCTAssertEqual(
      ["CTA Clicked", "CTA Clicked", "CTA Clicked", "CTA Clicked", "CTA Clicked"],
      self.segmentTrackingClient.events
    )
    XCTAssertEqual("discover", self.segmentTrackingClient.properties.last?["context_page"] as? String)
    XCTAssertEqual("recommended", self.segmentTrackingClient.properties.last?["context_type"] as? String)
    XCTAssertEqual(
      "discover_overlay",
      self.segmentTrackingClient.properties.last?["context_location"] as? String
    )
    XCTAssertEqual("recs_home", self.segmentTrackingClient.properties.last?["discover_ref_tag"] as? String)
  }

  func testTopFilters_Logged_Out() async {
    self.vm.configureWith(selectedRow: allProjectsRow)

    self.loadTopRows.assertValueCount(0)

    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    await self.vm.loadCategories()

    self.loadTopRows.assertValues(
      [
        [
          allProjectsRow
            |> SelectableRow.lens.isSelected .~ true,
          staffPicksRow
        ]
      ],
      "The top filter rows load immediately with the first one selected."
    )

    self.loadTopRowsInitialId.assertValues([nil])
  }

  func testTopFilters_Logged_In() async {
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: .template))

    self.vm.configureWith(selectedRow: allProjectsRow)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    await self.vm.loadCategories()

    self.loadTopRows.assertValues(
      [
        [
          allProjectsRow
            |> SelectableRow.lens.isSelected .~ true,
          staffPicksRow,
          starredRow,
          recommendedRow,
          socialRow
        ]
      ],
      "The top filter rows load immediately with the first one selected."
    )
    self.loadTopRowsInitialId.assertValues([nil])
  }

  func testTopFilters_Logged_In_Social() async {
    AppEnvironment.login(
      AccessTokenEnvelope(accessToken: "deadbeef", user: .template |> \.social .~ true)
    )

    self.vm.configureWith(selectedRow: allProjectsRow)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    await self.vm.loadCategories()

    self.loadTopRows.assertValues(
      [
        [
          allProjectsRow
            |> SelectableRow.lens.isSelected .~ true,
          staffPicksRow,
          starredRow,
          recommendedRow,
          socialRow
        ]
      ],
      "The top filter rows load immediately with the first one selected."
    )
    self.loadTopRowsInitialId.assertValues([nil])
  }

  func testTopFilters_Logged_In_OptedOutOfRecommendations() async {
    AppEnvironment.login(
      AccessTokenEnvelope(
        accessToken: "deadbeef", user: .template
          |> \.optedOutOfRecommendations .~ true
      )
    )

    self.vm.configureWith(selectedRow: allProjectsRow)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    await self.vm.loadCategories()

    self.loadTopRows.assertValues(
      [
        [
          allProjectsRow
            |> SelectableRow.lens.isSelected .~ true,
          staffPicksRow,
          starredRow,
          socialRow
        ]
      ],
      "The top filter rows load immediately with the first one selected."
    )
    self.loadTopRowsInitialId.assertValues([nil])
  }

  func testTopFilters_Category_Selected() async {
    self.vm.configureWith(selectedRow: artSelectableRow)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    await self.vm.loadCategories()

    self.loadTopRows.assertValues(
      [
        [
          allProjectsRow,
          staffPicksRow
        ]
      ]
    )
    self.loadTopRowsInitialId.assertValues([1])
  }

  func testExpandingCategoryFilters() async {
    await withEnvironment(apiService: MockService(fetchGraphCategoriesResult: .success(
      self
        .defaultRootCategoriesTemplate
    ))) {
      self.vm.configureWith(selectedRow: allProjectsRow)

      self.loadCategoryRows.assertValueCount(0)
      self.loadingIndicatorisVisible.assertValueCount(0)

      self.vm.viewDidLoad()
      self.vm.viewDidAppear()

      self.loadingIndicatorisVisible.assertValues([true])

      await self.vm.loadCategories()

      self.loadingIndicatorisVisible.assertValues([true, false])

      self.loadCategoryRows.assertValues(
        [[artExpandableRow, filmExpandableRow]],
        "The root categories emit."
      )
      self.loadCategoryRowsInitialId.assertValues([nil])
      self.loadCategoryRowsSelectedId.assertValues([nil])

      // Expand art
      self.vm.tapped(expandableRow: artExpandableRow)

      self.loadCategoryRows.assertValues(
        [
          [artExpandableRow, filmExpandableRow],
          [artExpandableRow |> ExpandableRow.lens.isExpanded .~ true, filmExpandableRow]
        ],
        "The art category expands."
      )
      self.loadCategoryRowsInitialId.assertValues([nil, nil])
      self.loadCategoryRowsSelectedId.assertValues([nil, 1])

      // Expand film
      self.vm.tapped(expandableRow: filmExpandableRow)

      self.loadCategoryRows.assertValues(
        [
          [artExpandableRow, filmExpandableRow],
          [artExpandableRow |> ExpandableRow.lens.isExpanded .~ true, filmExpandableRow],
          [artExpandableRow, filmExpandableRow |> ExpandableRow.lens.isExpanded .~ true]
        ],
        "The art category collapses and the film category expands."
      )
      self.loadCategoryRowsInitialId.assertValues([nil, nil, nil])
      self.loadCategoryRowsSelectedId.assertValues([nil, 1, 11])

      // Collapse the expanded film row
      self.vm.tapped(expandableRow: filmExpandableRow |> ExpandableRow.lens.isExpanded .~ true)

      self.loadCategoryRows.assertValues(
        [
          [artExpandableRow, filmExpandableRow],
          [artExpandableRow |> ExpandableRow.lens.isExpanded .~ true, filmExpandableRow],
          [artExpandableRow, filmExpandableRow |> ExpandableRow.lens.isExpanded .~ true],
          [artExpandableRow, filmExpandableRow]
        ],
        "The film category collapses."
      )
      self.loadCategoryRowsInitialId.assertValues([nil, nil, nil, nil])
      self.loadCategoryRowsSelectedId.assertValues([nil, 1, 11, 11])
    }
  }

  func testConfigureWithSelectedRow() async {
    let artSelectedExpandedRow = expandableRowTemplate
      |> ExpandableRow.lens.params.category .~ .art
      |> ExpandableRow.lens.isExpanded .~ true
      |> ExpandableRow.lens.selectableRows .~ [
        artSelectableRow |> SelectableRow.lens.isSelected .~ true,
        selectableRowTemplate |> SelectableRow.lens.params.category .~ .illustration
      ]

    await withEnvironment(apiService: MockService(fetchGraphCategoriesResult: .success(
      self
        .defaultRootCategoriesTemplate
    ))) {
      self.vm.configureWith(selectedRow: artSelectableRow)

      self.loadCategoryRows.assertValueCount(0)

      self.vm.viewDidLoad()
      self.vm.viewDidAppear()

      self.loadingIndicatorisVisible.assertValues([true])

      await self.vm.loadCategories()

      self.loadingIndicatorisVisible.assertValues([true, false])

      self.loadCategoryRows.assertValues(
        [
          [artSelectedExpandedRow, filmExpandableRow]
        ],
        "The art category expands."
      )
      self.loadCategoryRowsInitialId.assertValues([1])
      self.loadCategoryRowsSelectedId.assertValues([1])
    }
  }

  func testTappingSelectableRow() async {
    self.vm.configureWith(selectedRow: allProjectsRow)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    await self.vm.loadCategories()

    self.vm.tapped(selectableRow: allProjectsRow)

    self.notifyDelegateOfSelectedRow.assertValues(
      [allProjectsRow],
      "The tapped row emits."
    )

    XCTAssertEqual(["CTA Clicked"], self.segmentTrackingClient.events)
    XCTAssertEqual("discover", self.segmentTrackingClient.properties.last?["context_page"] as? String)
    XCTAssertEqual("all", self.segmentTrackingClient.properties.last?["context_type"] as? String)
    XCTAssertEqual(
      "discover_overlay",
      self.segmentTrackingClient.properties.last?["context_location"] as? String
    )
    XCTAssertEqual(true, self.segmentTrackingClient.properties.last?["discover_everything"] as? Bool)
    XCTAssertEqual(
      "discovery_home",
      self.segmentTrackingClient.properties.last?["discover_ref_tag"] as? String
    )
  }

  func testFavoriteRows_Without_Favorites() async {
    self.vm.configureWith(selectedRow: allProjectsRow)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    await self.vm.loadCategories()

    self.loadFavoriteRows.assertValueCount(0, "Favorite rows does not emit without favorites set.")
  }

  func testFavoriteRows_With_Favorites() async {
    await withEnvironment(apiService: MockService(fetchGraphCategoriesResult: .success(self.categoriesResponse))) {
      self.ubiquitousStore.favoriteCategoryIds = [1, 30]

      self.vm.configureWith(selectedRow: allProjectsRow)

      self.loadFavoriteRows.assertValueCount(0)

      self.vm.viewDidLoad()
      self.vm.viewDidAppear()

      await self.vm.loadCategories()

      self.loadFavoriteRows.assertValues([[artSelectableRow, documentarySelectableRow]])
      self.loadFavoriteRowsId.assertValues([nil])
    }
  }

  func testFavoriteRows_With_Favorites_Selected() async {
    await withEnvironment(apiService: MockService(fetchGraphCategoriesResult: .success(
      self
        .defaultRootCategoriesTemplate
    ))) {
      self.ubiquitousStore.favoriteCategoryIds = [1, 30]

      self.vm.configureWith(selectedRow: artSelectableRow)

      self.loadFavoriteRows.assertValueCount(0)

      self.vm.viewDidLoad()
      self.vm.viewDidAppear()

      await self.vm.loadCategories()

      self.loadFavoriteRows.assertValues([
        [
          artSelectableRow |> SelectableRow.lens.isSelected .~ true,
          documentarySelectableRow
        ]
      ])
      self.loadFavoriteRowsId.assertValues([1])
    }
  }

  func testCategoriesFromCache() async {
    self.cache[KSCache.ksr_discoveryFiltersCategories] = categories

    self.vm.configureWith(selectedRow: allProjectsRow)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    self.loadingIndicatorisVisible.assertValueCount(0)

    self.loadCategoryRows.assertValues(
      [[artExpandableRow, filmExpandableRow]],
      "Server did not advance, categories loaded from cache."
    )
  }
}
