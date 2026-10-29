import AVFoundation
@testable import Kickstarter_Framework
import XCTest

@MainActor
final class VideoFeedVideoPlayerTests: XCTestCase {
  private let url = URL(fileURLWithPath: "/tmp/cfa-nonexistent-video-test.mp4")

  func testSynchronousReleaseDoesNotRetainPlayerWrapper() {
    var player: VideoFeedVideoPlayer? = VideoFeedVideoPlayer()
    weak var released = player
    player = nil
    XCTAssertNil(released)
  }

  func testReplacementSeekDeliversOnlyLatestResult() async throws {
    let gate = PlaybackGate<Bool>()
    defer { gate.releaseAll() }
    let player = VideoFeedVideoPlayer(performSeek: { _, _ in (try? await gate.request()) ?? false })
    var values: [Bool] = []
    let old = player.seek(to: 0.2) { _ in XCTFail("Obsolete seek delivered") }
    await gate.waitFor(1)
    let current = player.seek(to: 0.8) { values.append($0) }
    await gate.waitFor(2)
    try gate.finish(1, .success(false))
    await current.value
    try gate.finish(0, .success(true))
    await old.value
    XCTAssertEqual(values, [false], "A current failed seek must still reach the existing recovery UI")
  }

  func testStopSuppressesLateSeekCompletion() async throws {
    let gate = PlaybackGate<Bool>()
    defer { gate.releaseAll() }
    let player = VideoFeedVideoPlayer(performSeek: { _, _ in (try? await gate.request()) ?? false })
    let seek = player.seek(to: 0) { _ in XCTFail("Stopped playback resumed") }
    await gate.waitFor(1)
    player.stop()
    try gate.finish(0, .success(true))
    await seek.value
    XCTAssertNil(player.player.currentItem)
  }

  func testPauseSuppressesLateLoopSeekCompletion() async throws {
    let gate = PlaybackGate<Bool>()
    defer { gate.releaseAll() }
    let player = VideoFeedVideoPlayer(performSeek: { _, _ in (try? await gate.request()) ?? false })
    let seek = player.seek(to: 0) { _ in XCTFail("User pause was undone") }
    await gate.waitFor(1)
    player.pause()
    try gate.finish(0, .success(true))
    await seek.value
  }

  func testSeekDoesNotRetainReleasedPlayerWrapper() async throws {
    let gate = PlaybackGate<Bool>()
    defer { gate.releaseAll() }
    var player: VideoFeedVideoPlayer? = VideoFeedVideoPlayer(performSeek: { _, _ in (try? await gate.request()) ?? false })
    weak var released = player
    let seek = try XCTUnwrap(player).seek(to: 0) { _ in XCTFail("Released player delivered") }
    await gate.waitFor(1)
    player = nil
    XCTAssertNil(released)
    try gate.finish(0, .success(true))
    await seek.value
  }

  func testStoppedPlaybackIgnoresNonCooperativeRecoveryTimer() async throws {
    let gate = PlaybackGate<Void>()
    defer { gate.releaseAll() }
    let player = VideoFeedVideoPlayer(sleep: { _ in try await gate.request() })
    let failure = expectation(description: "Stopped timer must not fail the cell")
    failure.isInverted = true
    player.onVideoFailed = { failure.fulfill() }
    player.load(url: self.url)
    await gate.waitFor(1)
    NotificationCenter.default.post(name: AVPlayerItem.playbackStalledNotification, object: player.player.currentItem)
    await gate.waitFor(2)
    player.stop()
    try gate.finish(0, .success(()))
    try gate.finish(1, .success(()))
    await fulfillment(of: [failure], timeout: 0.1)
  }

  func testRecoveryFailureFiresOnceForCurrentItem() async throws {
    let gate = PlaybackGate<Void>()
    defer { gate.releaseAll() }
    let player = VideoFeedVideoPlayer(sleep: { duration in
      XCTAssertEqual(duration, .seconds(3))
      try await gate.request()
    })
    defer { player.stop() }
    let failure = expectation(description: "Current stalled item fails after recovery window")
    var failures = 0
    player.onVideoFailed = { failures += 1; failure.fulfill() }
    player.load(url: self.url)
    await gate.waitFor(1)
    NotificationCenter.default.post(name: AVPlayerItem.playbackStalledNotification, object: player.player.currentItem)
    await gate.waitFor(2)
    // A repeated stall must share the first deadline, not reset its timer.
    NotificationCenter.default.post(name: AVPlayerItem.playbackStalledNotification, object: player.player.currentItem)
    try gate.finish(1, .success(()))
    await fulfillment(of: [failure], timeout: 2)
    NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: player.player.currentItem)
    XCTAssertEqual(failures, 1)
  }

  func testReplacementItemRejectsOldRecoveryTimer() async throws {
    let gate = PlaybackGate<Void>()
    defer { gate.releaseAll() }
    let player = VideoFeedVideoPlayer(sleep: { _ in try await gate.request() })
    defer { player.stop() }
    let failure = expectation(description: "Old item cannot fail its replacement")
    failure.isInverted = true
    player.onVideoFailed = { failure.fulfill() }
    player.load(url: self.url)
    await gate.waitFor(1)
    NotificationCenter.default.post(name: AVPlayerItem.playbackStalledNotification, object: player.player.currentItem)
    await gate.waitFor(2)
    player.load(url: self.url)
    await gate.waitFor(3)
    try gate.finish(0, .success(()))
    try gate.finish(1, .success(()))
    await fulfillment(of: [failure], timeout: 0.1)
  }
}

/// Deliberately non-cooperative suspension proves identity/cancellation checks
/// protect delivery even when the platform operation finishes after cancellation.
@MainActor
private final class PlaybackGate<Value> {
  private var pending: [CheckedContinuation<Value, Error>?] = []
  private var waits: [(Int, XCTestExpectation)] = []
  func request() async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
      pending.append(continuation)
      for (count, expectation) in waits where count == pending.count { expectation.fulfill() }
    }
  }
  func waitFor(_ count: Int) async {
    if pending.count >= count { return }
    let expectation = XCTestExpectation(description: "Playback operation admitted")
    waits.append((count, expectation))
    let result = await XCTWaiter().fulfillment(of: [expectation], timeout: 2)
    XCTAssertEqual(result, .completed)
  }
  func finish(_ index: Int, _ result: Result<Value, Error>) throws {
    guard pending.indices.contains(index) else { XCTFail("Operation was not admitted"); return }
    let continuation = try XCTUnwrap(pending[index])
    pending[index] = nil
    continuation.resume(with: result)
  }
  func releaseAll() {
    for continuation in pending { continuation?.resume(throwing: CancellationError()) }
    pending.removeAll()
  }
}
