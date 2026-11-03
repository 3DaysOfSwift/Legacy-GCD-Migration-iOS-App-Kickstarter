import KDS
import Prelude
import Prelude_UIKit
import UIKit

@MainActor
public let activitySampleBackingTitleLabelStyle =
  UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
    <> UILabel.lens.numberOfLines .~ 2
    <> UILabel.lens.lineBreakMode .~ .byTruncatingTail

@MainActor
public let activitySampleCellStyle: (UITableViewCell) -> UITableViewCell = { cell in
  cell |> baseTableViewCellStyle()
    |> UITableViewCell.lens.backgroundColor .~ .clear
    |> UITableViewCell.lens.contentView.layoutMargins %~~ { _, view in
      view.traitCollection.isRegularRegular
        ? .init(top: Styles.grid(4), left: Styles.grid(30), bottom: Styles.grid(3), right: Styles.grid(30))
        : .init(top: Styles.grid(4), left: Styles.grid(2), bottom: Styles.grid(3), right: Styles.grid(2))
    }
}

@MainActor
public let activitySampleFriendFollowLabelStyle =
  UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
    <> UILabel.lens.numberOfLines .~ 2
    <> UILabel.lens.lineBreakMode .~ .byTruncatingTail
    <> UILabel.lens.font .~ .ksr_subhead()

@MainActor
public let activitySampleProjectSubtitleLabelStyle =
  UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
    <> UILabel.lens.numberOfLines .~ 2
    <> UILabel.lens.lineBreakMode .~ .byTruncatingTail
    <> UILabel.lens.font .~ .ksr_subhead()

@MainActor
public let activitySampleProjectTitleLabelStyle =
  UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
    <> UILabel.lens.numberOfLines .~ 2
    <> UILabel.lens.lineBreakMode .~ .byTruncatingTail
    <> UILabel.lens.font .~ UIFont.ksr_subhead().bolded

@MainActor
public let activitySampleSeeAllActivityButtonStyle: ButtonStyle = { button in
  button.applyStyleConfiguration(KSRButtonLegacyStyle.grey)
  button.setTitle(Strings.discovery_activity_sample_button_see_all_activity(), for: .normal)
  return button
}

@MainActor
public let activitySampleStackViewStyle =
  UIStackView.lens.spacing .~ Styles.grid(3)
    <> UIStackView.lens.layoutMargins .~ .init(all: Styles.grid(4))
    <> UIStackView.lens.isLayoutMarginsRelativeArrangement .~ true

@MainActor
public let activitySampleTitleLabelStyle =
  UILabel.lens.font .~ .ksr_footnote()
    <> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
    <> UILabel.lens.numberOfLines .~ 1
    <> UILabel.lens.lineBreakMode .~ .byTruncatingTail
    <> UILabel.lens.text %~ { _ in Strings.discovery_activity_sample_title_Since_your_last_visit() }
