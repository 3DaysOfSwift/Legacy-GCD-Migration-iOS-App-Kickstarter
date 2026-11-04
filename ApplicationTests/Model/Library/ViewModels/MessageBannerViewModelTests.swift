@testable import Kickstarter_iOS
import XCTest

@MainActor
final class MessageBannerViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testConfigurationAndRepeatedVisibility() {
    let vm = MessageBannerViewModel()
    var configuration: MessageBannerConfiguration?
    var hidden: [Bool] = []
    vm.onConfiguration = { configuration = $0 }
    vm.onHidden = { hidden.append($0) }
    vm.update(with: (.success, "Saved"))
    vm.bannerViewWillShow(true)
    vm.bannerViewWillShow(true)
    vm.bannerViewWillShow(false)
    XCTAssertEqual(configuration?.message, "Saved")
    XCTAssertEqual(hidden, [false, true])
  }

  func testAutomaticDismissalUsesVoiceOverDelay() async {
    for voiceOver in [false, true] {
      var delays: [TimeInterval] = []
      let vm = MessageBannerViewModel(sleep: { delays.append($0) })
      var hidden: [Bool] = []
      vm.onHidden = { hidden.append($0) }
      await withEnvironment(isVoiceOverRunning: { voiceOver }) {
        vm.bannerViewWillShow(true)
        vm.bannerViewAnimationFinished(isHidden: false)
        await vm.waitForDismissal(voiceOver: voiceOver)
      }
      XCTAssertEqual(delays, [voiceOver ? 10 : 4])
      XCTAssertEqual(hidden, [false, true])
    }
  }
}
