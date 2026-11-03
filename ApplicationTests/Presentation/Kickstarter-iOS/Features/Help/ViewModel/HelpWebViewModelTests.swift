@testable import Kickstarter_iOS

@testable import KsApi


import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@MainActor
internal final class HelpWebViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  fileprivate let vm: HelpWebViewModelType = HelpWebViewModel()

  fileprivate let webViewLoadRequest = TestObserver<String, Never>()

  override func setUp() async throws {
    try await super.setUp()

    self.vm.outputs.webViewLoadRequest.map { $0.url?.relativePath ?? "" }
      .observe(self.webViewLoadRequest.observer)
  }

  func testWebRequestURLString() {
    self.vm.inputs.configureWith(helpType: .cookie)

    self.webViewLoadRequest.assertValueCount(0)

    self.vm.inputs.viewDidLoad()

    self.webViewLoadRequest.assertValues(["/cookies"])

    self.vm.inputs.configureWith(helpType: .helpCenter)
    self.vm.inputs.viewDidLoad()

    self.webViewLoadRequest.assertValues(["/cookies", "/help"])

    self.vm.inputs.configureWith(helpType: .howItWorks)
    self.vm.inputs.viewDidLoad()

    self.webViewLoadRequest.assertValues(["/cookies", "/help", "/about"])

    self.vm.inputs.configureWith(helpType: .privacy)
    self.vm.inputs.viewDidLoad()

    self.webViewLoadRequest.assertValues(
      ["/cookies", "/help", "/about", "/privacy"]
    )

    self.vm.inputs.configureWith(helpType: .terms)
    self.vm.inputs.viewDidLoad()

    self.webViewLoadRequest.assertValues([
      "/cookies", "/help", "/about", "/privacy",
      "/terms-of-use"
    ])
  }
}
