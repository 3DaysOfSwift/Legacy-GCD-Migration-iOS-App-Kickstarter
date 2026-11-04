import AVFoundation
import AVKit
import KDS
import KsApi

import Prelude
import UIKit

@MainActor
public protocol VideoViewControllerDelegate: AnyObject {
  func videoViewControllerDidFinish(_ controller: VideoViewController)
  func videoViewControllerDidStart(_ controller: VideoViewController)
}

public final class VideoViewController: UIViewController {
  internal weak var delegate: VideoViewControllerDelegate?
  internal weak var playbackDelegate: AudioVideoViewControllerPlaybackDelegate?
  fileprivate let viewModel = VideoViewModel()
  fileprivate var playerController: AVPlayerViewController!
  private var videoObservation: ProjectVideoObservation?
  private var backgroundObserver: PlatformObservation?

  @IBOutlet fileprivate var playButton: UIButton!
  @IBOutlet fileprivate var projectImageView: UIImageView!
  @IBOutlet fileprivate var videoContainerView: UIView!

  internal static func configuredWith(project: any VideoViewConfiguration) -> VideoViewController {
    let vc = Storyboard.Video.instantiate(VideoViewController.self)
    vc.viewModel.configureWith(project: project)
    return vc
  }

  public override func viewDidLoad() {
    super.viewDidLoad()

    self.playerController = self.children.compactMap { $0 as? AVPlayerViewController }.first

    self.playButton.addTarget(self, action: #selector(self.playButtonTapped), for: .touchUpInside)

    self.viewModel.viewDidLoad()

    self.setupNotifications()
  }

  public override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    self.viewModel.viewDidAppear()
  }

  public override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    self.viewModel.viewDidDisappear(animated: animated)
  }

  public override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    self.viewModel.viewWillDisappear()
  }

  public override func bindStyles() {
    super.bindStyles()

    self.view.backgroundColor = Colors.Background.Surface.primary.uiColor()

    _ = self.playButton
      |> UIButton.lens.image(for: .normal) .~ image(named: "play-arrow-icon")
      <> UIButton.lens.backgroundColor(for: .highlighted) .~ LegacyColors.ksr_white.uiColor()
      .withAlphaComponent(0.5)
      <> UIButton.lens.accessibilityLabel %~ { _ in Strings.accessibility_projects_buttons_play_video() }

    _ = self.projectImageView
      |> UIImageView.lens.accessibilityElementsHidden .~ true

    _ = self.projectImageView
      |> ignoresInvertColorsImageViewStyle
  }

  public override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onPlayButtonHidden = { [weak self] in self?.playButton.isHidden = $0 }
    self.viewModel.onVideoHidden = { [weak self] in self?.videoContainerView.isHidden = $0 }
    self.viewModel.onOpacity = { [weak self] alpha in
      UIView.animate(withDuration: alpha == 0 ? 0 : 0.3, delay: 0, options: .curveEaseOut) {
        self?.playButton.alpha = alpha
      }
    }
    self.viewModel.onCompletionBoundary = { [weak self] in self?.addCompletionObserver(atTime: $0) }
    self.viewModel.onPlayerURL = { [weak self] in self?.configurePlayer(withURL: $0) }
    self.viewModel.onFinish = { [weak self] in
      guard let self else { return }
      self.delegate?.videoViewControllerDidFinish(self)
    }
    self.viewModel.onStart = { [weak self] in
      guard let self else { return }
      self.delegate?.videoViewControllerDidStart(self)
    }
    self.viewModel.onPause = { [weak self] in self?.playerController.player?.pause() }
    self.viewModel.onPlay = { [weak self] in self?.playerController.player?.play() }
    self.viewModel.onProjectImageHidden = { [weak self] hidden in
      UIView.animate(withDuration: 0.5) { self?.projectImageView.alpha = hidden ? 0 : 1 }
    }
    self.viewModel.onProjectImageURL = { [weak self] url in
      self?.projectImageView.af.cancelImageRequest()
      self?.projectImageView.image = nil
      if let url { self?.projectImageView.ksr_setImageWithURL(url) }
    }
    self.viewModel.onSeekToBeginning = { [weak self] in self?.playerController.player?.seek(to: .zero) }
  }

  func addCompletionObserver(atTime time: CMTime) {
    self.videoObservation?.setCompletionBoundary(time)
  }

  internal func configurePlayer(withURL url: URL) {
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
    self.videoObservation?.stop()
    let player = AVPlayer(url: url)
    self.playerController.player = player
    self.videoObservation = ProjectVideoObservation(source: NativeProjectVideoEvents(player: player)) { [weak self] event in
      guard let self else { return }
      switch event {
      case let .duration(duration): self.viewModel.durationChanged(toNew: duration)
      case let .rate(rate, time): self.viewModel.rateChanged(toNew: rate, atTime: time)
      case .completion: self.viewModel.crossedCompletionThreshold()
      }
    }
  }

  @objc fileprivate func playButtonTapped() {
    self.viewModel.playButtonTapped()
  }

  deinit {
    // videoObservation releases its exact player's KVO/boundary resources.
  }

  private func setupNotifications() {
    if let observer = self.backgroundObserver { observer.dispose() }
    self.backgroundObserver = NotificationCenter.default.scopedObserver(
      forName: .ksr_applicationDidEnterBackground, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.viewModel.viewWillDisappear() }
    }
  }
}

extension VideoViewController: AudioVideoViewControllerPlaybackDelegate {
  func pauseAudioVideoPlayback() {
    if self.playerController.player?.timeControlStatus == .playing {
      self.playerController.player?.pause()
    }
  }
}
