import KDS
import KsApi

import UIKit

@MainActor
internal protocol ThanksCategoryCellDelegate: AnyObject {
  func thanksCategoryCell(_ cell: ThanksCategoryCell, didTapSeeAllProjectsWith category: KsApi.Category)
}

internal final class ThanksCategoryCell: UITableViewCell, ValueCell {
  internal weak var delegate: ThanksCategoryCellDelegate?
  fileprivate let viewModel = ThanksCategoryCellViewModel()

  @IBOutlet fileprivate var seeAllProjectsButton: UIButton!

  override func awakeFromNib() {
    super.awakeFromNib()
    // UIKit loads this view on the main thread; NSObject declares this hook nonisolated.
    MainActor.assumeIsolated {
      self.seeAllProjectsButton
        .addTarget(self, action: #selector(self.seeAllProjectsButtonTapped), for: .touchUpInside)
    }
  }

  func configureWith(value category: KsApi.Category) {
    self.seeAllProjectsButton.setTitle(self.viewModel.configureWith(category: category), for: .normal)
  }

  internal override func bindStyles() {
    super.bindStyles()

    self.seeAllProjectsButton.applyStyleConfiguration(KSRButtonLegacyStyle.grey)
  }

  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onGoToDiscovery = { [weak self] category in
      guard let self else { return }
      self.delegate?.thanksCategoryCell(self, didTapSeeAllProjectsWith: category)
    }
  }

  @objc fileprivate func seeAllProjectsButtonTapped() {
    self.viewModel.seeAllProjectsButtonTapped()
  }
}
