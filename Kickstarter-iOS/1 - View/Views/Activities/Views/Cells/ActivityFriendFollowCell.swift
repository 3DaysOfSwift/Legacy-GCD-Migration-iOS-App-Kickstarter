import KDS
import KsApi

import Prelude
import UIKit

internal final class ActivityFriendFollowCell: UITableViewCell, ValueCell {
  fileprivate let viewModel: ActivityFriendFollowCellViewModel = ActivityFriendFollowCellViewModel()

  @IBOutlet fileprivate var cardView: UIView!
  @IBOutlet fileprivate var containerView: UIView!
  @IBOutlet fileprivate var friendImageView: UIImageView!
  @IBOutlet fileprivate var friendLabel: UILabel!
  @IBOutlet fileprivate var followButton: UIButton!

  func configureWith(value: Activity) {
    self.viewModel.configureWith(activity: value)
    guard value.user != nil else { return }
    self.followButton.isHidden = self.viewModel.hideFollowButton ?? false
    self.friendLabel.attributedText = self.viewModel.title
    self.friendImageView.af.cancelImageRequest()
    self.friendImageView.image = nil
    if let url = self.viewModel.friendImageURL { self.friendImageView.ksr_setImageWithURL(url) }
  }

  override func bindViewModel() {
    super.bindViewModel()
    self.viewModel.onChange = { [weak self] in
      guard let self, let hidden = self.viewModel.hideFollowButton else { return }
      self.followButton.isHidden = hidden
    }
  }

  override func bindStyles() {
    super.bindStyles()

    _ = self
      |> feedTableViewCellStyle

    _ = self.cardView
      |> cardStyle()

    _ = self.containerView
      |> UIView.lens.layoutMargins .~ .init(topBottom: Styles.grid(3), leftRight: Styles.grid(2))

    self.containerView.backgroundColor = Colors.Background.Surface.primary.uiColor()

    _ = self.friendImageView
      |> ignoresInvertColorsImageViewStyle

    _ = self.friendLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()

    self.followButton.applyStyleConfiguration(KSRButtonStyle.filled)

    _ = self.followButton
      |> UIButton.lens.targets .~ [(self, action: #selector(self.followButtonTapped), .touchUpInside)]
      |> UIButton.lens.title(for: .normal) %~ { _ in Strings.social_following_friend_buttons_follow() }
  }

  @objc fileprivate func followButtonTapped() {
    self.viewModel.followButtonTapped()
  }
}
