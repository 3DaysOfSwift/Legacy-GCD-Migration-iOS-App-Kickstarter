import AVFoundation
@testable import Kickstarter_Framework
import XCTest

@MainActor
final class ProjectVideoObservationTests: XCTestCase {
  func testEventsDeliverOnMainActorAndOnlyCurrentBoundaryCanComplete() async throws {
    let source = ControlledProjectVideoEvents()
    var received: [String] = []
    let delivered = expectation(description: "current events")
    delivered.expectedFulfillmentCount = 3
    let owner = ProjectVideoObservation(source: source) { event in
      XCTAssertTrue(Thread.isMainThread)
      switch event {
      case let .duration(time): received.append("duration \(time.seconds)")
      case let .rate(rate, time): received.append("rate \(rate) at \(time.seconds)")
      case .completion: received.append("completion")
      }
      delivered.fulfill()
    }
    owner.setCompletionBoundary(.invalid)
    XCTAssertTrue(source.boundaries.isEmpty)
    owner.setCompletionBoundary(CMTime(seconds: 85, preferredTimescale: 1))
    let old = try XCTUnwrap(source.boundaries.last).1
    owner.setCompletionBoundary(CMTime(seconds: 170, preferredTimescale: 1))
    let current = try XCTUnwrap(source.boundaries.last).1
    source.continuation.yield(.duration(CMTime(seconds: 200, preferredTimescale: 1)))
    source.continuation.yield(.rate(1, .zero))
    source.continuation.yield(.completion(old))
    source.continuation.yield(.completion(current))
    await fulfillment(of: [delivered], timeout: 2)
    owner.stop(); await owner.task?.value
    XCTAssertEqual(received, ["duration 200.0", "rate 1.0 at 0.0", "completion"])
    XCTAssertEqual(source.stopCount, 1)
  }

  func testStoppedAndReleasedObserversRejectQueuedEvents() async {
    let source = ControlledProjectVideoEvents()
    var owner: ProjectVideoObservation? = ProjectVideoObservation(source: source) { _ in XCTFail("Late event") }
    let task = owner?.task
    source.continuation.yield(.duration(CMTime(seconds: 1, preferredTimescale: 1)))
    owner?.stop(); owner?.stop()
    weak var released = owner
    owner = nil
    XCTAssertNil(released)
    await task?.value
    XCTAssertEqual(source.stopCount, 1)

    let second = ControlledProjectVideoEvents()
    var releasedOwner: ProjectVideoObservation? = ProjectVideoObservation(source: second) { _ in XCTFail("Released owner delivered") }
    let pending = releasedOwner?.task
    weak var weakOwner = releasedOwner
    releasedOwner = nil
    XCTAssertNil(weakOwner)
    second.continuation.yield(.rate(1, .zero))
    await pending?.value
  }

  func testNativeBoundaryReplacementAndSynchronousReleaseFinishObservation() async throws {
    let player = AVPlayer()
    var source: NativeProjectVideoEvents? = NativeProjectVideoEvents(player: player)
    let stream = try XCTUnwrap(source).events
    source?.setBoundary(CMTime(seconds: 1, preferredTimescale: 1), id: UUID())
    source?.setBoundary(CMTime(seconds: 2, preferredTimescale: 1), id: UUID())
    weak var released = source
    source = nil
    XCTAssertNil(released)
    let ended = expectation(description: "stream ended")
    let consumer = Task { for await _ in stream {}; ended.fulfill() }
    await fulfillment(of: [ended], timeout: 2)
    consumer.cancel()
  }

  func testNativeLocalPlaybackDeliversDurationRateAndReplacementBoundary() async throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".wav")
    defer { try? FileManager.default.removeItem(at: url) }
    var bytes = Data()
    func text(_ value: String) { bytes.append(contentsOf: value.utf8) }
    func int<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { bytes.append(contentsOf: $0) } }
    let samples = 44_100
    text("RIFF"); int(UInt32(36 + samples * 2)); text("WAVEfmt "); int(UInt32(16))
    int(UInt16(1)); int(UInt16(1)); int(UInt32(44_100)); int(UInt32(88_200)); int(UInt16(2)); int(UInt16(16))
    text("data"); int(UInt32(samples * 2)); bytes.append(Data(count: samples * 2))
    try bytes.write(to: url)
    let asset = AVURLAsset(url: url)
    _ = try await asset.load(.duration, .tracks)
    let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
    let duration = expectation(description: "native duration")
    let rate = expectation(description: "native rate")
    let boundary = expectation(description: "native boundary")
    var sawDuration = false, sawRate = false, sawBoundary = false
    let owner = ProjectVideoObservation(source: NativeProjectVideoEvents(player: player)) { event in
      switch event {
      case let .duration(value) where !sawDuration:
        XCTAssertEqual(value.seconds, 1, accuracy: 0.01); sawDuration = true; duration.fulfill()
      case let .rate(value, _) where value > 0 && !sawRate:
        sawRate = true; rate.fulfill()
      case .completion where !sawBoundary:
        sawBoundary = true; boundary.fulfill()
      default: break
      }
    }
    defer { owner.stop() }
    owner.setCompletionBoundary(CMTime(seconds: 0.9, preferredTimescale: 100))
    owner.setCompletionBoundary(CMTime(seconds: 0.1, preferredTimescale: 100))
    player.play()
    await fulfillment(of: [duration, rate, boundary], timeout: 5)
  }
}

@MainActor
private final class ControlledProjectVideoEvents: ProjectVideoEventSource {
  let events: AsyncStream<ProjectVideoEvent>
  let continuation: AsyncStream<ProjectVideoEvent>.Continuation
  var boundaries: [(CMTime, UUID)] = []
  var stopCount = 0
  init() { (self.events, self.continuation) = AsyncStream<ProjectVideoEvent>.makeStream() }
  func setBoundary(_ time: CMTime, id: UUID) { self.boundaries.append((time, id)) }
  func stop() { self.stopCount += 1; self.continuation.finish() }
}
