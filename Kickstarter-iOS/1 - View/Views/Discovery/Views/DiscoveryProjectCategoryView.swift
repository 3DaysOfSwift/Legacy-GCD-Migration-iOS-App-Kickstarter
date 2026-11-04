import KDS
import KsApi

import Prelude
import UIKit

internal final class DiscoveryProjectCategoryView: UIView, NibLoading {
  private let viewModel = DiscoveryProjectCategoryViewModel()

  @IBOutlet private var blurView: UIImageView!
  @IBOutlet private var categoryStackView: UIStackView!
  @IBOutlet private var categoryViewImageView: UIImageView!
  @IBOutlet private var categoryViewLabel: UILabel!

  public required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
  }

  internal func configureWith(name: String, imageNameString: String) {
    self.viewModel.configureWith(name: name, imageNameString: imageNameString)
    self.categoryViewLabel.text = self.viewModel.categoryNameText
    if let name = self.viewModel.categoryImageName { self.categoryViewImageView.image = image(named: name) }
  }

  override func bindStyles() {
    super.bindStyles()

    // There used to be a blur view behind the category icons -
    // but now it's white-on-white, so no longer visible.
    // Setting this constraint maintains the same height as the old image,
    // but without having side effects in dark mode.
    self.blurView.heightAnchor.constraint(equalToConstant: 28.0).isActive = true

    _ = self.categoryViewLabel
      |> postcardCategoryLabelStyle

    _ = self.categoryViewImageView
      |> \.tintColor .~ LegacyColors.ksr_support_300.uiColor()
  }

}
