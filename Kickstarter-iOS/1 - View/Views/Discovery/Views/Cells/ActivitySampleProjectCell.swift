import KDS
import KsApi

import Prelude
import UIKit

@MainActor
internal protocol ActivitySampleProjectCellDelegate: AnyObject {
  /// Call when should go to activity screen.
  func goToActivity()
}

internal final class ActivitySampleProjectCell: UITableViewCell, ValueCell {
  fileprivate let viewModel = ActivitySampleProjectCellViewModel()
  internal weak var delegate: ActivitySampleProjectCellDelegate?

  @IBOutlet fileprivate var activityStackView: UIStackView!
  @IBOutlet fileprivate var activityTitleLabel: UILabel!
  @IBOutlet fileprivate var cardView: UIView!
  @IBOutlet fileprivate var projectImageAndInfoStackView: UIStackView!
  @IBOutlet fileprivate var projectImageView: UIImageView!
  @IBOutlet fileprivate var projectSubtitleAndTitleStackView: UIStackView!
  @IBOutlet fileprivate var projectSubtitleLabel: UILabel!
  @IBOutlet fileprivate var projectTitleLabel: UILabel!
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

    _ = self.activityTitleLabel
      |> activitySampleTitleLabelStyle

    _ = self.activityStackView
      |> activitySampleStackViewStyle

    _ = self.cardView
      |> dropShadowStyleMedium()

    self.cardView.backgroundColor = Colors.Background.Surface.primary.uiColor()

    _ = self.projectImageAndInfoStackView
      |> UIStackView.lens.spacing .~ Styles.grid(2)

    _ = self.projectSubtitleAndTitleStackView
      |> UIStackView.lens.spacing .~ Styles.gridHalf(1)

    _ = self.projectImageView
      |> ignoresInvertColorsImageViewStyle

    _ = self.projectSubtitleLabel
      |> activitySampleProjectSubtitleLabelStyle

    _ = self.projectTitleLabel
      |> activitySampleProjectTitleLabelStyle

    _ = self.seeAllActivityButton
      |> activitySampleSeeAllActivityButtonStyle
  }

  internal override func bindViewModel() {
    super.bindViewModel()
    self.viewModel.onGoToActivity = { [weak self] in self?.delegate?.goToActivity() }
  }

  internal func configureWith(value: Activity) {
    let display = self.viewModel.configureWith(activity: value)
    self.accessibilityHint = display.accessibilityHint
    self.projectSubtitleLabel.text = display.subtitle
    if let title = display.title { self.projectTitleLabel.text = title }
    self.projectImageView.af.cancelImageRequest()
    self.projectImageView.image = nil
    if let url = display.imageURL { self.projectImageView.ksr_setImageWithURL(url) }
  }

  @objc fileprivate func seeAllActivityButtonTapped() {
    self.viewModel.seeAllActivityTapped()
  }
}
