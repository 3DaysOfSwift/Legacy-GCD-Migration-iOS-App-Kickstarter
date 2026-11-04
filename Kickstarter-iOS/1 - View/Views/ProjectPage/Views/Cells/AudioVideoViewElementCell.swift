import AVKit
import KsApi

import Prelude
import Prelude_UIKit
import UIKit

@MainActor
internal protocol AudioVideoViewElementCellPlaybackDelegate: AnyObject {
  func pausePlayback() -> CMTime
  func isPlaying() -> Bool
}

class AudioVideoViewElementCell: UITableViewCell, ValueCell {
  // MARK: Properties

  private let viewModel = AudioVideoViewElementCellViewModel()
  private var playbackObservation: NSKeyValueObservation?
  private var playbackObservationTask: Task<Void, Never>?
  private lazy var playerController: AVPlayerViewController = { AVPlayerViewController() }()

  weak var delegate: AudioVideoViewElementCellPlaybackDelegate?

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)

    self.delegate = self

    self.configureViews()
    self.bindStyles()
    self.bindViewModel()
  }

  // MARK: Initializers

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configureWith(value: (element: AudioVideoViewElement, player: AVPlayer?, thumbnailImage: UIImage?)) {
    self.viewModel.configureWith(
      element: value.element,
      player: value.player,
      thumbnailImage: value.thumbnailImage
    )
  }

  // MARK: View Model

  internal override func bindViewModel() {
    self.viewModel.onPlayer = { [weak self] player in
      guard let self else { return }
      self.resetPlayer()
      try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
      self.playerController.player = player
    }
    self.viewModel.onThumbnail = { [weak self] image in
      guard let self else { return }
      self.playerController.contentOverlayView?.subviews.forEach { $0.removeFromSuperview() }
      self.observePlaybackStart()
      if let contentOverlayView = self.playerController.contentOverlayView {
        let imageView = UIImageView()
        imageView.image = image
        _ = imageView |> thumbnailImageViewStyle |> \.isUserInteractionEnabled .~ false
        _ = (imageView, contentOverlayView) |> ksr_addSubviewToParent() |> ksr_constrainViewToMarginsInParent()
      }
    }
    self.viewModel.onPause = { [weak self] in
      guard let self else { return }
      self.playerController.player?.pause()
      self.viewModel.recordSeektime(self.playerController.player?.currentTime() ?? .zero)
    }
  }

  // MARK: View Styles

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseTableViewCellStyle()
      |> \.separatorInset .~
      .init(
        top: 0,
        left: 0,
        bottom: 0,
        right: self.bounds.size.width + ProjectHeaderCellStyles.Layout.insets
      )

    _ = self.contentView
      |> \.layoutMargins .~ .init(
        topBottom: Styles.gridHalf(3),
        leftRight: Styles.grid(3)
      )

    let aspectRatio = CGFloat(9.0 / 16.0)

    NSLayoutConstraint.activate([
      self.playerController.view.heightAnchor.constraint(
        equalTo: self.contentView.layoutMarginsGuide.widthAnchor,
        multiplier: aspectRatio
      )
    ])
  }

  // MARK: Helpers

  private func observePlaybackStart() {
    self.playbackObservationTask?.cancel()
    self.playbackObservation?.invalidate()
    self.playbackObservation = nil
    guard let player = self.playerController.player else { return }

    let (changes, continuation) = AsyncStream<Void>.makeStream()
    self.playbackObservation = player.observe(\.timeControlStatus, options: [.old, .new]) { _, _ in
      // AVFoundation can publish off-main. No player or KVO payload crosses actors.
      continuation.yield(())
    }
    self.playbackObservationTask = Task { @MainActor [weak self] in
      for await _ in changes {
        guard !Task.isCancelled else { return }
        self?.playerController.contentOverlayView?.subviews.forEach { $0.removeFromSuperview() }
        self?.playbackObservation?.invalidate()
        self?.playbackObservation = nil
        return
      }
    }
  }

  deinit {
    self.playbackObservationTask?.cancel()
  }

  private func resetPlayer() {
    self.playbackObservationTask?.cancel()
    self.playbackObservationTask = nil
    self.playbackObservation?.invalidate()
    self.playbackObservation = nil
    self.playerController.player = nil
    self.playerController.contentOverlayView?.subviews.forEach { $0.removeFromSuperview() }
  }

  private func configureViews() {
    _ = (self.playerController.view, self.contentView)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToMarginsInParent()
  }
}

extension AudioVideoViewElementCell: AudioVideoViewElementCellPlaybackDelegate {
  func pausePlayback() -> CMTime {
    self.viewModel.pausePlayback()
  }

  func isPlaying() -> Bool {
    self.playerController.player?.timeControlStatus == .playing
  }
}
