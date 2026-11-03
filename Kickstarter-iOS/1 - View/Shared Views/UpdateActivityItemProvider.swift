import KsApi
import UIKit

// SDK callback object with immutable value snapshots; no shared mutable Update.
public final class UpdateActivityItemProvider: UIActivityItemProvider, @unchecked Sendable {
  private let title: String
  private let url: String
  private let sequence: Int

  public init(update: Update) {
    self.title = update.title
    self.url = update.urls.web.update
    self.sequence = update.sequence
    super.init(placeholderItem: update.title)
  }

  public override func activityViewController(
    _ activityViewController: UIActivityViewController,
    itemForActivityType activityType: UIActivity.ActivityType?
  ) -> Any? {
    guard let type = activityType else {
      return self.activityViewControllerPlaceholderItem(activityViewController)
    }
    let text = [self.title, self.url].joined(separator: "\n")
    switch type {
    case .message: return text
    case .postToTwitter:
      return Strings.project_checkout_share_twitter_via_kickstarter(project_or_update_title: text)
    case .copyToPasteboard, .postToFacebook: return self.url
    default:
      return Strings.social_update_sequence_and_title(update_number: String(self.sequence), update_title: text)
    }
  }
}
