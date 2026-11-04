import KDS
import KsApi

import Prelude
import UIKit

@MainActor
internal protocol ActivitySampleBackingCellDelegate: AnyObject {
  /// Call when should go to activity screen.
  func goToActivity()
}

internal final class ActivitySampleBackingCell: UITableViewCell, ValueCell {
  fileprivate let viewModel = ActivitySampleBackingCellViewModel()
  internal weak var delegate: ActivitySampleBackingCellDelegate?

  @IBOutlet fileprivate var activityStackView: UIStackView!
  @IBOutlet fileprivate var activityTitleLabel: UILabel!
  @IBOutlet fileprivate var backerImageAndInfoStackView: UIStackView!
  @IBOutlet fileprivate var backerImageView: CircleAvatarImageView!
  @IBOutlet fileprivate var backingTitleLabel: UILabel!
  @IBOutlet fileprivate var cardView: UIView!
  @IBOutlet fileprivate var seeAllActivityButton: UIButton!

  internal override func awakeFromNib() {
    super.awakeFromNib()
    // UIKit loads this view on the main thread; NSObject declares this hook nonisolated.
    MainActor.assumeIsolated {
      self.seeAllActivityButton.addTarget(
        self,
        action: #selector(self.seeAllActivityButtonTapped),
        for: .touchUpInside
      )
    }
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> activitySampleCellStyle
      |> \.backgroundColor .~ discoveryPageBackgroundColor()
      |> UITableViewCell.lens.accessibilityHint %~ { _ in
        Strings.dashboard_tout_accessibility_hint_opens_project()
      }

    self.cardView.backgroundColor = Colors.Background.Surface.primary.uiColor()

    _ = self.activityStackView
      |> activitySampleStackViewStyle

    _ = self.activityTitleLabel
      |> activitySampleTitleLabelStyle

    _ = self.backerImageAndInfoStackView
      |> UIStackView.lens.spacing .~ Styles.grid(2)

    _ = self.backerImageView
      |> ignoresInvertColorsImageViewStyle

    _ = self.backingTitleLabel
      |> activitySampleBackingTitleLabelStyle

    _ = self.cardView
      |> dropShadowStyleMedium()

    _ = self.seeAllActivityButton
      |> activitySampleSeeAllActivityButtonStyle
  }

  internal override func bindViewModel() {
    super.bindViewModel()
    self.viewModel.onGoToActivity = { [weak self] in self?.delegate?.goToActivity() }
  }

  internal func configureWith(value: Activity) {
    let display = self.viewModel.configureWith(activity: value)
    self.backingTitleLabel.attributedText = display.title
    self.backerImageView.af.cancelImageRequest()
    self.backerImageView.image = nil
    if let url = display.imageURL { self.backerImageView.ksr_setImageWithURL(url) }
  }

  @objc fileprivate func seeAllActivityButtonTapped() {
    self.viewModel.seeAllActivityTapped()
  }
}
