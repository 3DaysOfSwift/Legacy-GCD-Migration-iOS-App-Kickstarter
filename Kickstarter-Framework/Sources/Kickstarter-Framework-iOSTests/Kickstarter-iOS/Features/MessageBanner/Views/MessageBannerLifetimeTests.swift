@testable import Kickstarter_Framework
import Library
import SwiftUI
import XCTest

/// Runtime lifetime checks, not image snapshots. Reference-device guards stay unchanged.
@MainActor
final class MessageBannerLifetimeTests: XCTestCase {
  func testOldDeadlineCannotDismissReplacementBanner() async throws {
    XCTAssertFalse(UIAccessibility.isVoiceOverRunning, "This runtime check expects the default four-second policy")
    let state = BannerLifetimeState()
    let window = self.show(state)
    defer { window.isHidden = true; window.rootViewController = nil }
    try await Task.sleep(for: .seconds(1.5))
    let replacement = MessageBannerViewViewModel((.success, "Replacement"))
    state.current = replacement
    // Beyond the original four-second deadline, before the replacement's deadline.
    try await Task.sleep(for: .seconds(3))
    XCTAssertTrue(state.current === replacement)
    try await Task.sleep(for: .seconds(1.5))
    XCTAssertNil(state.current, "The current banner must still auto-dismiss")
  }

  func testLeavingViewCancelsPendingDismissal() async throws {
    XCTAssertFalse(UIAccessibility.isVoiceOverRunning, "This runtime check expects the default four-second policy")
    let state = BannerLifetimeState()
    let window = self.show(state)
    try await Task.sleep(for: .seconds(1))
    window.isHidden = true
    window.rootViewController = nil
    try await Task.sleep(for: .seconds(4.5))
    XCTAssertNotNil(state.current, "A removed view must not mutate its former binding")
  }

  private func show(_ state: BannerLifetimeState) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = UIHostingController(rootView: BannerLifetimeHost(state: state))
    window.makeKeyAndVisible()
    return window
  }
}

@MainActor
private final class BannerLifetimeState: ObservableObject {
  @Published var current: MessageBannerViewViewModel? = MessageBannerViewViewModel((.success, "Original"))
}

private struct BannerLifetimeHost: View {
  @ObservedObject var state: BannerLifetimeState
  var body: some View {
    MessageBannerView(viewModel: self.$state.current)
  }
}
