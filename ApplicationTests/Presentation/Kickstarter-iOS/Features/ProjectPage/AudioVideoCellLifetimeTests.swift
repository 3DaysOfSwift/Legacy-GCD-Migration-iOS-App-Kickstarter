import UIKit
@testable import Kickstarter_iOS
import AVKit
import XCTest

@testable import KsApi

@MainActor
final class AudioVideoCellLifetimeTests: XCTestCase {
  func testReplacementAndReleaseDetachPlaybackObservation() {
    let first = AVPlayer()
    let replacement = AVPlayer()
    let element = AudioVideoViewElement(
      sourceURLString: "https://example.invalid/video", thumbnailURLString: nil, seekPosition: .zero)
    var cell: AudioVideoViewElementCell? = AudioVideoViewElementCell(style: .default, reuseIdentifier: nil)
    cell?.configureWith(value: (element, first, UIImage()))
    cell?.configureWith(value: (element, first, UIImage()))
    cell?.configureWith(value: (element, replacement, UIImage()))
    weak var released = cell
    cell = nil
    XCTAssertNil(released)
    // Repeated thumbnails and replacement must not leave manual KVO registrations
    // addressing the released cell on either player.
    for player in [first, replacement] {
      player.willChangeValue(forKey: "timeControlStatus")
      player.didChangeValue(forKey: "timeControlStatus")
    }
  }
}
