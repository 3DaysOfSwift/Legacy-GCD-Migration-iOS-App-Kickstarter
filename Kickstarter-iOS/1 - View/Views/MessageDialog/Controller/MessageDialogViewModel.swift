import Foundation
import KsApi
import Prelude

@MainActor
public final class MessageDialogViewModel {
  var onKeyboardVisibility: ((Bool) -> Void)?
  var onLoadingHidden: ((Bool) -> Void)?
  var onPosted: ((Message) -> Void)?
  var onDismiss: (() -> Void)?
  var onPostEnabled: ((Bool) -> Void)?
  var onRecipient: ((String) -> Void)?
  var onError: ((String) -> Void)?

  private let feature: MessagingFeature
  private let sleep: (TimeInterval) async throws -> Void
  private var subject: MessageSubject?
  private var body: String?
  private var enabled = false
  private var sendTask: Task<Void, Never>?
  private var sendVersion = UUID()

  public convenience init() { self.init(feature: AppModel.shared.messagingFeature) }
  public init(feature: MessagingFeature, sleep: @escaping (TimeInterval) async throws -> Void = { delay in
    if delay.isInfinite { try await Task.sleep(nanoseconds: UInt64.max) }
    else if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
  }) {
    self.feature = feature
    self.sleep = sleep
  }

  public func configureWith(messageSubject: MessageSubject, context _: KSRAnalytics.MessageDialogContext) {
    self.subject = messageSubject
  }

  public func viewDidLoad() {
    self.enabled = false
    self.onPostEnabled?(false)
    self.onLoadingHidden?(true)
    if let subject = self.subject {
      switch subject {
      case let .messageThread(thread): self.onRecipient?(thread.participant.name)
      case let .project(_, name): self.onRecipient?(name)
      }
    }
    self.onKeyboardVisibility?(true)
  }

  public func bodyTextChanged(_ body: String) {
    self.body = body
    let enabled = !body.trimmed().isEmpty
    guard enabled != self.enabled else { return }
    self.enabled = enabled
    self.onPostEnabled?(enabled)
  }

  public func cancelButtonPressed() {
    self.sendVersion = UUID()
    self.sendTask?.cancel()
    self.sendTask = nil
    self.onKeyboardVisibility?(false)
    self.onDismiss?()
  }

  public func postButtonPressed() {
    self.onLoadingHidden?(false)
    guard let body = self.body, let subject = self.subject else { return }
    self.sendTask?.cancel()
    let version = UUID()
    self.sendVersion = version
    let session = self.feature.sessionFeature
    let userID = session.currentUser?.id
    let generation = session.generation
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    // Admit the write immediately; canceling presentation must not cancel a sent message.
    let command = self.feature.requestSend(body: body, subject: subject)
    let sleep = self.sleep
    self.sendTask = Task { [weak self] in
      let result = await command.result
      do {
        try await sleep(delay)
        try Task.checkCancellation()
      } catch { return }
      guard let self, self.sendVersion == version,
            session.isCurrent(userID: userID, generation: generation) else { return }
      self.sendTask = nil
      switch result {
      case let .success(message):
        self.onPosted?(message)
        self.onKeyboardVisibility?(false)
        self.onDismiss?()
        self.onLoadingHidden?(true)
      case let .failure(error):
        guard !(error is CancellationError) else { return }
        self.onError?((error as? ErrorEnvelope)?.errorMessages.first ?? Strings.messages_dialog_generic_error())
        self.onLoadingHidden?(true)
      }
    }
  }

  func waitForSend() async { await self.sendTask?.value }
}
