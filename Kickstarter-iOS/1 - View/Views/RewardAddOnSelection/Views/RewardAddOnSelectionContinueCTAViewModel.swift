import Foundation
import KsApi

public typealias RewardAddOnSelectionContinueCTAViewData = (
  selectedQuantity: Int,
  isValid: Bool,
  isLoading: Bool,
  pledgeAmount: NSAttributedString? // Only shows pledge amount section if this is set.
)

struct RewardAddOnSelectionContinueCTAState {
  let buttonEnabled: Bool
  let buttonTitle: String
  let isLoading: Bool
  let pledgeAmount: NSAttributedString?

  init(data: RewardAddOnSelectionContinueCTAViewData) {
    self.buttonEnabled = data.isValid
    self.buttonTitle = data.selectedQuantity > 0
      ? Strings.Continue_with_quantity_count_add_ons(quantity_count: data.selectedQuantity)
      : Strings.Continue()
    self.isLoading = data.isLoading
    self.pledgeAmount = data.pledgeAmount
  }
}
