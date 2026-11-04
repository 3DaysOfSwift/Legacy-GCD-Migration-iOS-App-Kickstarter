@testable import Kickstarter_iOS
import XCTest

@MainActor
final class HelpViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = HelpViewModel()

  func testWebHelpAndSheet() {
    var opened: [HelpType] = []
    var sheet: [HelpType] = []
    self.vm.onWebHelp = { opened.append($0) }
    self.vm.onHelpSheet = { sheet = $0 }
    for type: HelpType in [.cookie, .helpCenter, .howItWorks, .privacy, .terms] {
      self.vm.helpTypeButtonTapped(type)
    }
    self.vm.showHelpSheetButtonTapped()
    XCTAssertEqual(opened, [.cookie, .helpCenter, .howItWorks, .privacy, .terms])
    XCTAssertEqual(sheet, [.howItWorks, .contact, .terms, .privacy, .cookie])
  }

  func testContactRequiresMailAvailability() {
    var composeCount = 0
    var errorCount = 0
    self.vm.onMailCompose = { composeCount += 1 }
    self.vm.onNoEmailError = { _ in errorCount += 1 }
    self.vm.helpTypeButtonTapped(.contact)
    XCTAssertEqual(composeCount, 0)
    XCTAssertEqual(errorCount, 0)
    self.vm.canSendEmail(true)
    self.vm.helpTypeButtonTapped(.contact)
    self.vm.canSendEmail(false)
    self.vm.helpTypeButtonTapped(.contact)
    XCTAssertEqual(composeCount, 1)
    XCTAssertEqual(errorCount, 1)
  }
}
