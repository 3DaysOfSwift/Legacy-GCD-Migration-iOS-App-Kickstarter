import AVFoundation
import KsApi
import Observation
import UIKit

@MainActor
@Observable
public final class AudioVideoViewElementCellViewModel {
  public init() {}
  public var onPlayer: ((AVPlayer) -> Void)?
  public var onThumbnail: ((UIImage) -> Void)?
  public var onPause: (() -> Void)?
  private var seekTime: CMTime = .zero

  public func configureWith(element: AudioVideoViewElement, player: AVPlayer?, thumbnailImage: UIImage?) {
    if let player {
      let seek = element.seekPosition.isValid ? element.seekPosition : .zero
      player.currentItem?.seek(to: seek, completionHandler: nil)
      self.onPlayer?(player)
    }
    if element.seekPosition == .zero, let thumbnailImage { self.onThumbnail?(thumbnailImage) }
  }

  public func pausePlayback() -> CMTime {
    self.onPause?()
    return self.seekTime
  }

  public func recordSeektime(_ seekTime: CMTime) { self.seekTime = seekTime }
}
