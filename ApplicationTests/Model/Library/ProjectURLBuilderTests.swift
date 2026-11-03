@testable import Kickstarter_iOS
@testable import KsApi

import XCTest

@MainActor
class ProjectURLBuilderTests: XCTestCase {
  func testGetProjectBackingDetailsURL() {
    let backingDetailsURL = getProjectBackingDetailsURL(with: Project.template)
    let url = "https://www.kickstarter.com/projects/1/a-fun-project/backing/details"

    XCTAssertNotNil(backingDetailsURL)
    XCTAssertEqual(backingDetailsURL?.absoluteString, url)
  }
}
