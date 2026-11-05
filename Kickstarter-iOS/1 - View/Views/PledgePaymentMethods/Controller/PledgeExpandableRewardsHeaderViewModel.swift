import KDS
import KsApi
import Prelude
import UIKit

public enum PledgeExpandableRewardsHeaderItem {
  case header(PledgeSummaryRewardCellData)
  case reward(PledgeSummaryRewardCellData)

  public var data: PledgeSummaryRewardCellData {
    switch self {
    case let .header(data): return data
    case let .reward(data): return data
    }
  }

  public var isHeader: Bool {
    switch self {
    case .header: return true
    case .reward: return false
    }
  }

  public var isReward: Bool {
    switch self {
    case .header: return false
    case .reward: return true
    }
  }
}

public struct PledgeExpandableRewardsHeaderViewData {
  public let rewards: [Reward]
  public let selectedQuantities: SelectedRewardQuantities
  public let currencyCode: String
  public let omitCurrencyCode: Bool
}

@MainActor
public final class PledgeExpandableRewardsHeaderViewModel {
  public var onRewards: (([PledgeExpandableRewardsHeaderItem]) -> Void)?
  public var onExpansion: ((Bool) -> Void)?
  private var data: PledgeExpandableRewardsHeaderViewData?
  private var loaded = false
  private var expanded = false

  public init() {}

  public func configure(with data: PledgeExpandableRewardsHeaderViewData) {
    self.data = data
    self.publishRewardsIfReady()
  }

  public func viewDidLoad() {
    self.loaded = true
    self.publishRewardsIfReady()
  }

  public func expandButtonTapped() {
    self.expanded.toggle()
    self.onExpansion?(self.expanded)
  }

  private func publishRewardsIfReady() {
    guard self.loaded, let data = self.data else { return }
    let date = data.rewards.compactMap(\.estimatedDeliveryOn).max() ?? 0
    guard date > 0 else { return }
    let dateString = Format.date(secondsInUTC: date, template: DateFormatter.monthYear, timeZone: UTCTimeZone)
    let delivery = Strings.backing_info_estimated_delivery_date(delivery_date: dateString)
    let total = data.rewards.reduce(0.0) { total, reward in
      total.addingCurrency(reward.minimum.multiplyingCurrency(Double(data.selectedQuantities[reward.id] ?? 0)))
    }
    self.onRewards?(items(with: data, selectedQuantities: data.selectedQuantities, estimatedDeliveryString: delivery, total: total))
  }
}

// MARK: - Functions

@MainActor
private func items(
  with data: PledgeExpandableRewardsHeaderViewData,
  selectedQuantities: SelectedRewardQuantities,
  estimatedDeliveryString: String,
  total: Double
) -> [PledgeExpandableRewardsHeaderItem] {
  guard let totalAmountAttributedText = attributedHeaderCurrency(
    with: data.currencyCode, amount: total, omitUSCurrencyCode: data.omitCurrencyCode
  ) else { return [] }

  let headerItem = PledgeExpandableRewardsHeaderItem.header(.init(
    type: .header,
    headerText: nil,
    showHeader: true,
    text: estimatedDeliveryString,
    amount: totalAmountAttributedText
  ))

  let rewardItems = data.rewards.compactMap { reward -> PledgeExpandableRewardsHeaderItem? in
    guard let title = reward.title else { return nil }

    let quantity = selectedQuantities[reward.id] ?? 0
    let itemString = quantity > 1 ? "\(Format.wholeNumber(quantity)) x \(title)" : title

    let amount = quantity > 1 ? reward.minimum * Double(quantity) : reward.minimum
    let amountAttributedText = attributedRewardCurrency(
      with: data.currencyCode, amount: amount, omitUSCurrencyCode: data.omitCurrencyCode
    )

    return PledgeExpandableRewardsHeaderItem.reward(.init(
      type: .reward,
      headerText: nil,
      showHeader: true,
      text: itemString,
      amount: amountAttributedText
    ))
  }

  return [headerItem] + rewardItems
}

@MainActor
private func attributedHeaderCurrency(
  with currencyCode: String,
  amount: Double,
  omitUSCurrencyCode: Bool
) -> NSAttributedString? {
  let defaultAttributes = checkoutCurrencyDefaultAttributes()
    .withAllValuesFrom([.foregroundColor: LegacyColors.ksr_support_400.uiColor()])
  let superscriptAttributes = checkoutCurrencySuperscriptAttributes()
  guard
    let attributedCurrency = Format.attributedCurrency(
      amount,
      currencyCode: currencyCode,
      omitCurrencyCode: omitUSCurrencyCode,
      defaultAttributes: defaultAttributes,
      superscriptAttributes: superscriptAttributes,
      maximumFractionDigits: 0,
      minimumFractionDigits: 0
    ) else { return nil }

  return attributedCurrency
}

@MainActor
private func attributedRewardCurrency(
  with currencyCode: String,
  amount: Double,
  omitUSCurrencyCode: Bool
) -> NSAttributedString {
  let currencyString = Format.currency(
    amount,
    currencyCode: currencyCode,
    omitCurrencyCode: omitUSCurrencyCode,
    maximumFractionDigits: 0,
    minimumFractionDigits: 0
  )

  return NSAttributedString(
    string: currencyString,
    attributes: [
      .foregroundColor: LegacyColors.ksr_support_400.uiColor(),
      .font: UIFont.ksr_subhead().bolded
    ]
  )
}
