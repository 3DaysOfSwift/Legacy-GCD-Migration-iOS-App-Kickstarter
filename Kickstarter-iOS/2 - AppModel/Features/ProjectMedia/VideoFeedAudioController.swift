import Foundation
import AVFoundation
import MediaPlayer
import UIKit

@MainActor
public protocol AudioSessionManaging: AnyObject {
  func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode) throws
  func setActive(_ active: Bool) throws
  func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

@MainActor
private final class LiveAudioSession: AudioSessionManaging {
  static let shared = LiveAudioSession()

  func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode) throws {
    try AVAudioSession.sharedInstance().setCategory(category, mode: mode, options: [])
  }

  func setActive(_ active: Bool) throws {
    try AVAudioSession.sharedInstance().setActive(active)
  }

  func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
    try AVAudioSession.sharedInstance().setActive(active, options: options)
  }
}

// MARK: - Controller

/// Manages the AVAudioSession state machine for the video feed.
///
/// On iOS 26+, the session starts in `.soloAmbient` so the physical silent switch is respected.
/// When the user signals intent to hear audio (volume-up or the unmute overlay button), the session switches
/// to `.playback` to bypass the physical switch.
///
/// On iOS versions below 26, the session stays in `.playback` so that mute state is managed via the overlay button.
@MainActor
public final class VideoFeedAudioController {
  private let session: AudioSessionManaging

  public private(set) var isPlaybackSessionActive = false
  internal private(set) var isResettingAudioSession = false

  private var volumeObservation: NSKeyValueObservation?
  private var muteStateObserver: (any NSObjectProtocol)?

  private enum AudioEvent: Sendable { case volumeUp, silentSwitch }
  private var eventContinuation: AsyncStream<AudioEvent>.Continuation?
  internal private(set) var observationTask: Task<Void, Never>?
  private var observationVersion = UUID()
  internal private(set) var resetTask: Task<Void, Never>?
  private var resetVersion = UUID()
  private var volumeView: MPVolumeView?
  private var isDismissed = false
  private let nextTurn: @MainActor () async -> Void
  public private(set) var configurationError: Error?

  public var onVolumeUpDetected: (() -> Void)?

  public init(
    session: (any AudioSessionManaging)? = nil,
    nextTurn: @escaping @MainActor () async -> Void = { await Task.yield() }
  ) {
    self.session = session ?? LiveAudioSession.shared
    self.nextTurn = nextTurn
  }

  deinit {
    self.resetTask?.cancel()
    self.observationTask?.cancel()
    self.eventContinuation?.finish()
    self.volumeObservation?.invalidate()
    if let observer = self.muteStateObserver { NotificationCenter.default.removeObserver(observer) }
    // Bounded UIKit cleanup by value: never retain a deinitializing controller.
    // Avoid isolated deinit: the current toolchain crashes in its back-deployment
    // runtime when released from a synchronous XCTest/Objective-C main-thread call.
    let volumeView = self.volumeView
    Task { @MainActor in volumeView?.removeFromSuperview() }
  }

  public func configure() {
    self.isDismissed = false
    self.configurationError = nil
    do {
      if #available(iOS 26, *) {
        try self.session.setCategory(.soloAmbient, mode: .default)
      } else {
        try self.session.setCategory(.playback, mode: .default)
      }
      try self.session.setActive(true)
    } catch {
      self.configurationError = error
    }
  }

  /// Sets up volume up detection and silent switch observation on iOS 26+.
  /// `MPVolumeView` reroutes hardware volume buttons to media volume so `outputVolume` KVO fires in silent mode.
  @available(iOS 26, *)
  public func setupObservers(in view: UIView) {
    self.stopObserving()
    self.isDismissed = false
    let version = self.observationVersion
    let (events, continuation) = AsyncStream<AudioEvent>.makeStream()
    self.eventContinuation = continuation
    let volumeView = MPVolumeView(frame: .zero)
    volumeView.alpha = 0.001
    volumeView.isUserInteractionEnabled = false
    volumeView.accessibilityElementsHidden = true
    view.addSubview(volumeView)
    self.volumeView = volumeView

    // KVO may arrive off-main. Transfer only an immutable event into the owned
    // stream; no controller/session state is touched from the callback.
    self.volumeObservation = AVAudioSession.sharedInstance()
      .observe(\.outputVolume, options: [.old, .new]) { _, change in
        guard let old = change.oldValue, let new = change.newValue, new > old else { return }
        continuation.yield(.volumeUp)
      }
    self.muteStateObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.outputMuteStateChangeNotification, object: nil, queue: .main
    ) { _ in continuation.yield(.silentSwitch) }
    self.observationTask = Task { [weak self] in
      for await event in events {
        guard !Task.isCancelled, let self, !self.isDismissed,
          self.observationVersion == version else { return }
        switch event {
        case .volumeUp:
          self.handleVolumeUp()
          if self.isPlaybackSessionActive { self.onVolumeUpDetected?() }
        case .silentSwitch:
          self.handleSilentSwitchChange()
        }
      }
    }
  }

  private func stopObserving() {
    self.observationVersion = UUID()
    self.volumeObservation?.invalidate()
    self.volumeObservation = nil
    if let observer = self.muteStateObserver { NotificationCenter.default.removeObserver(observer) }
    self.muteStateObserver = nil
    self.eventContinuation?.finish()
    self.eventContinuation = nil
    self.observationTask?.cancel()
    self.observationTask = nil
    self.volumeView?.removeFromSuperview()
    self.volumeView = nil
  }

  /// Called when a volume-up press is detected.
  /// Switches to `.playback` to bypass the silent switch and marks the override as active.
  public func handleVolumeUp() {
    guard !self.isDismissed, !self.isResettingAudioSession else { return }

    self.activatePlayback()
  }

  /// Called when `outputMuteStateChangeNotification` fires (physical silent switch toggled).
  /// Resets the session to `.soloAmbient` so the switch takes effect.
  public func handleSilentSwitchChange() {
    guard !self.isDismissed else { return }
    self.resetSession()
  }

  /// Called when the overlay mute button is tapped and the result is unmuted.
  /// Switches to `.playback` so the overlay can override the silent switch.
  public func handleOverlayUnmute() {
    self.activatePlayback()
  }

  /// Called when a new video is activated.
  public func handleNewVideoActivated() {
    guard !self.isDismissed else { return }
    if self.isPlaybackSessionActive {
      try? self.session.setCategory(.playback, mode: .default)
      try? self.session.setActive(true)
    } else {
      self.resetSession()
    }
  }

  /// Called on dismiss. Resets to `.soloAmbient` so the feed doesn't hold `.playback` after leaving.
  public func handleDismiss() {
    self.isDismissed = true
    self.stopObserving()
    self.resetVersion = UUID()
    self.resetTask?.cancel()
    self.isResettingAudioSession = false
    self.isPlaybackSessionActive = false
    try? self.session.setCategory(.soloAmbient, mode: .default)
  }

  // MARK: - Private

  private func activatePlayback() {
    guard !self.isDismissed else { return }
    try? self.session.setCategory(.playback, mode: .default)
    try? self.session.setActive(true)

    self.isPlaybackSessionActive = true
  }

  internal func waitForReset() async { await self.resetTask?.value }

  private func resetSession() {
    self.resetTask?.cancel()
    let version = UUID()
    self.resetVersion = version
    self.isResettingAudioSession = true
    self.isPlaybackSessionActive = false

    try? self.session.setActive(false, options: .notifyOthersOnDeactivation)
    try? self.session.setCategory(.soloAmbient, mode: .default)
    try? self.session.setActive(true)

    let nextTurn = self.nextTurn
    self.resetTask = Task { [weak self] in
      await nextTurn()
      guard !Task.isCancelled, let self, !self.isDismissed, self.resetVersion == version else { return }
      self.isResettingAudioSession = false
      self.resetTask = nil
    }
  }
}
