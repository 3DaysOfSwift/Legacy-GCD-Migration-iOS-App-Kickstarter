import AVFoundation
import KsApi

@MainActor
public final class VideoViewModel {
  public var onCompletionBoundary: ((CMTime) -> Void)?
  public var onPlayerURL: ((URL) -> Void)?
  public var onReportCompletion: ((VoidEnvelope) -> Void)?
  public var onReportStart: ((VoidEnvelope) -> Void)?
  public var onFinish: (() -> Void)?
  public var onStart: (() -> Void)?
  public var onOpacity: ((CGFloat) -> Void)?
  public var onPause: (() -> Void)?
  public var onPlay: (() -> Void)?
  public var onPlayButtonHidden: ((Bool) -> Void)?
  public var onProjectImageHidden: ((Bool) -> Void)?
  public var onProjectImageURL: ((URL?) -> Void)?
  public var onSeekToBeginning: (() -> Void)?
  public var onVideoHidden: ((Bool) -> Void)?

  private let feature: ProjectMediaFeature
  private let route = UUID()
  private var project: (any VideoViewConfiguration)?
  private var loaded = false
  private var duration: CMTime?
  private var rateAndTime: (Double, CMTime)?
  private var lastPlayingTime: CMTime?
  private var hasStarted = false
  private var hasCompleted = false
  private var hasPlayed = false
  private var playHidden: Bool?
  private var imageHidden: Bool?
  private var hasImageURL = false
  private var imageURL: URL?
  private var playerURL: URL?
  private var startTask: Task<Void, Never>?
  private var completionTask: Task<Void, Never>?

  public init(feature: ProjectMediaFeature? = nil) {
    self.feature = feature ?? AppModel.shared.projectMediaFeature
  }

  public func configureWith(project: any VideoViewConfiguration) {
    self.project = project
    if self.loaded { self.displayProject(project); self.trackPlaybackIfReady() }
  }

  public func viewDidLoad() {
    self.loaded = true
    if let project = self.project { self.displayProject(project); self.trackPlaybackIfReady() }
    self.onOpacity?(0)
  }

  private func displayProject(_ project: any VideoViewConfiguration) {
    let properties = project.videoViewProperties
    self.setImageHidden(false)
    self.setPlayHidden(properties.video == nil)
    let url = URL(string: properties.photoFull)
    if !self.hasImageURL || self.imageURL != url {
      self.hasImageURL = true
      self.imageURL = url
      self.onProjectImageURL?(url)
    }
    if self.hasStarted, self.startTask == nil { self.startTask = self.report(project: project, completed: false) }
    if self.hasCompleted, self.completionTask == nil {
      self.completionTask = self.report(project: project, completed: true)
    }
  }

  public func playButtonTapped() {
    if self.loaded, let video = self.project?.videoViewProperties.video,
       let url = URL(string: video.hls ?? video.high ?? ""), self.playerURL != url {
      self.playerURL = url
      self.onPlayerURL?(url)
    }
    self.hasPlayed = true
    self.onPlay?()
    self.setImageHidden(true)
    self.setPlayHidden(true)
    self.onStart?()
  }

  public func durationChanged(toNew duration: CMTime) {
    guard self.duration != duration else { return }
    self.duration = duration
    self.onCompletionBoundary?(CMTimeMakeWithSeconds(0.85 * duration.seconds, preferredTimescale: 1))
    self.evaluateCompletionAndEnd()
    self.trackPlaybackIfReady()
  }

  public func rateChanged(toNew rate: Double, atTime currentTime: CMTime) {
    if let previous = self.rateAndTime, previous.0 == rate, previous.1 == currentTime { return }
    self.rateAndTime = (rate, currentTime)
    if rate == 1 { self.lastPlayingTime = currentTime; self.trackPlaybackIfReady() }
    if !self.hasStarted, rate == 1, currentTime == .zero {
      self.hasStarted = true
      if self.loaded, let project = self.project { self.startTask = self.report(project: project, completed: false) }
    }
    self.evaluateCompletionAndEnd()
  }

  private func evaluateCompletionAndEnd() {
    guard let duration = self.duration, let (_, time) = self.rateAndTime else { return }
    if time.seconds >= 0.85 * duration.seconds { self.crossedCompletionThreshold() }
    if time == duration {
      self.setImageHidden(false)
      self.setPlayHidden(false)
      self.onSeekToBeginning?()
      self.onFinish?()
    }
  }

  public func crossedCompletionThreshold() {
    guard !self.hasCompleted else { return }
    self.hasCompleted = true
    if self.loaded, let project = self.project { self.completionTask = self.report(project: project, completed: true) }
  }

  private func report(project: any VideoViewConfiguration, completed: Bool) -> Task<Void, Never> {
    let request = self.feature.requestReport(route: self.route, project: project, completed: completed)
    return Task { [weak self] in
      guard let value = await request.value, !Task.isCancelled, let self else { return }
      if completed { self.onReportCompletion?(value) } else { self.onReportStart?(value) }
    }
  }

  private func trackPlaybackIfReady() {
    guard self.loaded, let project = self.project, let duration = self.duration,
          let time = self.lastPlayingTime else { return }
    AppEnvironment.current.ksrAnalytics.trackProjectVideoPlaybackStarted(
      project: project, videoLength: lround(duration.seconds), videoPosition: lround(time.seconds)
    )
  }

  private func setPlayHidden(_ hidden: Bool) {
    guard self.playHidden != hidden else { return }
    self.playHidden = hidden
    self.onPlayButtonHidden?(hidden)
  }

  private func setImageHidden(_ hidden: Bool) {
    guard self.imageHidden != hidden else { return }
    self.imageHidden = hidden
    self.onProjectImageHidden?(hidden)
    self.onVideoHidden?(!hidden)
  }

  public func viewDidAppear() { if self.playHidden == false { self.onOpacity?(1) } }
  public func viewDidDisappear(animated: Bool) {}
  public func viewWillDisappear() { if self.hasPlayed { self.onPause?() } }
  internal func waitForReports() async { await self.startTask?.value; await self.completionTask?.value }

  deinit {
    self.startTask?.cancel()
    self.completionTask?.cancel()
    let feature = self.feature
    let route = self.route
    Task { @MainActor in feature.release(route: route) }
  }
}
