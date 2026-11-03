import KsApi
import UIKit

// UIActivityItemProvider is SDK-Sendable. This subclass adds immutable String
// snapshots only; it never carries the mutable service Project across callbacks.
public final class ProjectActivityItemProvider: UIActivityItemProvider, @unchecked Sendable {
  private let projectName: String
  private let projectURL: String

  public init(project: Project) {
    self.projectName = project.name
    self.projectURL = project.urls.web.project
    super.init(placeholderItem: project.name)
  }

  public override func activityViewController(
    _ activityViewController: UIActivityViewController,
    itemForActivityType activityType: UIActivity.ActivityType?
  ) -> Any? {
    let text = [self.projectName, self.projectURL].joined(separator: "\n")
    if activityType == .postToTwitter {
      return Strings.project_checkout_share_twitter_via_kickstarter(project_or_update_title: text)
    }
    if activityType == .copyToPasteboard || activityType == .postToFacebook { return self.projectURL }
    return text
  }
}
