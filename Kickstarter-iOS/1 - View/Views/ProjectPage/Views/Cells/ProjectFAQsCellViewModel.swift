import KsApi
import Observation

@MainActor
@Observable
public final class ProjectFAQsCellViewModel {
  public init() {}
  public private(set) var answer = ""
  public private(set) var question = ""
  public private(set) var isExpanded = false
  public private(set) var updatedText: String?

  public func configureWith(value: (ProjectFAQ, Bool)) {
    let (faq, expanded) = value
    self.answer = faq.answer
    self.question = faq.question
    self.isExpanded = expanded
    if let createdAt = faq.createdAt {
      self.updatedText = "Updated \(Format.date(secondsInUTC: createdAt, template: "MMM d, yyyy"))"
    }
  }
}
