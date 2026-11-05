import KsApi
import Prelude
import UIKit

public struct ShareActivityCompletionData {
  internal let activityType: UIActivity.ActivityType?
  internal let completed: Bool
  internal let returnedItems: [Any]?
  internal let activityError: Error?

  public init(
    activityType: UIActivity.ActivityType?,
    completed: Bool,
    returnedItems: [Any]?,
    activityError: Error?
  ) {
    self.activityType = activityType
    self.completed = completed
    self.returnedItems = returnedItems
    self.activityError = activityError
  }
}

@MainActor
public final class ShareViewModel {
  public var onShareSheet: ((UIActivityViewController, UIView?) -> Void)?
  private var context: (ShareContext, UIView?)?
  public init() {}
  public func configureWith(shareContext: ShareContext, shareContextView: UIView?) {
    self.context = (shareContext, shareContextView)
  }
  public func shareButtonTapped() {
    guard let (context, source) = self.context,
          let controller = activityController(forShareContext: context) else { return }
    self.onShareSheet?(controller, source)
  }
}

@MainActor
private func activityItemProvider(forShareContext shareContext: ShareContext) -> UIActivityItemProvider {
  switch shareContext {
  case let .discovery(project):
    return ProjectActivityItemProvider(project: project)
  case let .project(project):
    return ProjectActivityItemProvider(project: project)
  case let .thanks(project):
    return ProjectActivityItemProvider(project: project)
  case let .update(_, update):
    return UpdateActivityItemProvider(update: update)
  }
}

private func shareUrl(forShareContext shareContext: ShareContext) -> URL? {
  switch shareContext {
  case let .discovery(project):
    return URL(string: project.urls.web.project)
  case let .project(project):
    return URL(string: project.urls.web.project)
  case let .thanks(project):
    return URL(string: project.urls.web.project)
  case let .update(_, update):
    return URL(string: update.urls.web.update)
  }
}

private func excludedActivityTypes(forShareContext shareContext: ShareContext) -> [UIActivity.ActivityType] {
  switch shareContext {
  case let .update(_, update) where !update.isPublic:
    return [.mail, .message, .postToFacebook, .postToTwitter, .postToWeibo]
  default:
    return []
  }
}

@MainActor
private func activityController(forShareContext shareContext: ShareContext) -> UIActivityViewController? {
  guard let url = shareUrl(forShareContext: shareContext) else { return nil }

  let provider = activityItemProvider(forShareContext: shareContext)
  let safariUrl = SafariURL(url: url)

  let controller = UIActivityViewController(
    activityItems: [provider, safariUrl],
    applicationActivities: [SafariActivity(url: safariUrl)]
  )

  controller.excludedActivityTypes = excludedActivityTypes(forShareContext: shareContext)

  return controller
}
