import Foundation
import UserNotifications

/// Each delivery owns its download and may finish exactly once, including when
/// the system expires the extension while a download or attachment is finishing.
final class NotificationService: UNNotificationServiceExtension {
  private let lock = NSLock()
  private var delivery: NotificationDelivery?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler handler: @escaping (UNNotificationContent) -> Void
  ) {
    let next = NotificationDelivery(content: request.content, handler: handler)
    self.lock.lock()
    let previous = self.delivery
    self.delivery = next
    self.lock.unlock()
    previous?.expire()
    next.start()
  }

  override func serviceExtensionTimeWillExpire() {
    self.lock.lock()
    let current = self.delivery
    self.lock.unlock()
    current?.expire()
  }

  deinit { self.delivery?.expire() }
}

/// The lock guards the task and the one-time ownership transfer of SDK content
/// and its completion handler. Neither cancellation nor handler invocation runs
/// under the lock. No mutable notification content is shared with the worker.
final class NotificationDelivery: @unchecked Sendable {
  typealias Download = @Sendable (URL) async throws -> URL
  private let lock = NSLock()
  private var content: UNNotificationContent?
  private var handler: ((UNNotificationContent) -> Void)?
  private var task: Task<Void, Never>?
  private var started = false
  private let attachmentURL: URL?
  private let attachmentType: String?

  init(content: UNNotificationContent, handler: @escaping (UNNotificationContent) -> Void) {
    self.content = content
    self.handler = handler
    let payload = content.userInfo["ab"] as? [AnyHashable: Any]
    let attachment = payload?["att"] as? [AnyHashable: Any]
    self.attachmentURL = (attachment?["url"] as? String).flatMap(URL.init(string:))
    self.attachmentType = attachment?["type"] as? String
  }

  @discardableResult
  func start(download: @escaping Download = { try await NotificationDelivery.download($0) }) -> Task<Void, Never>? {
    self.lock.lock()
    let shouldStart = !self.started && self.handler != nil
    self.started = true
    self.lock.unlock()
    guard shouldStart else { return nil }
    guard let url = self.attachmentURL, let type = self.attachmentType else {
      self.finish()
      return nil
    }

    let worker = Task { [self] in
      do {
        try Task.checkCancellation()
        let temporaryURL = try await download(url)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try Task.checkCancellation()
        let typedURL = URL(fileURLWithPath: temporaryURL.path + "." + type)
        try FileManager.default.moveItem(at: temporaryURL, to: typedURL)
        let attachment = try UNNotificationAttachment(identifier: "", url: typedURL, options: nil)
        try Task.checkCancellation()
        self.finish(attachment: attachment)
      } catch {
        self.finish()
      }
    }
    self.lock.lock()
    let alreadyFinished = self.handler == nil
    if !alreadyFinished { self.task = worker }
    self.lock.unlock()
    // Expiry or synchronous completion can win before the worker is installed.
    if alreadyFinished { worker.cancel() }
    return worker
  }

  func expire() { self.finish() }

  private func finish(attachment: UNNotificationAttachment? = nil) {
    self.lock.lock()
    let handler = self.handler
    let original = self.content
    let worker = self.task
    self.handler = nil
    self.content = nil
    self.task = nil
    self.lock.unlock()
    worker?.cancel()
    guard let handler, let original else { return }
    if let attachment, let modified = original.mutableCopy() as? UNMutableNotificationContent {
      modified.attachments = [attachment]
      handler(modified)
    } else {
      handler(original)
    }
  }

  private static func download(_ url: URL) async throws -> URL {
    let session = URLSession(configuration: .default)
    defer { session.finishTasksAndInvalidate() }
    let (file, _) = try await session.download(from: url)
    return file
  }
}
