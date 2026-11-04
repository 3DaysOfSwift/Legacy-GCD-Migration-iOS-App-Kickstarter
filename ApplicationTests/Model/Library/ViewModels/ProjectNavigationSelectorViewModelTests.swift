@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class ProjectNavigationSelectorViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testSectionsAndSelection() {
    let vm = ProjectNavigationSelectorViewModel()
    var sections: [[NavigationSection]] = []
    var selected: [Int] = []
    var animated: [Int] = []
    vm.onSections = { sections.append($0) }
    vm.onSelect = { selected.append($0) }
    vm.onAnimate = { animated.append($0) }
    vm.didMoveToSuperview()
    vm.didMoveToSuperview()
    var project = Project.template
    project.displayPrelaunch = false
    project.extendedProjectProperties = ExtendedProjectProperties(
      environmentalCommitments: [], faqs: [], aiDisclosure: nil, risks: "",
      story: ProjectStoryElements(htmlViewElements: []), minimumPledgeAmount: 1, projectNotice: nil
    )
    vm.configureNavigationSelector(with: (project, nil))
    vm.buttonTapped(index: 0)
    vm.buttonTapped(index: 3)
    XCTAssertEqual(sections, [[.overview], [.overview, .campaign, .faq, .risks]])
    XCTAssertEqual(selected, [0, 0, 0, 3])
    XCTAssertEqual(animated, [0, 3])
  }

  func testAnalyticsSkipsInitialOverviewAndRepeatedTabs() {
    let vm = ProjectNavigationSelectorViewModel()
    vm.configureNavigationSelector(with: (.template, nil))
    vm.buttonTapped(index: 0)
    vm.buttonTapped(index: 1)
    vm.buttonTapped(index: 1)
    vm.buttonTapped(index: 0)
    XCTAssertEqual(self.segmentTrackingClient.events, ["Page Viewed", "Page Viewed"])
    XCTAssertEqual(self.segmentTrackingClient.properties.compactMap { $0["context_section"] as? String },
                   ["campaign", "overview"])
  }

  func testPrelaunchAndEnvironmentalCommitments() {
    let vm = ProjectNavigationSelectorViewModel()
    var sections: [NavigationSection] = []
    vm.onSections = { sections = $0 }
    var project = Project.template
    project.extendedProjectProperties = ExtendedProjectProperties(
      environmentalCommitments: [ProjectTabCategoryDescription(
        description: "Commitment", category: .reusabilityAndRecyclability, id: 1
      )], faqs: [], aiDisclosure: nil, risks: "",
      story: ProjectStoryElements(htmlViewElements: []), minimumPledgeAmount: 1, projectNotice: nil
    )
    project.displayPrelaunch = true
    vm.configureNavigationSelector(with: (project, nil))
    XCTAssertEqual(sections, [.overview])
    project.displayPrelaunch = false
    vm.configureNavigationSelector(with: (project, nil))
    XCTAssertEqual(sections, [.overview, .campaign, .faq, .risks, .environmentalCommitments])
  }
}
