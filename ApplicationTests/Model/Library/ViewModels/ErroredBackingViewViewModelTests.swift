@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class ErroredBackingViewViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = ErroredBackingViewViewModel()

  func testNotifyDelegateManageButtonTapped_Emits_WhenButtonIsTapped() {
    let env = ProjectAndBackingEnvelope.template

    XCTAssertNil(self.vm.backingForManageAction())
    self.vm.configure(with: env)

    XCTAssertEqual(self.vm.backingForManageAction(), env)
  }

  func testErroredBackings() {
    let date = AppEnvironment.current.calendar.date(byAdding: DateComponents(day: 4), to: MockDate().date)

    let project = Project.template
      |> \.name .~ "Awesome tabletop collection"
      |> \.dates.finalCollectionDate .~ date?.timeIntervalSince1970

    let env = ProjectAndBackingEnvelope.template
      |> \.project .~ project

    XCTAssertNil(self.vm.projectName)
    XCTAssertNil(self.vm.finalCollectionDateText)

    self.vm.configure(with: env)

    XCTAssertEqual(self.vm.projectName, "Awesome tabletop collection")
    XCTAssertEqual(self.vm.finalCollectionDateText, "4 days left")
  }

  func testErroredBackings_lessThanAnHour() {
    let date = AppEnvironment.current.calendar.date(byAdding: DateComponents(minute: 48), to: MockDate().date)

    let project = Project.template
      |> \.name .~ "Awesome tabletop collection"
      |> \.dates.finalCollectionDate .~ date?.timeIntervalSince1970

    let env = ProjectAndBackingEnvelope.template
      |> \.project .~ project

    XCTAssertNil(self.vm.projectName)
    XCTAssertNil(self.vm.finalCollectionDateText)

    self.vm.configure(with: env)

    XCTAssertEqual(self.vm.projectName, "Awesome tabletop collection")
    XCTAssertEqual(self.vm.finalCollectionDateText, "1 hour left")
  }
}
