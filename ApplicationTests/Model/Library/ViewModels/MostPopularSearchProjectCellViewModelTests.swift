@testable import Kickstarter_iOS
import KDS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class MostPopularSearchProjectCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  private let vm = MostPopularSearchProjectCellViewModel()

  func testProjectData_Live() {
    let project = .cosmicSurgery
      |> Project.lens.stats.fundingProgress .~ 0.5
      |> Project.lens.state .~ .live
      |> Project.lens.photo.full .~ "http://wwww.cosmicsurgery.com/theproject.jpg"

    self.vm.configureWith(project: project)

    XCTAssertEqual(self.vm.metadataText, "15 days")
    XCTAssertEqual(self.vm.percentFundedText.string, "50%")
    XCTAssertEqual(self.vm.progress, 0.5)
    XCTAssertEqual(self.vm.progressBarColor, LegacyColors.ksr_create_700.uiColor())
    XCTAssertEqual(self.vm.projectImageUrl?.absoluteString ?? "", "http://wwww.cosmicsurgery.com/theproject.jpg")
    XCTAssertEqual(self.vm.projectName.string, "Cosmic Surgery")
  }

  func testProjectData_Successful() {
    let project = .cosmicSurgery
      |> Project.lens.stats.fundingProgress .~ 2.25
      |> Project.lens.state .~ .successful
      |> Project.lens.photo.full .~ "http://wwww.cosmicsurgery.com/theproject.jpg"

    self.vm.configureWith(project: project)

    XCTAssertEqual(self.vm.metadataText, "Successful")
    XCTAssertEqual(self.vm.percentFundedText.string, "225%")
    XCTAssertEqual(self.vm.progress, 2.25)
    XCTAssertEqual(self.vm.progressBarColor, LegacyColors.ksr_create_700.uiColor())
    XCTAssertEqual(self.vm.projectImageUrl?.absoluteString ?? "", "http://wwww.cosmicsurgery.com/theproject.jpg")
    XCTAssertEqual(self.vm.projectName.string, "Cosmic Surgery")
  }

  func testProjectData_Failure() {
    let project = .cosmicSurgery
      |> Project.lens.stats.fundingProgress .~ 0.25
      |> Project.lens.state .~ .failed
      |> Project.lens.photo.full .~ "http://wwww.cosmicsurgery.com/theproject.jpg"

    self.vm.configureWith(project: project)

    XCTAssertEqual(self.vm.metadataText, "Unsuccessful")
    XCTAssertEqual(self.vm.percentFundedText.string, "25%")
    XCTAssertEqual(self.vm.progress, 0.25)
    XCTAssertEqual(self.vm.progressBarColor, LegacyColors.ksr_support_400.uiColor())
    XCTAssertEqual(self.vm.projectImageUrl?.absoluteString ?? "", "http://wwww.cosmicsurgery.com/theproject.jpg")
    XCTAssertEqual(self.vm.projectName.string, "Cosmic Surgery")
  }

  func testProjectData_Canceled() {
    let project = .cosmicSurgery
      |> Project.lens.stats.fundingProgress .~ 0.15
      |> Project.lens.state .~ .canceled
      |> Project.lens.photo.full .~ "http://wwww.cosmicsurgery.com/theproject.jpg"

    self.vm.configureWith(project: project)

    XCTAssertEqual(self.vm.metadataText, "Canceled")
    XCTAssertEqual(self.vm.percentFundedText.string, "15%")
    XCTAssertEqual(self.vm.progress, 0.15)
    XCTAssertEqual(self.vm.progressBarColor, LegacyColors.ksr_support_400.uiColor())
    XCTAssertEqual(self.vm.projectImageUrl?.absoluteString ?? "", "http://wwww.cosmicsurgery.com/theproject.jpg")
    XCTAssertEqual(self.vm.projectName.string, "Cosmic Surgery")
  }

  func testProjectData_Prelaunch() {
    let project = .template
      |> Project.lens.name .~ "Best of Lazy Bathtub Cat"
      |> Project.lens.photo.full .~ "http://www.lazybathtubcat.com/vespa.jpg"
      |> Project.lens.displayPrelaunch .~ true
      |> Project.lens.prelaunchActivated .~ true
      |> Project.lens.personalization.isStarred .~ true

    XCTAssertFalse(self.vm.prelaunchProject)

    self.vm.configureWith(project: project)

    XCTAssertEqual(self.vm.prelaunchProject, true)
  }
}

@MainActor
final class SearchEmptyStateNativeStateTests: XCTestCase {
  func testQueryAndFilterCombinationsAndReuse() {
    let model = SearchEmptyStateCellViewModel()
    model.configureWith(data: .init(query: "cats", hasFilters: true))
    XCTAssertEqual(model.titleText, Strings.No_results_for(query: "cats"))
    XCTAssertEqual(model.subtitleText, Strings.Try_rephrasing_your_search_or_adjusting_the_filters())
    XCTAssertFalse(model.hideClearFiltersButton)

    model.configureWith(data: .init(query: nil, hasFilters: true))
    XCTAssertEqual(model.titleText, Strings.No_results())
    XCTAssertEqual(model.subtitleText, Strings.Try_adjusting_the_filters())
    XCTAssertFalse(model.hideClearFiltersButton)

    model.configureWith(data: .init(query: "", hasFilters: false))
    XCTAssertEqual(model.titleText, Strings.No_results())
    XCTAssertEqual(model.subtitleText, Strings.Try_rephrasing_your_search())
    XCTAssertTrue(model.hideClearFiltersButton)
  }
}
