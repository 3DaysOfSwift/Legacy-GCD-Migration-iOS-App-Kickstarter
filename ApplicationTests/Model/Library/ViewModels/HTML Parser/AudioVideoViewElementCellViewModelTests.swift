@testable import Kickstarter_iOS
@testable import KsApi
import AVKit
import XCTest

@MainActor
final class AudioVideoViewElementCellViewModelTests: XCTestCase {
  func testPlayerThumbnailAndPause() {
    let vm = AudioVideoViewElementCellViewModel()
    let player = AVPlayer()
    let thumbnail = UIImage(systemName: "camera")!
    let element = AudioVideoViewElement(sourceURLString: "https://video.com", thumbnailURLString: "https://thumbnail.com", seekPosition: .zero)
    var receivedPlayer: AVPlayer?
    var receivedThumbnail: UIImage?
    var pauses = 0
    vm.onPlayer = { receivedPlayer = $0 }
    vm.onThumbnail = { receivedThumbnail = $0 }
    vm.onPause = { pauses += 1 }
    vm.configureWith(element: element, player: player, thumbnailImage: thumbnail)
    XCTAssertEqual(receivedPlayer, player)
    XCTAssertEqual(receivedThumbnail, thumbnail)
    let time = CMTime(seconds: 123, preferredTimescale: 1)
    receivedThumbnail = nil
    let resumed = AudioVideoViewElement(sourceURLString: "https://video.com", thumbnailURLString: "https://thumbnail.com", seekPosition: time)
    vm.configureWith(element: resumed, player: player, thumbnailImage: thumbnail)
    XCTAssertNil(receivedThumbnail)
    vm.recordSeektime(time)
    XCTAssertEqual(vm.pausePlayback(), time)
    XCTAssertEqual(pauses, 1)
  }
}
