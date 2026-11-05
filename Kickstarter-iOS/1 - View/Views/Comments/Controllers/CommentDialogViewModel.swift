import Foundation
import KsApi
import Prelude

public struct CommentDialogData {
  public let project: Project
  public let update: Update?
  public let recipientName: String?
  public let context: KSRAnalytics.CommentDialogContext
}

@MainActor
final class CommentDialogViewModel {
  enum Event {
    case body(String)
    case postEnabled(Bool)
    case loadingHidden(Bool)
    case posted(Comment)
    case dismiss
    case subtitle(String)
    case keyboard(Bool)
    case error(String)
  }

  var onEvent: ((Event) -> Void)?
  private let discussionFeature: DiscussionFeature
  private let sleep: @MainActor () async throws -> Void
  private var data: CommentDialogData?
  private var activeData: CommentDialogData?
  private var currentUser: User?
  private var body: String?
  private var enabled: Bool?
  private var postTask: Task<Void, Never>?

  init(feature: DiscussionFeature? = nil, sleep: @escaping @MainActor () async throws -> Void = {
    try await Task.sleep(for: .seconds(1))
  }) {
    self.discussionFeature = feature ?? AppModel.shared.discussionFeature
    self.sleep = sleep
  }

  func configureWith(project: Project, update: Update?, recipientName: String?, context: KSRAnalytics.CommentDialogContext) {
    self.data = CommentDialogData(project: project, update: update, recipientName: recipientName, context: context)
  }

  func viewWillAppear() {
    if self.enabled == nil { self.publishEnabled(false) }
    self.onEvent?(.loadingHidden(true))
    self.onEvent?(.keyboard(true))
    self.currentUser = AppEnvironment.current.currentUser
    guard let data = self.data else { return }
    self.activeData = data
    self.onEvent?(.subtitle(data.project.name))
    if let recipient = data.recipientName { self.onEvent?(.body("@\(recipient): ")) }
  }

  func viewWillDisappear() { self.onEvent?(.keyboard(false)) }

  func commentBodyChanged(_ text: String) {
    self.body = text
    self.publishEnabled(!text.isEmpty)
  }

  func cancelButtonPressed() { self.onEvent?(.dismiss) }

  func postButtonPressed() {
    guard let body = self.body, let user = self.currentUser, let data = self.activeData else { return }
    self.postTask?.cancel()
    let feature = self.discussionFeature
    let sessionID = feature.sessionFeature.generation
    let userID = AppEnvironment.current.currentUser?.id
    let commentableID = data.update.map { encodeToBase64("FreeformPost-\($0.id)") } ?? data.project.graphID
    let submission = feature.beginPost(
      project: data.project, commentableID: commentableID, parentID: nil, user: user, body: body
    )
    self.onEvent?(.loadingHidden(false))
    self.publishEnabled(false)
    let sleep = self.sleep
    self.postTask = Task { [weak self] in
      let result: Result<Comment, Error>
      do {
        result = .success(try await submission.result.value)
      } catch { result = .failure(error) }
      do { try await sleep() } catch { return }
      guard !Task.isCancelled, let self,
            feature.sessionFeature.isCurrent(userID: userID, generation: sessionID) else { return }
      switch result {
      case let .success(comment) where comment.status != .failed:
        self.onEvent?(.posted(comment))
        self.onEvent?(.dismiss)
      case .success, .failure:
        self.onEvent?(.error(Strings.Something_went_wrong_please_try_again()))
      }
      self.onEvent?(.loadingHidden(true))
      self.publishEnabled(true)
    }
    self.onEvent?(.posted(submission.comment))
    self.onEvent?(.dismiss)
  }

  func waitForMutations() async { await self.postTask?.value }

  deinit { self.postTask?.cancel() }

  private func publishEnabled(_ value: Bool) {
    guard self.enabled != value else { return }
    self.enabled = value
    self.onEvent?(.postEnabled(value))
  }
}
