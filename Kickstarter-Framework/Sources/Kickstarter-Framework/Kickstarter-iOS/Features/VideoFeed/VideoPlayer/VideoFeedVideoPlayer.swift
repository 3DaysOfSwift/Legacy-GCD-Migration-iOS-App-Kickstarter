import AVFoundation
import AVKit
import Foundation

/// AVPlayer wrapper for a single video feed cell.
/// Loops by observing `AVPlayerItemDidPlayToEndTime` and seeking back to the start
@MainActor
@Observable
class VideoFeedVideoPlayer {
  // MARK: - Outputs

  private(set) var progress: Double = 0
  /// Total watch time in milliseconds. Excludes paused intervals.
  /// Resets when the player stops. Does not reset on scrub.
  private(set) var watchTimeMs: Int = 0

  var isPlaying: Bool { self.player.rate > 0 }
  let player = AVPlayer()
  var onVideoReady: (() -> Void)?
  /// Fired when the current item fails to load or play (e.g. an unsupported codec).
  var onVideoFailed: (() -> Void)?

  // MARK: - Private

  @ObservationIgnored private var startupTask: Task<Void, Never>?
  @ObservationIgnored private var recoveryTask: Task<Void, Never>?
  @ObservationIgnored private var seekTask: Task<Void, Never>?
  private var playbackVersion = UUID()
  private var seekVersion = UUID()
  private let sleep: @MainActor (Duration) async throws -> Void
  private let performSeek: @MainActor (AVPlayer, Double) async -> Bool
  @ObservationIgnored private var timeObserverToken: Any?
  @ObservationIgnored private var endObserver: (any NSObjectProtocol)?
  @ObservationIgnored private var failedObserver: (any NSObjectProtocol)?
  @ObservationIgnored private var stalledObserver: (any NSObjectProtocol)?
  /// Once `onReady` has fired, flip this so we don't fire it repeatedly.
  private var hasFiredOnReady = false
  private var hasFiredOnFailed = false

  // MARK: - Lifecycle

  init(
    sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    performSeek: @escaping @MainActor (AVPlayer, Double) async -> Bool = { player, progress in
      guard let duration = player.currentItem?.duration, duration.isNumeric else { return false }
      let target = CMTime(seconds: progress * duration.seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
      return await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }
  ) {
    self.sleep = sleep
    self.performSeek = performSeek
  }

  deinit {
    self.startupTask?.cancel()
    self.recoveryTask?.cancel()
    self.seekTask?.cancel()
    for observer in [self.endObserver, self.failedObserver, self.stalledObserver].compactMap({ $0 }) {
      NotificationCenter.default.removeObserver(observer)
    }
    let player = self.player
    let token = self.timeObserverToken
    // Only platform-resource cleanup survives the wrapper; callbacks capture it weakly.
    Task { @MainActor in
      player.currentItem?.cancelPendingSeeks()
      if let token { player.removeTimeObserver(token) }
    }
  }

  /// Replaces the current item with the URL's content and starts playback.
  /// Loops on completion via `AVPlayerItemDidPlayToEndTime`.
  func load(url: URL) {
    self.cancelPendingOperations()
    let version = self.playbackVersion
    self.hasFiredOnReady = false
    self.hasFiredOnFailed = false
    self.removeItemObservers()

    let item = AVPlayerItem(url: url)
    self.player.replaceCurrentItem(with: item)
    self.addTimeObserver()

    /// When this video ends, loop (seek) it back to the start.
    self.endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.player.currentItem === item, self.playbackVersion == version else { return }
        self.seek(to: 0) { [weak self] _ in self?.player.play() }
      }
    }

    /// Catches mid-playback failures (network drop, decoder errors, etc.).
    self.failedObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemFailedToPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.player.currentItem === item, self.playbackVersion == version else { return }
        self.notifyFailed()
      }
    }

    /// Catches errors caused by losing network connection mid-playback.
    /// AVPlayer triggers this when it can no longer load a video but doesn't transition to .failed it just freezes,
    /// `AVPlayerItemFailedToPlayToEndTime` never fires in this specific case.
    self.stalledObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.playbackStalledNotification,
      object: item,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.player.currentItem === item, self.playbackVersion == version else { return }
        // Keep the first pending stall deadline; repeated notifications must not
        // postpone the existing three-second recovery window.
        guard self.recoveryTask == nil else { return }
        let sleep = self.sleep
        self.recoveryTask = Task { [weak self] in
          defer {
            if self?.playbackVersion == version { self?.recoveryTask = nil }
          }
          do { try await sleep(.seconds(3)) } catch { return }
          guard !Task.isCancelled, let self, self.playbackVersion == version,
            self.player.currentItem === item, self.player.rate == 0 else { return }
          self.notifyFailed()
        }
      }
    }

    // Preserve the existing three-second startup failure check.
    let sleep = self.sleep
    self.startupTask = Task { [weak self] in
      do { try await sleep(.seconds(3)) } catch { return }
      guard !Task.isCancelled, let self, self.playbackVersion == version,
        self.player.currentItem === item, !self.hasFiredOnReady else { return }
      if item.error != nil || item.status == .failed { self.notifyFailed() }
    }
  }

  // MARK: - Playback control

  func play() {
    self.player.play()
  }

  func pause() {
    self.cancelSeek()
    self.player.pause()
  }

  /// Tears down the current item. Used on cell reuse.
  func stop() {
    self.cancelPendingOperations()
    self.removeItemObservers()

    self.player.pause()
    self.player.replaceCurrentItem(with: nil)

    self.progress = 0
    self.watchTimeMs = 0

    self.hasFiredOnReady = false
    self.hasFiredOnFailed = false
  }

  /// A replacement seek or stopped/reused cell cannot resume an obsolete item.
  @discardableResult
  func seek(to progress: Double, completion: ((Bool) -> Void)? = nil) -> Task<Void, Never> {
    self.cancelSeek()
    let version = self.seekVersion
    let playbackVersion = self.playbackVersion
    let item = self.player.currentItem
    let player = self.player
    let performSeek = self.performSeek
    let task = Task { [weak self] in
      guard !Task.isCancelled else { return }
      let finished = await performSeek(player, progress)
      guard !Task.isCancelled, let self, self.seekVersion == version,
        self.playbackVersion == playbackVersion, self.player.currentItem === item else { return }
      completion?(finished)
    }
    self.seekTask = task
    return task
  }

  private func cancelSeek() {
    self.seekVersion = UUID()
    self.seekTask?.cancel()
    self.player.currentItem?.cancelPendingSeeks()
  }

  private func cancelPendingOperations() {
    self.playbackVersion = UUID()
    if let token = self.timeObserverToken {
      self.player.removeTimeObserver(token)
      self.timeObserverToken = nil
    }
    self.startupTask?.cancel()
    self.recoveryTask?.cancel()
    self.recoveryTask = nil
    self.cancelSeek()
  }

  // MARK: - Private

  private func addTimeObserver() {
    let item = self.player.currentItem
    let version = self.playbackVersion
    let interval = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

    self.timeObserverToken = self.player.addPeriodicTimeObserver(
      forInterval: interval,
      queue: .main
    ) { [weak self] time in
      MainActor.assumeIsolated {
        guard let self, self.playbackVersion == version, self.player.currentItem === item,
              let duration = self.player.currentItem?.duration,
              duration.isNumeric,
              duration.seconds > 0
        else { return }

        /// First non-zero tick means a frame is being presented so we can trigger `onReady`.
        if !self.hasFiredOnReady, time.seconds > 0 {
          self.hasFiredOnReady = true
          self.onVideoReady?()
        }

        /// Watch time only while playing (rate > 0 means not paused).
        if self.player.rate > 0 {
          self.watchTimeMs = Int(time.seconds * 1_000)
        }

        self.progress = time.seconds / duration.seconds
      }
    }
  }

  /// Guards against calling `onVideoFailed` more than once per video feed item..
  /// Both the `AVPlayerItemFailedToPlayToEndTime` notification and the failed to load timeout can observe the same failure.
  private func notifyFailed() {
    guard !self.hasFiredOnFailed else { return }

    self.hasFiredOnFailed = true
    self.onVideoFailed?()
  }

  private func removeItemObservers() {
    if let endObserver = self.endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }

    self.endObserver = nil

    if let failedObserver = self.failedObserver {
      NotificationCenter.default.removeObserver(failedObserver)
    }

    self.failedObserver = nil

    if let stalledObserver = self.stalledObserver {
      NotificationCenter.default.removeObserver(stalledObserver)
    }

    self.stalledObserver = nil
  }
}
