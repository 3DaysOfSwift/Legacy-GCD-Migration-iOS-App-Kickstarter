@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
private final class RisksDisclaimerDelegateProbe: ProjectRisksDisclaimerCellDelegate {
  var urls: [URL] = []
  func projectRisksDisclaimerCell(_ cell: ProjectRisksDisclaimerCell, didTapURL url: URL) {
    self.urls.append(url)
  }
}

@MainActor
final class ProjectRisksDisclaimerCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testTapNotifiesDelegateWithTrustURL() throws {
    let cell = ProjectRisksDisclaimerCell(style: .default, reuseIdentifier: nil)
    let delegate = RisksDisclaimerDelegateProbe()
    cell.delegate = delegate
    let expected = try XCTUnwrap(HelpType.trust.url(withBaseUrl: AppEnvironment.current.apiService.serverConfig.webBaseUrl))
    cell.perform(NSSelectorFromString("descriptionLabelTapped"))
    XCTAssertEqual(delegate.urls, [expected])
  }
}
