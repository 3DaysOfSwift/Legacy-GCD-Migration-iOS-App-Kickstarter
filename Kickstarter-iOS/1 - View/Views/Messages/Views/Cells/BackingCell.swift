import KDS
import KsApi

import Prelude
import UIKit

@MainActor
internal protocol BackingCellDelegate: AnyObject {
  /// Call when should navigate to Backing Info.
  func backingCellGoToBackingInfo()
}

internal final class BackingCell: UITableViewCell, ValueCell {
  fileprivate let viewModel: BackingCellViewModel = BackingCellViewModel()

  @IBOutlet private var backingInfoButton: UIButton!
  @IBOutlet private var deliveryLabel: UILabel!
  @IBOutlet private var dividerView: UIView!
  @IBOutlet private var pledgedLabel: UILabel!
  @IBOutlet private var rewardLabel: UILabel!
  @IBOutlet private var rootStackView: UIStackView!

  internal weak var delegate: BackingCellDelegate?

  internal override func awakeFromNib() {
    super.awakeFromNib()
    // UIKit loads this view on the main thread; NSObject declares this hook nonisolated.
    MainActor.assumeIsolated {
      self.backingInfoButton.addTarget(
        self, action: #selector(self.backingInfoButtonTapped),
        for: .touchUpInside
      )
    }
  }

  internal func configureWith(value: (backing: Backing, project: Project, isFromBacking: Bool)) {
    self.viewModel.configureWith(
      backing: value.backing,
      project: value.project,
      isFromBacking: value.isFromBacking
    )
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseTableViewCellStyle()
      |> BackingCell.lens.contentView.layoutMargins %~~ { _, cell in
        cell.traitCollection.isRegularRegular
          ? .init(topBottom: Styles.grid(6), leftRight: Styles.grid(16))
          : .init(topBottom: Styles.grid(3), leftRight: Styles.grid(2))
      }

    self.backingInfoButton.applyStyleConfiguration(KSRButtonLegacyStyle.grey)
    _ = self.backingInfoButton
      |> UIButton.lens.title(for: .normal) %~ { _ in Strings.backing_info_info_button() }
      |> UIButton.lens.contentEdgeInsets %~~ { _, button in
        button.traitCollection.isRegularRegular
          ? .init(topBottom: Styles.grid(2), leftRight: Styles.grid(3))
          : .init(topBottom: Styles.gridHalf(3), leftRight: Styles.gridHalf(5))
      }

    _ = self.deliveryLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UILabel.lens.font .~ UIFont.ksr_caption1()

    _ = self.dividerView
      |> separatorStyle

    _ = self.pledgedLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
      |> UILabel.lens.font .~ UIFont.ksr_headline()

    _ = self.rewardLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UILabel.lens.font .~ .ksr_subhead()
  }

  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onDisplay = { [weak self] display in
      self?.backingInfoButton.isHidden = display.isBackingInfoHidden
      self?.pledgedLabel.text = display.pledged
      self?.rewardLabel.text = display.reward
      self?.deliveryLabel.text = display.delivery
      self?.rootStackView.alignment = display.alignment
    }
  }

  @objc private func backingInfoButtonTapped() {
    self.delegate?.backingCellGoToBackingInfo()
  }
}
