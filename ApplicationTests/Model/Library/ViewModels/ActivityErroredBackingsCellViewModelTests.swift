@testable import Kickstarter_iOS
@testable import KsApi
import XCTest
import UIKit

@MainActor
final class ActivityErroredBackingsCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testConfigurationReplacesBackingViews() {
    let cell = ActivityErroredBackingsCell(style: .default, reuseIdentifier: nil)
    func backingViews(in view: UIView) -> [ErroredBackingView] {
      view.subviews.flatMap { child in
        (child as? ErroredBackingView).map { [$0] } ?? backingViews(in: child)
      }
    }
    let backing = ProjectAndBackingEnvelope(project: .template, backing: .errored)
    cell.configureWith(value: [backing, backing])
    XCTAssertEqual(backingViews(in: cell).count, 2)
    cell.configureWith(value: [backing])
    XCTAssertEqual(backingViews(in: cell).count, 1)
    cell.configureWith(value: [])
    XCTAssertEqual(backingViews(in: cell).count, 0)
  }
}

@MainActor
final class ActivitySurveyResponseNativeStateTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testCountAndPositionUpdateForReusedCell() {
    let vm = ActivitySurveyResponseCellViewModel()
    let response = SurveyResponse.template
    vm.configureWith(surveyResponse: response, count: 2, position: 1)
    XCTAssertTrue(vm.rewardSurveysCountIsHidden)
    XCTAssertEqual(vm.rewardSurveysCountText, Strings.Reward_Surveys(reward_survey_count: 2))
    XCTAssertNotNil(vm.surveyResponse)
    vm.configureWith(surveyResponse: response, count: 2, position: 0)
    XCTAssertFalse(vm.rewardSurveysCountIsHidden)
    vm.configureWith(surveyResponse: response, count: 1, position: 1)
    XCTAssertFalse(vm.rewardSurveysCountIsHidden)
  }
}
