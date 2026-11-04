import KDS
import KsApi

import Prelude
import UIKit

internal final class FindFriendsFriendFollowCell: UITableViewCell, ValueCell {
  @IBOutlet fileprivate var avatarImageView: CircleAvatarImageView!
  @IBOutlet fileprivate var friendNameLabel: UILabel!
  @IBOutlet fileprivate var friendLocationLabel: UILabel!
  @IBOutlet fileprivate var projectsBackedLabel: UILabel!
  @IBOutlet fileprivate var projectsCreatedLabel: UILabel!
  @IBOutlet fileprivate var followButton: UIButton!
  @IBOutlet fileprivate var unfollowButton: UIButton!

  fileprivate let viewModel = FindFriendsFriendFollowCellViewModel()

  func configureWith(value: (friend: User, source: FriendsSource)) {
    self.viewModel.configureWith(friend: value.friend)
    self.renderState()
    self.avatarImageView.af.cancelImageRequest()
    self.avatarImageView.image = nil
    if let url = self.viewModel.imageURL { self.avatarImageView.ksr_setImageWithURL(url) }
  }

  override func bindViewModel() {
    super.bindViewModel()
    self.viewModel.onChange = { [weak self] in self?.renderState() }
  }

  private func renderState() {
    let model = self.viewModel
    self.accessibilityValue = model.cellAccessibilityValue
    if let value = model.enableFollowButton { self.followButton.isEnabled = value }
    if let value = model.enableUnfollowButton { self.unfollowButton.isEnabled = value }
    self.followButton.accessibilityLabel = model.followButtonAccessibilityLabel
    self.unfollowButton.accessibilityLabel = model.unfollowButtonAccessibilityLabel
    self.friendNameLabel.text = model.name
    self.friendLocationLabel.text = model.location
    self.projectsBackedLabel.text = model.projectsBackedText
    if let text = model.projectsCreatedText { self.projectsCreatedLabel.text = text }
    if let value = model.hideProjectsCreated { self.projectsCreatedLabel.isHidden = value }
    if let value = model.hideFollowButton { self.followButton.isHidden = value }
    if let value = model.hideUnfollowButton { self.unfollowButton.isHidden = value }
  }

  override func bindStyles() {
    super.bindStyles()

    _ = self.avatarImageView
      |> ignoresInvertColorsImageViewStyle

    _ = self.friendNameLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
      |> UILabel.lens.font .~ UIFont.ksr_headline(size: 14.0)

    _ = self.self.friendLocationLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UILabel.lens.font .~ .ksr_caption1()

    _ = self.projectsBackedLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UILabel.lens.font .~ .ksr_footnote()

    _ = self.projectsCreatedLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UILabel.lens.font .~ .ksr_footnote()

    self.followButton.applyStyleConfiguration(KSRButtonStyle.filled)

    _ = self.followButton
      |> UIButton.lens.targets .~ [(self, action: #selector(self.followButtonTapped), .touchUpInside)]
      |> UIButton.lens.title(for: .normal) %~ { _ in Strings.social_following_friend_buttons_follow() }

    self.unfollowButton.applyStyleConfiguration(KSRButtonLegacyStyle.grey)
    _ = self.unfollowButton
      |> UIButton.lens.targets .~ [(self, action: #selector(self.unfollowButtonTapped), .touchUpInside)]
      |> UIButton.lens.title(for: .normal) %~ { _ in
        Strings.social_following_friend_buttons_following()
      }

    _ = self
      |> baseTableViewCellStyle()
      |> UITableViewCell.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()
      |> UITableViewCell.lens.contentView.layoutMargins %~~ { _, cell in
        cell.traitCollection.isRegularRegular
          ? .init(topBottom: Styles.grid(2), leftRight: Styles.grid(20))
          : .init(all: Styles.grid(2))
      }
  }

  @objc func followButtonTapped() {
    self.viewModel.followButtonTapped()
  }

  @objc func unfollowButtonTapped() {
    self.viewModel.unfollowButtonTapped()
  }
}
