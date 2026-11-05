import KDS
import KsApi
import Prelude
import UIKit

public enum PostCampaignRewardsSummaryItem {
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

public struct PostCampaignRewardsSummaryViewData {
  let rewards: [Reward]
  let selectedQuantities: SelectedRewardQuantities
  let currencyCode: String
  let omitCurrencyCode: Bool
  let shipping: PledgeShippingSummaryViewData?
  let useLatePledgeCosts: Bool
}

@MainActor
public final class PostCampaignPledgeRewardsSummaryViewModel {
  public var onRewards: ((PledgeSummaryRewardCellData?, [PledgeSummaryRewardCellData]) -> Void)?
  public var onPledgeTotal: ((PledgeSummaryViewData) -> Void)?
  private var configuration: (PostCampaignRewardsSummaryViewData, Double?, PledgeSummaryViewData)?
  private var loaded = false

  public init() {}

  public func configureWith(
    rewardsData: PostCampaignRewardsSummaryViewData,
    bonusAmount: Double?,
    pledgeData: PledgeSummaryViewData
  ) {
    self.configuration = (rewardsData, bonusAmount, pledgeData)
    self.publishIfReady()
  }

  public func viewDidLoad() {
    self.loaded = true
    self.publishIfReady()
  }

  private func publishIfReady() {
    guard self.loaded, let (data, bonus, pledge) = self.configuration else { return }
    let date = data.rewards.compactMap(\.estimatedDeliveryOn).max() ?? 0
    let delivery: String?
    if date > 0 {
      let formatted = Format.date(secondsInUTC: date, template: DateFormatter.monthYear, timeZone: UTCTimeZone)
      delivery = Strings.backing_info_estimated_delivery_date(delivery_date: formatted)
    } else {
      delivery = nil
    }
    let rows = items(with: data, selectedQuantities: data.selectedQuantities,
                     estimatedDeliveryString: delivery, bonusAmount: bonus)
    let header = rows.compactMap { item -> PledgeSummaryRewardCellData? in
      guard case let .header(value) = item else { return nil }
      return value
    }.first
    let rewards = rows.compactMap { item -> PledgeSummaryRewardCellData? in
      guard case let .reward(value) = item else { return nil }
      return value
    }
    self.onRewards?(header, rewards)
    self.onPledgeTotal?(pledge)
  }
}

// MARK: - Functions

@MainActor
private func items(
  with data: PostCampaignRewardsSummaryViewData,
  selectedQuantities: SelectedRewardQuantities,
  estimatedDeliveryString: String?,
  bonusAmount: Double?
) -> [PostCampaignRewardsSummaryItem] {
  // MARK: Header

  let headerItem = PostCampaignRewardsSummaryItem.header(.init(
    type: .header,
    headerText: nil,
    showHeader: false,
    text: estimatedDeliveryString ?? "",
    amount: NSAttributedString(string: "")
  ))

  // MARK: Rewards

  let rewardItems = data.rewards.compactMap { reward -> PostCampaignRewardsSummaryItem? in
    guard reward.isNoReward == false, let title = reward.title else { return nil }

    let quantity = selectedQuantities[reward.id] ?? 0
    let itemString = quantity > 1 ? "\(Format.wholeNumber(quantity)) x \(title)" : title

    let itemCost = data.useLatePledgeCosts ? reward.latePledgeAmount : reward.pledgeAmount
    let amount = quantity > 1 ? itemCost * Double(quantity) : itemCost
    let amountAttributedText = attributedRewardCurrency(
      with: data.currencyCode, amount: amount, omitUSCurrencyCode: data.omitCurrencyCode
    )

    return PostCampaignRewardsSummaryItem.reward(.init(
      type: .reward,
      headerText: nil,
      showHeader: false,
      text: itemString,
      amount: amountAttributedText
    ))
  }
  var items = [headerItem] + rewardItems

  // MARK: Shipping

  if let shipping = data.shipping, shipping.total > 0 {
    let shippingAmountAttributedText = attributedRewardCurrency(
      with: data.currencyCode, amount: shipping.total, omitUSCurrencyCode: data.omitCurrencyCode
    )

    let shippingItem = PostCampaignRewardsSummaryItem.reward(.init(
      type: .shipping,
      headerText: nil,
      showHeader: false,
      text: Strings.Shipping_to_country(country: shipping.locationName),
      amount: shippingAmountAttributedText
    ))

    items.append(shippingItem)
  }

  // MARK: Bonus

  if let bonus = bonusAmount, bonus > 0, rewardItems.isEmpty == false {
    let bonusAmountAttributedText = attributedRewardCurrency(
      with: data.currencyCode, amount: bonus, omitUSCurrencyCode: data.omitCurrencyCode
    )

    let bonusItem = PostCampaignRewardsSummaryItem.reward(.init(
      type: .bonusSupport,
      headerText: nil,
      showHeader: false,
      text: Strings.Bonus_support(),
      amount: bonusAmountAttributedText
    ))

    items.append(bonusItem)
  }

  return items
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
