import KDS
import KsApi

import Prelude
import UIKit

internal final class MessageThreadCell: UITableViewCell, ValueCell {
  private let viewModel = MessageThreadCellViewModel()

  @IBOutlet private var avatarImageView: UIImageView!
  @IBOutlet private var bodyLabel: UILabel!
  @IBOutlet private var dateLabel: UILabel!
  @IBOutlet private var dividerView: UIView!
  @IBOutlet private var nameLabel: UILabel!
  @IBOutlet private var projectNameLabel: UILabel!
  @IBOutlet private var replyIndicator: UIView!
  @IBOutlet private var unreadIndicatorView: UIView!

  func configureWith(value: MessageThread) {
    let state = self.viewModel.configureWith(messageThread: value)
    self.avatarImageView.af.cancelImageRequest()
    self.avatarImageView.image = nil
    if let url = state.participantAvatarURL { self.avatarImageView.af.setImage(withURL: url) }
    self.nameLabel.setHTML(state.participantName)
    self.replyIndicator?.isHidden = state.replyIndicatorHidden
    self.projectNameLabel.text = state.projectName
    self.dateLabel.text = state.date
    self.dateLabel.accessibilityLabel = state.dateAccessibilityLabel
    self.unreadIndicatorView?.isHidden = state.unreadIndicatorHidden
    self.bodyLabel.text = state.messageBody
  }

  override func setSelected(_ selected: Bool, animated: Bool) {
    super.setSelected(selected, animated: animated)

    self.viewModel.setSelected(selected)
    if selected { self.unreadIndicatorView?.isHidden = true }
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseTableViewCellStyle()
      |> MessageThreadCell.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()
      |> MessageThreadCell.lens.contentView.layoutMargins %~~ { _, cell in
        cell.traitCollection.isRegularRegular
          ? .init(topBottom: Styles.grid(6), leftRight: Styles.grid(16))
          : .init(topBottom: Styles.grid(3), leftRight: Styles.grid(2))
      }

    _ = self.avatarImageView
      |> ignoresInvertColorsImageViewStyle

    _ = self.bodyLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UILabel.lens.font .~ UIFont.ksr_subhead(size: 14.0)

    _ = self.dateLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
      |> UILabel.lens.font .~ .ksr_caption1()

    _ = self.dividerView
      |> separatorStyle

    _ = self.nameLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
      |> UILabel.lens.font .~ UIFont.ksr_headline(size: 13.0)

    _ = self.projectNameLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UILabel.lens.font .~ UIFont.ksr_subhead(size: 15.0)
  }

}
