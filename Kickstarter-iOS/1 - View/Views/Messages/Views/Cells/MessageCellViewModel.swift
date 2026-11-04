import Foundation
import KsApi

@MainActor
public final class MessageCellViewModel {
  struct Display {
    let avatarURL: URL?
    let name: String
    let timestamp: String
    let timestampAccessibilityLabel: String
    let body: String
  }

  var onDisplay: ((Display) -> Void)?
  var onSender: ((User) -> Void)?
  private var message: Message?

  func configureWith(message: Message) {
    self.message = message
    self.onDisplay?(Display(
      avatarURL: URL(string: message.sender.avatar.large ?? message.sender.avatar.medium),
      name: message.sender.name,
      timestamp: Format.date(secondsInUTC: message.createdAt, dateStyle: .short, timeStyle: .short),
      timestampAccessibilityLabel: Format.date(secondsInUTC: message.createdAt, dateStyle: .long, timeStyle: .short),
      body: message.body
    ))
  }

  func cellHeaderTapped() {
    if let sender = self.message?.sender { self.onSender?(sender) }
  }
}
