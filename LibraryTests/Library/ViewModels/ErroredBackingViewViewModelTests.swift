@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@MainActor
final class ErroredBackingViewViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private lazy var vm: ErroredBackingViewViewModelType = {
    let vm = ErroredBackingViewViewModel()
    vm.outputs.finalCollectionDateText.observe(self.finalCollectionDateText.observer)
    vm.outputs.notifyDelegateManageButtonTapped.observe(self.notifyDelegateManageButtonTapped.observer)
    vm.outputs.projectName.observe(self.projectName.observer)
    return vm
  }()

  private let finalCollectionDateText = TestObserver<String, Never>()
  private let notifyDelegateManageButtonTapped = TestObserver<ProjectAndBackingEnvelope, Never>()
  private let projectName = TestObserver<String, Never>()



  func testNotifyDelegateManageButtonTapped_Emits_WhenButtonIsTapped() {
    let env = ProjectAndBackingEnvelope.template

    self.vm.inputs.configure(with: env)

    self.notifyDelegateManageButtonTapped.assertDidNotEmitValue()

    self.vm.inputs.manageButtonTapped()

    self.notifyDelegateManageButtonTapped.assertValue(env)
  }

  func testErroredBackings() {
    let date = AppEnvironment.current.calendar.date(byAdding: DateComponents(day: 4), to: MockDate().date)

    let project = Project.template
      |> \.name .~ "Awesome tabletop collection"
      |> \.dates.finalCollectionDate .~ date?.timeIntervalSince1970

    let env = ProjectAndBackingEnvelope.template
      |> \.project .~ project

    self.projectName.assertDidNotEmitValue()
    self.finalCollectionDateText.assertDidNotEmitValue()

    self.vm.inputs.configure(with: env)

    self.projectName.assertValue("Awesome tabletop collection")
    self.finalCollectionDateText.assertValue("4 days left")
  }

  func testErroredBackings_lessThanAnHour() {
    let date = AppEnvironment.current.calendar.date(byAdding: DateComponents(minute: 48), to: MockDate().date)

    let project = Project.template
      |> \.name .~ "Awesome tabletop collection"
      |> \.dates.finalCollectionDate .~ date?.timeIntervalSince1970

    let env = ProjectAndBackingEnvelope.template
      |> \.project .~ project

    self.projectName.assertDidNotEmitValue()
    self.finalCollectionDateText.assertDidNotEmitValue()

    self.vm.inputs.configure(with: env)

    self.projectName.assertValue("Awesome tabletop collection")
    self.finalCollectionDateText.assertValue("1 hour left")
  }
}
