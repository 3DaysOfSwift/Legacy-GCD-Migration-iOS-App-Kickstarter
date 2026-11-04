import Foundation
import KsApi

public typealias CommentComposerViewData = (
  avatarURL: URL?,
  canPostComment: Bool,
  hidden: Bool,
  becomeFirstResponder: Bool
)

public enum CommentComposerConstant {
  // The API only supports comments not more than 9000 characters
  public static let characterLimit: Int = 9_000
}

public final class CommentComposerViewModel {
  public private(set) var bodyText: String?
  public init() {}
  public func bodyTextDidChange(_ text: String?) { self.bodyText = text }
  public func resetInput() { self.bodyText = nil }
  public var placeholderHidden: Bool { self.bodyText?.isEmpty == false }
  public var postButtonHidden: Bool { self.bodyText?.trimmed().isEmpty ?? true }
  public func textToSubmit() -> String? { self.bodyText?.trimmed() }
  public func textViewShouldChange(text: String?, in range: NSRange, replacementText: String) -> Bool {
    let currentText = text ?? ""
    guard let stringRange = Range(range, in: currentText) else { return false }
    let updated = currentText.replacingCharacters(in: stringRange, with: replacementText)
    return updated.trimmed().count <= CommentComposerConstant.characterLimit
  }
}
