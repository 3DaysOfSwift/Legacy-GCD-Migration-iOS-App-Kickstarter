import Foundation
import KsApi
import SwiftUI

@MainActor
public protocol VideoFeedViewModelType: AnyObject {
  /// Current active set of video items shown in the feed.
  var items: [VideoFeedItem] { get }
  /// Updated only on a completed fetch. Used to trigger collection view reloads.
  var fetchedItems: [VideoFeedItem] { get }
  /// Set when a logged-out user taps save. Triggers the login flow.
  var loginIntent: LoginIntent? { get }
  /// True once the first fetch completes successfully.
  var isInitialLoadComplete: Bool { get }
  /// Project ID of the most recent failed save. Triggers the error toast on the selected cell.
  var saveFailedItemId: String? { get }
  /// True when all videos in the feed are muted. Persists.
  var isMuted: Bool { get }
  /// Kicks off the initial feed fetch.
  func viewDidLoad()
  /// Syncs save state from the project page cache on return to the feed.
  func viewWillAppear()
  /// Fires any save the user tapped before logging in.
  func userSessionStarted()
  /// Optimistically toggles the saved state; the Feature orders writes for each project.
  func toggleSaved(for item: VideoFeedItem)
  /// Returns a binding to the saved state for the given project ID.
  func isSaved(projectId: String) -> Binding<Bool>
  /// Clears the pending login intent after the login flow is presented.
  func clearLoginIntent()
  /// Clears the save error after the toast has been shown.
  func clearSaveFailedItemId()
  /// Toggles mute state for all videos and persists the new value.
  func toggleMute()
  /// Tracks a swipe to a new video, then fires an impression for the incoming video.
  func trackPageViewed(atIndex index: Int, totalWatchTimeMs: Int, totalVideoDurationMs: Int)
  /// Tracks a CTA tap in the video feed (play, pause, save, share).
  func trackCTAClicked(ctaContext: KSRAnalytics.CTAContext, item: VideoFeedItem)
  func trackProgressBarTapped(item: VideoFeedItem, positionInSession: Int, percentageWatched: Float)
}

@Observable @MainActor
public final class VideoFeedViewModel: VideoFeedViewModelType {
  // MARK: - Outputs

  /// The current working set of items.
  /// Updated optimistically on watch/unwatch.
  public var items: [VideoFeedItem] { self.feed.items }

  /// Updated only when a real fetch completes.
  /// Allows `VideoFeedViewController` to know when to reload the collection view.
  public var fetchedItems: [VideoFeedItem] { self.feed.fetchedItems }

  public var isLoading: Bool { self.feed.isLoading }
  public var errorMessage: String? {
    if self.feed.error is ProjectMediaFeature
      .FeedError { return Strings.Something_went_wrong_please_try_again() }
    return self.feed.error?.localizedDescription
  }

  public private(set) var loginIntent: LoginIntent? = nil
  public var isInitialLoadComplete: Bool { self.feed.isInitialLoadComplete }

  /// Set to the project ID of an item whose save/unsave request failed.
  /// Observed by `VideoFeedViewController` to trigger the error toast on the correct cell.
  public var saveFailedItemId: String? { self.feed.saveFailedItemID }

  public private(set) var isMuted: Bool = VideoFeedViewModel.persistedIsMuted

  private static var persistedIsMuted: Bool = false

  /// Store the item id when a logged-out user taps save. Finishes executing on `userSessionStarted` if login succeeded.
  private var pendingSaveItemId: String? = nil

  private let projectMediaFeature: ProjectMediaFeature
  private let route: UUID
  private let feed: ProjectMediaFeature.FeedState
  @ObservationIgnored private var loadingTask: Task<Void, Never>?

  private var lastPageIndex: Int = 0

  // MARK: - Init

  public init(projectMediaFeature: ProjectMediaFeature? = nil) {
    let feature = projectMediaFeature ?? AppModel.shared.projectMediaFeature
    let route = UUID()
    self.projectMediaFeature = feature
    self.route = route
    self.feed = feature.feedState(route: route)
  }

  deinit {
    self.loadingTask?.cancel()
    let feature = self.projectMediaFeature
    let route = self.route
    // Bounded MainActor cleanup; durable saves are owned by the Feature.
    Task { @MainActor in feature.release(route: route) }
  }

  // MARK: - Inputs

  public func viewDidLoad() {
    self.loadingTask = self.projectMediaFeature.requestFeed(route: self.route)
  }

  /// Called each time the feed reappears.
  /// Reconciles the save button's state for when users save projects from a presented project page (when tapping the CTA).
  public func viewWillAppear() {
    self.projectMediaFeature.reconcileSavedProjects(route: self.route)
  }

  /// Called after login completes. Fires any save that was deferred due to a pending login.
  public func userSessionStarted() {
    guard let pendingId = self.pendingSaveItemId, self.projectMediaFeature.hasCurrentUser,
          let item = self.items.first(where: { $0.id == pendingId }) else {
      self.pendingSaveItemId = nil
      return
    }

    self.pendingSaveItemId = nil
    self.toggleSaved(for: item)
  }

  /// Returns a binding to `isSaved` for the item with the given ID.
  /// If the user is logged out, save the intended id to save and show login instead.
  public func isSaved(projectId: String) -> Binding<Bool> {
    Binding(
      get: { self.items.first(where: { $0.id == projectId })?.isSaved ?? false },
      set: { [weak self] _ in
        guard let self, let item = self.items.first(where: { $0.id == projectId }) else { return }

        guard self.projectMediaFeature.hasCurrentUser else {
          self.pendingSaveItemId = item.id
          self.showLogin()

          return
        }

        self.toggleSaved(for: item)
      }
    )
  }

  /// Immediate visual feedback; the Feature orders durable writes per project.
  public func toggleSaved(for item: VideoFeedItem) {
    self.projectMediaFeature.toggleSaved(
      route: self.route, projectID: item.id
    )
  }

  public func clearLoginIntent() {
    self.loginIntent = nil
  }

  public func clearSaveFailedItemId() {
    self.projectMediaFeature.clearSaveFailure(route: self.route)
  }

  public func toggleMute() {
    self.isMuted.toggle()
    VideoFeedViewModel.persistedIsMuted = self.isMuted
  }

  public func trackPageViewed(atIndex index: Int, totalWatchTimeMs: Int, totalVideoDurationMs: Int) {
    guard index < self.items.count else { return }

    let incoming = self.items[index]
    let outgoing = self.items[self.lastPageIndex]

    AppEnvironment.current.ksrAnalytics.trackVideoFeedSwipe(
      videoId: incoming.id,
      projectId: incoming.projectId,
      positionInSession: index,
      fromVideoId: outgoing.id,
      totalWatchTimeMs: totalWatchTimeMs,
      totalVideoDurationMs: totalVideoDurationMs
    )

    AppEnvironment.current.ksrAnalytics.trackVideoFeedImpression(
      videoId: incoming.id,
      projectId: incoming.projectId,
      positionInSession: index
    )

    self.lastPageIndex = index
  }

  public func trackCTAClicked(ctaContext: KSRAnalytics.CTAContext, item: VideoFeedItem) {
    AppEnvironment.current.ksrAnalytics.trackVideoFeedCTAClicked(
      ctaContext: ctaContext,
      videoId: item.id,
      projectId: item.projectId
    )
  }

  public func trackProgressBarTapped(item: VideoFeedItem, positionInSession: Int, percentageWatched: Float) {
    AppEnvironment.current.ksrAnalytics.trackVideoFeedProgressBarTapped(
      videoId: item.id,
      projectId: item.projectId,
      positionInSession: positionInSession,
      percentageWatched: percentageWatched
    )
  }

  // MARK: - Private

  /// Triggers the login flow. Called when a logged-out user tries to save a project.
  private func showLogin() {
    self.loginIntent = .videoFeed
  }

  func fetchVideoFeed() async {
    self.loadingTask = self.projectMediaFeature.requestFeed(route: self.route)
    await self.loadingTask?.value
  }

  func waitForSaves() async {
    await self.projectMediaFeature.waitForSaves(route: self.route)
  }
}
