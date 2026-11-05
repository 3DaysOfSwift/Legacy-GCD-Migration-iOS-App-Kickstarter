@testable import Kickstarter_iOS
import KDS
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class ProjectPamphletMainCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = ProjectPamphletMainCellViewModel()

  private let backingLabelHidden = PamphletRecorder<Bool>()
  private let backersTitleLabelText = PamphletRecorder<String>()
  private let conversionLabelHidden = PamphletRecorder<Bool>()
  private let conversionLabelText = PamphletRecorder<String>()
  private let creatorImageUrl = PamphletRecorder<String?>()
  private let creatorLabelText = PamphletRecorder<String>()
  private let deadlineSubtitleLabelText = PamphletRecorder<String>()
  private let deadlineTitleLabelText = PamphletRecorder<String>()
  private let fundingProgressBarViewBackgroundColor = PamphletRecorder<UIColor>()
  private let isPrelaunchProject = PamphletRecorder<Bool>()
  private let notifyDelegateToGoToCreator = PamphletRecorder<any ProjectPamphletMainCellConfiguration>()
  private let opacityForViews = PamphletRecorder<CGFloat>()
  private let pledgedSubtitleLabelText = PamphletRecorder<String>()
  private let pledgedTitleLabelText = PamphletRecorder<String>()
  private let pledgedTitleLabelTextColor = PamphletRecorder<UIColor>()
  private let prelaunchProjectBackingText = PamphletRecorder<String>()
  private let progressPercentage = PamphletRecorder<Float>()
  private let projectBlurbLabelText = PamphletRecorder<String>()
  private let projectImageUrl = PamphletRecorder<String?>()
  private let projectNameLabelText = PamphletRecorder<String>()
  private let projectStateLabelText = PamphletRecorder<String>()
  private let projectStateLabelTextColor = PamphletRecorder<UIColor>()
  private let projectUnsuccessfulLabelTextColor = PamphletRecorder<UIColor>()
  private let stateLabelHidden = PamphletRecorder<Bool>()
  private let statsStackViewAccessibilityLabel = PamphletRecorder<String>()

  override func setUp() async throws {
    try await super.setUp()

    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case .backersSubtitleLabelText: break
      case let .backersTitleLabelText(value): self.backersTitleLabelText.record(value)
      case .categoryNameLabelText: break
      case .configureVideoPlayerController: break
      case let .conversionLabelHidden(value): self.conversionLabelHidden.record(value)
      case let .conversionLabelText(value): self.conversionLabelText.record(value)
      case let .creatorImageUrl(value): self.creatorImageUrl.record(value?.absoluteString)
      case let .creatorLabelText(value): self.creatorLabelText.record(value)
      case let .deadlineSubtitleLabelText(value): self.deadlineSubtitleLabelText.record(value)
      case let .deadlineTitleLabelText(value): self.deadlineTitleLabelText.record(value)
      case let .fundingProgressBarViewBackgroundColor(value): self.fundingProgressBarViewBackgroundColor.record(value)
      case let .isPrelaunchProject(value): self.isPrelaunchProject.record(value)
      case .locationNameLabelText: break
      case .locationStackViewHidden: break
      case let .notifyDelegateToGoToCreator(value): self.notifyDelegateToGoToCreator.record(value)
      case .notifyDelegateToGoToProjectNotice: break
      case let .opacityForViews(value): self.opacityForViews.record(value)
      case let .pledgedSubtitleLabelText(value): self.pledgedSubtitleLabelText.record(value)
      case let .pledgedTitleLabelText(value): self.pledgedTitleLabelText.record(value)
      case let .pledgedTitleLabelTextColor(value): self.pledgedTitleLabelTextColor.record(value)
      case let .prelaunchProjectBackingText(value): self.prelaunchProjectBackingText.record(value)
      case let .progressPercentage(value): self.progressPercentage.record(value)
      case let .projectBlurbLabelText(value): self.projectBlurbLabelText.record(value)
      case let .projectImageUrl(value): self.projectImageUrl.record(value?.absoluteString)
      case let .projectNameLabelText(value): self.projectNameLabelText.record(value)
      case let .projectStateLabelText(value): self.projectStateLabelText.record(value)
      case let .projectStateLabelTextColor(value): self.projectStateLabelTextColor.record(value)
      case let .projectUnsuccessfulLabelTextColor(value): self.projectUnsuccessfulLabelTextColor.record(value)
      case let .stateLabelHidden(value): self.stateLabelHidden.record(value)
      case let .statsStackViewAccessibilityLabel(value): self.statsStackViewAccessibilityLabel.record(value)
      case let .backingLabelHidden(value): self.backingLabelHidden.record(value)
      case .projectNoticeBannerHidden: break
      }
    }
  }

  func testVideoPlayerConfiguredOnceAfterProjectAndDelegateAreReady() {
    let vm = ProjectPamphletMainCellViewModel()
    var configurations = 0
    vm.onEvent = { if case .configureVideoPlayerController = $0 { configurations += 1 } }
    vm.delegateDidSet()
    vm.configureWith(value: (Project.template, nil))
    XCTAssertEqual(configurations, 0)
    vm.awakeFromNib()
    XCTAssertEqual(configurations, 1)
    vm.delegateDidSet()
    vm.configureWith(value: (Project.template, nil))
    XCTAssertEqual(configurations, 1)
  }

  func testStatsStackViewAccessibilityLabel() {
    let project = .template
      |> Project.lens.dates.deadline .~ (self.dateType.init().timeIntervalSince1970 + 60 * 60 * 24 * 10)
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.statsStackViewAccessibilityLabel.assertValues(
      ["$1,000 of $2,000 goal, 10 backers so far, 10 days to go to go"]
    )

    let nonUSProject = project
      |> Project.lens.country .~ .gb
      |> Project.lens.stats.projectCurrency .~ Project.Country.gb.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 1.2
      |> Project.lens.stats.convertedPledgedAmount .~ 1_200
    self.vm.configureWith(value: (nonUSProject, nil))

    self.statsStackViewAccessibilityLabel.assertValues(
      [
        "$1,000 of $2,000 goal, 10 backers so far, 10 days to go to go",
        "$1,200 of $2,400 goal, 10 backers so far, 10 days to go to go"
      ]
    )

    let nonUSProjectCurrencyProject = project
      |> Project.lens.country .~ .gb
      |> Project.lens.stats.projectCurrency .~ Project.Country.es.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 1.2
      |> Project.lens.stats.convertedPledgedAmount .~ 1_200
    self.vm.configureWith(value: (nonUSProjectCurrencyProject, nil))

    self.statsStackViewAccessibilityLabel.assertValues(
      [
        "$1,000 of $2,000 goal, 10 backers so far, 10 days to go to go",
        "$1,200 of $2,400 goal, 10 backers so far, 10 days to go to go",
        "$1,200 of $2,400 goal, 10 backers so far, 10 days to go to go"
      ]
    )

    let nonUSUserCurrency = project
      |> Project.lens.stats.userCurrency .~ Project.Country.gb.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 2.0

    self.vm.configureWith(value: (nonUSUserCurrency, nil))

    self.statsStackViewAccessibilityLabel.assertValues(
      [
        "$1,000 of $2,000 goal, 10 backers so far, 10 days to go to go",
        "$1,200 of $2,400 goal, 10 backers so far, 10 days to go to go",
        "$1,200 of $2,400 goal, 10 backers so far, 10 days to go to go",
        "£2,000 of £4,000 goal, 10 backers so far, 10 days to go to go"
      ]
    )
  }

  func testStatsStackViewAccessibilityLabel_defaultCurrency_nonUSUser() {
    let defaultUserCurrency = Project.template
      |> Project.lens.dates.deadline .~ (self.dateType.init().timeIntervalSince1970 + 60 * 60 * 24 * 10)
      |> Project.lens.stats.projectCurrency .~ Project.Country.gb.currencyCode
      |> Project.lens.stats.staticUsdRate .~ 2.0
      |> Project.lens.stats.usdExchangeRate .~ 2.0

    withEnvironment(countryCode: "CA") {
      self.vm.configureWith(value: (defaultUserCurrency, nil))
      self.vm.awakeFromNib()

      self.statsStackViewAccessibilityLabel.assertValues(
        ["US$ 2,000 of US$ 4,000 goal, 10 backers so far, 10 days to go to go"]
      )
    }
  }

  func testBackingLabelHidden_NotABacker() {
    let project = .template |> Project.lens.personalization.isBacking .~ false
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.backingLabelHidden.assertValues([true])
  }

  func testBackingLabelHidden_NotABacker_VideoInteraction() {
    let project = .template |> Project.lens.personalization.isBacking .~ false
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.backingLabelHidden.assertValues([true])

    self.vm.videoDidStart()

    self.backingLabelHidden.assertValues([true])

    self.vm.videoDidFinish()

    self.backingLabelHidden.assertValues([true])
  }

  func testBackingLabelHidden_LoggedOut() {
    let project = .template |> Project.lens.personalization.isBacking .~ nil
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.backingLabelHidden.assertValues([true])
  }

  func testBackingLabelHidden_Backer() {
    let project = .template |> Project.lens.personalization.isBacking .~ true
      |> \.displayPrelaunch .~ false
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.backingLabelHidden.assertValues([false])
    self.isPrelaunchProject.assertValues([false])
    self.prelaunchProjectBackingText.assertValues(["You’re a backer!"])
  }

  func testBackingLabelHidden_PrelaunchProject() {
    let project = .template |> Project.lens.personalization.isBacking .~ false
      |> \.displayPrelaunch .~ true
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.backingLabelHidden.assertValues([false])
    self.isPrelaunchProject.assertValues([true])
    self.prelaunchProjectBackingText.assertValues(["Coming soon"])
  }

  func testBackingLabelHidden_Backer_VideoInteraction() {
    let project = .template |> Project.lens.personalization.isBacking .~ true
      |> \.displayPrelaunch .~ false
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.backingLabelHidden.assertValues([false])

    self.vm.videoDidStart()

    self.backingLabelHidden.assertValues([false, true])

    self.vm.videoDidFinish()

    self.backingLabelHidden.assertValues([false, true, false])
  }

  func testCreatorImageUrl() {
    let project = .template
      |> (Project.lens.creator.avatar .. User.Avatar.lens.small) .~ "hello.jpg"
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()
    self.creatorImageUrl.assertValues(["hello.jpg"])
  }

  func testCreatorLabelText() {
    let project = Project.template |> Project.lens.creator.name .~ "Creator Blob"
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()
    self.creatorLabelText.assertValues(["by Creator Blob"])
  }

  func testProjectBlurbLabelText() {
    let project = Project.template |> Project.lens.blurb .~ "The elevator pitch"
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()
    self.projectBlurbLabelText.assertValues(["The elevator pitch"])
  }

  func testProjectImageUrl() {
    let project = .template
      |> Project.lens.photo.full .~ "project.jpg"
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()
    self.projectImageUrl.assertValues(["project.jpg"])
  }

  func testProjectNameLabelText() {
    let project = Project.template |> Project.lens.blurb .~ "The elevator pitch"
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()
    self.projectBlurbLabelText.assertValues(["The elevator pitch"])
  }

  func testBackersTitleLabel() {
    let project = .template |> Project.lens.stats.backersCount .~ 1_000
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.backersTitleLabelText.assertValues([Format.wholeNumber(project.stats.backersCount)])
  }

  // MARK: - Conversion Label

  func testConversionLabel_WhenConversionNotNeeded_US_Project_US_ProjectCurrency_US_User() {
    let project = Project.template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode

    withEnvironment(countryCode: "US") {
      self.vm.configureWith(value: (project, nil))
      self.vm.awakeFromNib()

      self.conversionLabelText.assertValueCount(0)
      self.conversionLabelHidden.assertValues([true])
    }
  }

  func testConversionLabel_WhenConversionNeeded_US_Project_US_ProjectCurrency_NonUS_User() {
    let project = .template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.pledged .~ 1_000
      |> Project.lens.stats.goal .~ 2_000
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.ca.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 1.3

    withEnvironment(countryCode: "CA") {
      self.vm.configureWith(value: (project, nil))
      self.vm.awakeFromNib()

      self.conversionLabelText.assertValues(["Converted from US$ 1,000 pledged of US$ 2,000 goal."])
      self.conversionLabelHidden.assertValues([false])
    }
  }

  func testConversionLabel_WhenConversionNeeded_NonUS_Project_NonUS_ProjectCurrency_US_User() {
    let project = .template
      |> Project.lens.country .~ .gb
      |> Project.lens.stats.projectCurrency .~ Project.Country.gb.currencyCode
      |> Project.lens.stats.goal .~ 2
      |> Project.lens.stats.pledged .~ 1

    withEnvironment(config: .template |> Config.lens.countryCode .~ "US") {
      self.vm.configureWith(value: (project, nil))
      self.vm.awakeFromNib()

      self.conversionLabelText.assertValues(["Converted from £1 pledged of £2 goal."])
      self.conversionLabelHidden.assertValues([false])
    }
  }

  func testConversionLabel_WhenConversionNeeded_NonUS_Project_DifferentNonUS_ProjectCurrency_US_User() {
    let project = .template
      |> Project.lens.country .~ .gb
      |> Project.lens.stats.projectCurrency .~ Project.Country.es.currencyCode
      |> Project.lens.stats.goal .~ 2
      |> Project.lens.stats.pledged .~ 1

    withEnvironment(config: .template |> Config.lens.countryCode .~ "US") {
      self.vm.configureWith(value: (project, nil))
      self.vm.awakeFromNib()

      self.conversionLabelText.assertValues(["Converted from €1 pledged of €2 goal."])
      self.conversionLabelHidden.assertValues([false])
    }
  }

  func testDeadlineLabels() {
    let project = .template
      |> Project.lens.dates.deadline .~ (self.dateType.init().timeIntervalSince1970 + 60 * 60 * 24 * 4)

    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.deadlineTitleLabelText.assertValues(["4"])
    self.deadlineSubtitleLabelText.assertValues(["days to go"])
  }

  func testFundingProgressBarViewBackgroundColor_UnsuccessfulProject() {
    let project = .template
      |> Project.lens.state .~ .failed

    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.fundingProgressBarViewBackgroundColor.assertValues([LegacyColors.ksr_support_400.uiColor()])
  }

  func testFundingProgressBarViewBackgroundColor_SuccessfulProject() {
    let project = .template
      |> Project.lens.state .~ .successful

    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.fundingProgressBarViewBackgroundColor.assertValues([LegacyColors.ksr_create_700.uiColor()])
  }

  func testPledgedTitleLabelTextColor_SucessfulProject() {
    let project = .template
      |> Project.lens.state .~ .successful

    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.pledgedTitleLabelTextColor.assertValues([LegacyColors.ksr_create_700.uiColor()])
  }

  func testPledgedTitleLabelTextColor_UnsuccessfulProject() {
    let project = .template
      |> Project.lens.state .~ .canceled

    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.pledgedTitleLabelTextColor.assertValues([LegacyColors.ksr_support_400.uiColor()])
  }

  // MARK: - Pledged Label

  func testPledgedLabels_WhenConversionNotNeeded() {
    let project = .template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.pledged .~ 1_000
      |> Project.lens.stats.goal .~ 2_000

    withEnvironment(countryCode: "US") {
      self.vm.configureWith(value: (project, nil))
      self.vm.awakeFromNib()

      self.pledgedTitleLabelText.assertValues(["$1,000"])
      self.pledgedSubtitleLabelText.assertValues(["pledged of $2,000"])
    }
  }

  func testPledgedLabels_WhenConversionNotNeeded_NonUS_Location() {
    let project = Project.template

    withEnvironment(countryCode: "CA") {
      self.vm.configureWith(value: (project, nil))
      self.vm.awakeFromNib()

      self.pledgedTitleLabelText.assertValues(
        ["US$ 1,000"]
      )
      self.pledgedSubtitleLabelText.assertValues(
        ["pledged of US$ 2,000"]
      )
    }
  }

  func testPledgedLabels_WhenConversionNeeded() {
    let project = .template
      |> Project.lens.country .~ .gb
      |> Project.lens.stats.projectCurrency .~ Project.Country.gb.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 2.0

    withEnvironment(countryCode: "US") {
      self.vm.configureWith(value: (project, nil))
      self.vm.awakeFromNib()

      self.pledgedTitleLabelText.assertValues(["$2,000"])
      self.pledgedSubtitleLabelText.assertValues(["pledged of $4,000"])
    }
  }

  func testPledgedLabels_ConversionNotNeeded_NonUSCountry() {
    let project = .template
      |> Project.lens.country .~ .gb
      |> Project.lens.stats.projectCurrency .~ Project.Country.gb.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.gb.currencyCode
      |> Project.lens.stats.pledged .~ 1
      |> Project.lens.stats.goal .~ 2

    withEnvironment(countryCode: "GB") {
      self.vm.configureWith(value: (project, nil))
      self.vm.awakeFromNib()

      self.pledgedTitleLabelText.assertValues(["£1"])
      self.pledgedSubtitleLabelText.assertValues(["pledged of £2"])
    }
  }

  func testPledgedLabels_ConversionNeeded_NonUSCountry_DifferentNonUS_ProjectCurrency() {
    let project = .template
      |> Project.lens.country .~ .gb
      |> Project.lens.stats.projectCurrency .~ Project.Country.mx.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.gb.currencyCode
      |> Project.lens.stats.convertedPledgedAmount .~ 4
      |> Project.lens.stats.pledged .~ 1
      |> Project.lens.stats.goal .~ 20
      |> Project.lens.stats.userCurrencyRate .~ 2.0

    withEnvironment(countryCode: "GB") {
      self.vm.configureWith(value: (project, nil))
      self.vm.awakeFromNib()

      self.pledgedTitleLabelText.assertValues(["£4"])
      self.pledgedSubtitleLabelText.assertValues(["pledged of £40"])
    }
  }

  func testProgressPercentage_UnderFunded() {
    let project = .template
      |> Project.lens.stats.pledged .~ 100
      |> Project.lens.stats.goal .~ 200
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.progressPercentage.assertValues([0.5])
  }

  func testProgressPercentage_OverFunded() {
    let project = .template
      |> Project.lens.stats.pledged .~ 300
      |> Project.lens.stats.goal .~ 200
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.progressPercentage.assertValues([1.0])
  }

  func testProjectStateLabelTextColor_SuccessfulProject() {
    let project = .template
      |> Project.lens.state .~ .successful
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.projectStateLabelTextColor.assertValues([LegacyColors.ksr_create_700.uiColor()])
  }

  func testProjectStateLabelTextColor_UnsuccessfulProject() {
    let project = .template
      |> Project.lens.state .~ .failed
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.projectStateLabelTextColor.assertValues([LegacyColors.ksr_support_400.uiColor()])
  }

  func testProjectUnsuccessfulLabelTextColor_SuccessfulProjects() {
    let project = .template
      |> Project.lens.state .~ .failed
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.projectUnsuccessfulLabelTextColor.assertValues([LegacyColors.ksr_support_400.uiColor()])
  }

  func testProjectUnsuccessfulLabelTextColor_UnsuccessfulProjects() {
    let project = .template
      |> Project.lens.state .~ .failed
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.projectUnsuccessfulLabelTextColor.assertValues([LegacyColors.ksr_support_400.uiColor()])
  }

  func testStateLabelHidden_LiveProject() {
    let project = .template
      |> Project.lens.state .~ .live
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.stateLabelHidden.assertValues([true])
  }

  func testStateLabelHidden_NonLiveProject() {
    let project = .template
      |> Project.lens.state .~ .successful
    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    self.stateLabelHidden.assertValues([false])
  }

  func testViewTransition() {
    self.opacityForViews.assertValueCount(0)

    self.vm.awakeFromNib()

    self.opacityForViews.assertValues([0.0])

    self.vm.configureWith(value: (Project.template, nil))

    self.opacityForViews.assertValues([0.0, 1.0], "Fade in views after project comes in.")
  }

  func testNotifyDelegateToGoToCreator() {
    let project = Project.template

    XCTAssertTrue(self.notifyDelegateToGoToCreator.values.isEmpty)

    self.vm.configureWith(value: (project, nil))
    self.vm.awakeFromNib()

    XCTAssertTrue(self.notifyDelegateToGoToCreator.values.isEmpty)

    self.vm.creatorButtonTapped()

    XCTAssertEqual(self.notifyDelegateToGoToCreator.values.count, 1)
    XCTAssertEqual(
      self.notifyDelegateToGoToCreator.values.first?.projectPamphletMainCellProperties.param.id,
      project.id
    )

    XCTAssertEqual(["CTA Clicked"], self.segmentTrackingClient.events)
    XCTAssertEqual("creator_details", self.segmentTrackingClient.properties.last?["context_cta"] as? String)
  }
}

private final class PamphletRecorder<Value> {
  private(set) var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
}
private extension PamphletRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
