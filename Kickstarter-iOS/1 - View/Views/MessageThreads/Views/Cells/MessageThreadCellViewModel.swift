import Foundation
import KsApi

@MainActor
struct MessageThreadPresentation {
  let date: String
  let dateAccessibilityLabel: String
  let messageBody: String
  let participantAvatarURL: URL?
  let participantName: String
  let projectName: String
  let replyIndicatorHidden: Bool
  let unreadIndicatorHidden: Bool

  init(thread: MessageThread) {
    let sentByCurrentUser = thread.lastMessage.sender.id == AppEnvironment.current.currentUser?.id
    self.date = Format.date(secondsInUTC: thread.lastMessage.createdAt, dateStyle: .short, timeStyle: .none)
    self.dateAccessibilityLabel = Format.date(
      secondsInUTC: thread.lastMessage.createdAt, dateStyle: .long, timeStyle: .none
    )
    self.messageBody = thread.lastMessage.body.replacingOccurrences(of: "\n", with: " ")
    self.participantAvatarURL = URL(string: thread.participant.avatar.medium)
    self.participantName = sentByCurrentUser
      ? "<b>\(Strings.messages_me())</b>, \(thread.participant.name)" : thread.participant.name
    self.projectName = thread.project.name
    self.replyIndicatorHidden = !sentByCurrentUser
    self.unreadIndicatorHidden = !hasUnreadMessages(for: thread)
  }
}

@MainActor
final class MessageThreadCellViewModel {
  private var thread: MessageThread?

  func configureWith(messageThread: MessageThread) -> MessageThreadPresentation {
    self.thread = messageThread
    return MessageThreadPresentation(thread: messageThread)
  }

  func setSelected(_ selected: Bool) {
    guard selected, let thread = self.thread else { return }
    markedAsRead(for: thread)
  }
}

@MainActor
private func hasUnreadMessages(for messageThread: MessageThread) -> Bool {
  return (AppEnvironment.current.cache[cacheKey(for: messageThread)] as? Bool)
    ?? (messageThread.unreadMessagesCount > 0)
}

private func cacheKey(for messageThread: MessageThread) -> String {
  return "\(KSCache.ksr_messageThreadHasUnreadMessages)_\(messageThread.id)"
}

@MainActor
private func markedAsRead(for messageThread: MessageThread) {
  AppEnvironment.current.cache[cacheKey(for: messageThread)] = false
}
