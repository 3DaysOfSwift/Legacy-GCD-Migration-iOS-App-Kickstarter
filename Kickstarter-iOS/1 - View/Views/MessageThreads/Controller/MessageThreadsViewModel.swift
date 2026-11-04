import Foundation
import KsApi
import Observation

@MainActor
@Observable
public final class MessageThreadsViewModel {
  public private(set) var emptyStateIsVisible = false
  public private(set) var loadingFooterIsHidden = false
  public private(set) var mailboxName = ""
  public private(set) var messageThreads: [MessageThread] = []
  public private(set) var isRefreshing = false
  public var onSearch: (() -> Void)?
  public var onMailboxChooser: (() -> Void)?

  private let feature: MessagingFeature
  private let route = UUID()
  private var project: Project?
  private var mailbox: Mailbox?
  private var isNearBottom = false
  private var requestGeneration = 0
  private var hadRequested = false
  private var projectionTask: Task<Void, Never>?

  public convenience init() { self.init(feature: AppModel.shared.messagingFeature) }
  public init(feature: MessagingFeature) { self.feature = feature }

  deinit {
    let feature = self.feature, route = self.route
    Task { @MainActor in feature.release(route: route) }
  }

  public func configureWith(project: Project?, refTag _: RefTag?) { self.project = project }
  public func mailboxButtonPressed() { self.onMailboxChooser?() }
  public func searchButtonPressed() { self.onSearch?() }
  public func viewDidLoad() { self.switchTo(mailbox: .inbox) }
  public func switchTo(mailbox: Mailbox) {
    self.mailbox = mailbox
    self.mailboxName = mailbox == .inbox ? Strings.messages_navigation_inbox() : Strings.messages_navigation_sent()
    self.loadingFooterIsHidden = false
    self.loadFirstPage()
  }
  public func refresh() {
    guard self.mailbox != nil else { return }
    self.isRefreshing = true
    self.loadFirstPage()
  }
  public func willDisplayRow(_ row: Int, outOf totalRows: Int) {
    guard totalRows > 1 else { return }
    let nearBottom = row >= totalRows - 3
    defer { self.isNearBottom = nearBottom }
    guard nearBottom, !self.isNearBottom else { return }
    self.loadingFooterIsHidden = false
    guard let task = self.feature.requestNextPage(route: self.route) else { return }
    self.projectResult(task)
  }

  internal func waitForPresentation() async { await self.projectionTask?.value }

  private func loadFirstPage() {
    guard let mailbox = self.mailbox else { return }
    if self.hadRequested { self.messageThreads = [] }
    self.hadRequested = true
    let task = self.feature.requestMailbox(route: self.route, mailbox: mailbox, project: self.project, refresh: true)
    self.projectResult(task)
  }

  private func projectResult(_ task: Task<Void, Never>) {
    self.requestGeneration += 1
    let generation = self.requestGeneration
    self.projectionTask?.cancel()
    self.projectionTask = Task { [weak self] in
      await task.value
      guard let self, !Task.isCancelled, self.requestGeneration == generation else { return }
      let snapshot = self.feature.snapshot(route: self.route)
      if snapshot.error == nil {
        self.messageThreads = snapshot.threads
        self.emptyStateIsVisible = snapshot.threads.isEmpty
      }
      self.isRefreshing = false
      self.loadingFooterIsHidden = true
    }
  }
}
