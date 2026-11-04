@testable import Kickstarter_iOS
import Foundation
import XCTest
@testable import KsApi


import Prelude

@MainActor
final class ProjectPamphletCreatorHeaderCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  private let vm = ProjectPamphletCreatorHeaderCellViewModel()

  func testLaunchDateLabelAttributedText() {
    let dateComponents = DateComponents()
      |> \.month .~ 11
      |> \.day .~ 7
      |> \.year .~ 2_019
      |> \.timeZone .~ TimeZone.init(secondsFromGMT: 0)

    let calendar = Calendar(identifier: .gregorian)
      |> \.timeZone .~ TimeZone.init(secondsFromGMT: 0)!

    withEnvironment(calendar: calendar, locale: Locale(identifier: "en")) {
      let date = AppEnvironment.current.calendar.date(from: dateComponents)

      let project = Project.template
        |> \.dates.launchedAt .~ date!.timeIntervalSince1970

      XCTAssertNil(self.vm.launchDateLabelAttributedText)

      self.vm.configure(with: project)

      XCTAssertEqual(self.vm.launchDateLabelAttributedText?.string,
                     "You launched this project on November 7, 2019. For creator tools, head to our website!")
    }
  }
}
