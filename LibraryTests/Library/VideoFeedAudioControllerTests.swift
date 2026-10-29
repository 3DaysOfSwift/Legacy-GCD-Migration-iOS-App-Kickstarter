import AVFoundation
import MediaPlayer
import UIKit
@testable import Library
@testable import LibraryTestHelpers
import XCTest

final class MockAudioSession: AudioSessionManaging {
  private(set) var categories: [AVAudioSession.Category] = []
  private(set) var activeStates: [Bool] = []

  var lastCategory: AVAudioSession.Category? { self.categories.last }

  func setCategory(_ category: AVAudioSession.Category, mode _: AVAudioSession.Mode) throws {
    self.categories.append(category)
  }

  func setActive(_ active: Bool) throws {
    self.activeStates.append(active)
  }

  func setActive(_ active: Bool, options _: AVAudioSession.SetActiveOptions) throws {
    self.activeStates.append(active)
  }
}

@MainActor
final class VideoFeedAudioControllerTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  func testOlderResetCannotReleaseNewResetGuard() async throws {
    let gate = AccountRequestGate<Void>()
    defer { gate.releaseAll() }
    let controller = VideoFeedAudioController(session: MockAudioSession(), nextTurn: { _ = try? await gate.request() })
    controller.handleSilentSwitchChange()
    let first = controller.resetTask
    await gate.waitFor(1)
    controller.handleSilentSwitchChange()
    let second = controller.resetTask
    await gate.waitFor(2)
    try gate.finish(0, .success(()))
    await first?.value
    XCTAssertTrue(controller.isResettingAudioSession)
    try gate.finish(1, .success(()))
    await second?.value
    XCTAssertFalse(controller.isResettingAudioSession)
  }

  func testDismissRejectsPendingResetAndLaterVolumeIntent() async throws {
    let gate = AccountRequestGate<Void>()
    defer { gate.releaseAll() }
    let session = MockAudioSession()
    let controller = VideoFeedAudioController(session: session, nextTurn: { _ = try? await gate.request() })
    controller.handleSilentSwitchChange()
    let reset = controller.resetTask
    await gate.waitFor(1)
    controller.handleDismiss()
    let count = session.categories.count
    controller.handleVolumeUp()
    controller.handleOverlayUnmute()
    try gate.finish(0, .success(()))
    await reset?.value
    XCTAssertEqual(session.categories.count, count)
    XCTAssertFalse(controller.isPlaybackSessionActive)
  }

  func testObserverReplacementAndDismissRemoveVolumeViewAndQueuedEvents() async {
    guard #available(iOS 26, *) else { return }
    let session = MockAudioSession()
    let controller = VideoFeedAudioController(session: session)
    let view = UIView()
    controller.setupObservers(in: view)
    let first = controller.observationTask
    controller.setupObservers(in: view)
    await first?.value
    XCTAssertEqual(view.subviews.filter { $0 is MPVolumeView }.count, 1)
    let current = controller.observationTask
    NotificationCenter.default.post(name: AVAudioSession.outputMuteStateChangeNotification, object: nil)
    controller.handleDismiss()
    let count = session.categories.count
    await current?.value
    XCTAssertEqual(session.categories.count, count)
    XCTAssertTrue(view.subviews.isEmpty)
  }

  func testObserverTaskDoesNotRetainReleasedController() async {
    guard #available(iOS 26, *) else { return }
    let view = UIView()
    var controller: VideoFeedAudioController? = VideoFeedAudioController(session: MockAudioSession())
    weak var released = controller
    controller?.setupObservers(in: view)
    let task = controller?.observationTask
    controller = nil
    XCTAssertNil(released)
    await task?.value
    await Task.yield()
    XCTAssertTrue(view.subviews.isEmpty)
  }

  func testConfigure() {
    let mock = MockAudioSession()
    let controller = VideoFeedAudioController(session: mock)

    controller.configure()

    if #available(iOS 26, *) {
      XCTAssertEqual(mock.lastCategory, .soloAmbient)
    } else {
      XCTAssertEqual(mock.lastCategory, .playback)
    }

    XCTAssertEqual(mock.activeStates.last, true)
  }

  func testVolumeUp_SwitchesToPlaybackAndSetsFlag() {
    let mock = MockAudioSession()
    let controller = VideoFeedAudioController(session: mock)

    controller.handleVolumeUp()

    XCTAssertEqual(mock.lastCategory, .playback)
    XCTAssertTrue(controller.isPlaybackSessionActive)
  }

  func testVolumeUp_IsBlockedDuringSessionReset() {
    let mock = MockAudioSession()
    let controller = VideoFeedAudioController(session: mock)

    controller.handleSilentSwitchChange()

    let categoryAfterReset = mock.lastCategory

    controller.handleVolumeUp()

    XCTAssertEqual(mock.lastCategory, categoryAfterReset)
    XCTAssertFalse(controller.isPlaybackSessionActive)
  }

  func testSilentSwitch_ResetsTSoloAmbient() {
    let mock = MockAudioSession()
    let controller = VideoFeedAudioController(session: mock)

    controller.handleVolumeUp() /// puts us in .playback
    controller.handleSilentSwitchChange()

    XCTAssertEqual(mock.lastCategory, .soloAmbient)
  }

  func testSilentSwitch_ClearsPlaybackFlag() {
    let mock = MockAudioSession()
    let controller = VideoFeedAudioController(session: mock)

    controller.handleVolumeUp()
    XCTAssertTrue(controller.isPlaybackSessionActive)

    controller.handleSilentSwitchChange()

    XCTAssertFalse(controller.isPlaybackSessionActive)
  }

  func testOverlayUnmute_SwitchesToPlayback() {
    let mock = MockAudioSession()
    let controller = VideoFeedAudioController(session: mock)

    controller.handleOverlayUnmute()

    XCTAssertEqual(mock.lastCategory, .playback)
    XCTAssertTrue(controller.isPlaybackSessionActive)
  }

  func testDismiss_ResetsTSoloAmbient() {
    let mock = MockAudioSession()
    let controller = VideoFeedAudioController(session: mock)

    controller.handleVolumeUp()
    controller.handleDismiss()

    XCTAssertEqual(mock.lastCategory, .soloAmbient)
  }
}
