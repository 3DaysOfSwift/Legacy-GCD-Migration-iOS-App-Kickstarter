@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class SettingsNotificationPickerViewModelTests: XCTestCase {
  func testFrequencyAndMissingDigest() {
    let viewModel = SettingsNotificationPickerViewModel()
    var user = User.template
    user[keyPath: UserAttribute.notification(.creatorDigest).keyPath] = true
    viewModel.configure(with: .init(cellType: .emailFrequency, user: user))
    XCTAssertEqual(viewModel.frequencyValueText, EmailFrequency.dailySummary.descriptionText)
    user[keyPath: UserAttribute.notification(.creatorDigest).keyPath] = false
    viewModel.configure(with: .init(cellType: .emailFrequency, user: user))
    XCTAssertEqual(viewModel.frequencyValueText, EmailFrequency.twiceADaySummary.descriptionText)
    user[keyPath: UserAttribute.notification(.creatorDigest).keyPath] = nil
    viewModel.configure(with: .init(cellType: .emailFrequency, user: user))
    XCTAssertEqual(viewModel.frequencyValueText, EmailFrequency.twiceADaySummary.descriptionText)
  }
}
