import Foundation
import KsApi
import Observation

@MainActor
@Observable
public final class MessagesSearchViewModel {
  public private(set) var isSearching = false
  public private(set) var messageThreads: [MessageThread] = []
  public var onMessageThread: ((MessageThread) -> Void)?

  private let feature: MessagingFeature
  private let sleep: (TimeInterval) async throws -> Void
  private var project: Project?
  private var query = ""
  private var isVisible = true
  private var didLoad = false
  private var searchTask: Task<Void, Never>?
  private var revision = 0

  public convenience init() { self.init(feature: AppModel.shared.messagingFeature) }
  public init(feature: MessagingFeature, sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
    if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
  }) {
    self.feature = feature
    self.sleep = sleep
  }

  public func clearSearchText() { self.searchTextChanged("") }
  public func configureWith(project: Project?) { self.project = project }
  public func viewDidLoad() { self.didLoad = true }
  public func viewWillAppear() { self.isVisible = true }
  public func viewWillDisappear() {
    self.isVisible = false
    self.revision += 1
    self.searchTask?.cancel()
    self.isSearching = false
  }
  public func tappedMessageThread(_ thread: MessageThread) { self.onMessageThread?(thread) }
  public func searchTextChanged(_ text: String?) {
    let query = text ?? ""
    guard query != self.query else { return }
    self.query = query
    self.revision += 1
    let revision = self.revision
    self.searchTask?.cancel()
    self.messageThreads = []
    self.isSearching = !query.isEmpty
    guard !query.isEmpty else { return }
    let delay = AppEnvironment.current.debounceInterval.searchDelaySeconds
    self.searchTask = Task { [weak self, feature, sleep] in
      do {
        try await sleep(delay)
        try Task.checkCancellation()
        guard let self, self.isVisible, self.didLoad, self.revision == revision else { return }
        let results = try await feature.search(query: query, project: self.project)
        try Task.checkCancellation()
        guard self.isVisible, self.revision == revision else { return }
        self.messageThreads = results
        self.isSearching = false
      } catch {
        guard let self, !Task.isCancelled, self.revision == revision else { return }
        self.isSearching = false
      }
    }
  }
  internal func waitForSearch() async { await self.searchTask?.value }
}
