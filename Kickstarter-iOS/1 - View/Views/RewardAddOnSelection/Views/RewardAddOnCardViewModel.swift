import KDS
import KsApi
import Prelude
import UIKit

public struct RewardAddOnCardViewData: Equatable {
  public let project: Project
  public let reward: Reward
  public let context: RewardCardViewContext
  public let shippingRule: ShippingRule?
  public let selectedQuantities: SelectedRewardQuantities
}

@MainActor
public final class RewardAddOnCardViewModel {
  public struct Display {
    let conversionHidden: Bool
    let conversion: String?
    let amount: NSAttributedString
    let description: String
    let title: String?
    let includedItems: NSAttributedString?
    let includedItemsHidden: Bool
    let shipping: String?
    let shippingHidden: Bool
    let pills: [String]
    let pickup: String?
    let pickupHidden: Bool
    let maximum: Double
    let image: Reward.Image?
  }
  public var onDisplay: ((Display) -> Void)?
  public init() {}

  public var onQuantity: ((Int) -> Void)?
  public var onQuantitySelected: ((Int, Int) -> Void)?
  public var onSelectionFeedback: (() -> Void)?
  public var onWarningFeedback: (() -> Void)?
  private var currentData: RewardAddOnCardViewData?

  public func addButtonTapped() { self.updateQuantity(1) }

  public func configure(with data: RewardAddOnCardViewData) {
    self.currentData = data
    let project = data.project
    let reward = data.reward
    let rule = data.shippingRule
    let conversion: String?
    if needsConversion(project: project) {
      let amount = reward.minimum.addingCurrency(rule?.cost ?? 0)
        .multiplyingCurrency(Double(project.stats.userCurrencyRate ?? project.stats.staticUsdRate))
      let currency = project.stats.userCurrency ?? Project.Country.us.currencyCode
      let formatted = Format.currency(amount, currencyCode: currency,
                                      omitCurrencyCode: project.stats.omitUSCurrencyCode, roundingMode: .up)
      conversion = Strings.About_reward_amount(reward_amount: formatted)
    } else {
      conversion = nil
    }
    if reward.rewardsItems == nil { assertionFailure("Expected reward items to be fetched.") }
    let rewardItems = reward.rewardsItems ?? []
    let shipping = rule.flatMap { estimatedShippingText(for: [reward], project: project, locationId: $0.location.id) }
    self.onDisplay?(Display(
      conversionHidden: !needsConversion(project: project), conversion: conversion,
      amount: amountStringForReward(project: project, reward: reward, shippingRule: rule),
      description: reward.description, title: reward.title,
      includedItems: itemsLabelAttributedText(rewardItems), includedItemsHidden: rewardItems.isEmpty,
      shipping: shipping, shippingHidden: !reward.shipping.enabled || shipping == nil,
      pills: pillValues(project: project, reward: reward), pickup: reward.localPickup?.displayableName,
      pickupHidden: !isRewardLocalPickup(reward),
      maximum: Double(rewardLimitPerBackerRemainingForBacker(project: project, reward: reward) ?? 0),
      image: reward.image
    ))
    self.onQuantity?(data.selectedQuantities[data.reward.id] ?? 0)
  }

  public func stepperValueChanged(_ value: Double) { self.updateQuantity(Int(value)) }

  private func updateQuantity(_ quantity: Int) {
    self.onQuantity?(quantity)
    guard let data = self.currentData else { return }
    self.onQuantitySelected?(quantity, data.reward.id)
    let maxValue = Double(rewardLimitPerBackerRemainingForBacker(project: data.project, reward: data.reward) ?? 0)
    let value = Double(quantity)
    if value > 0 && value < maxValue { self.onSelectionFeedback?() }
    if value == 0 || value >= maxValue { self.onWarningFeedback?() }
  }


}

// MARK: - Functions

@MainActor
private func amountStringForReward(
  project: Project,
  reward: Reward,
  shippingRule: ShippingRule?
) -> NSAttributedString {
  let font: UIFont = UIFont.ksr_subhead().weighted(.medium)
  let foregroundColor: UIColor = LegacyColors.ksr_create_700.uiColor()

  let projectCurrency = project.statsCurrency

  let min = minPledgeAmount(forProject: project, reward: reward)
  let amountString = Format.currency(
    min,
    currencyCode: projectCurrency,
    omitCurrencyCode: project.stats.omitUSCurrencyCode
  )

  if let shippingRule = shippingRule, shippingRule.cost > 0 {
    let shippingAmount = Format.currency(
      shippingRule.cost,
      currencyCode: projectCurrency,
      omitCurrencyCode: project.stats.omitUSCurrencyCode
    )

    let combinedString = Strings.reward_amount_plus_shipping_cost_each(
      reward_amount: amountString,
      shipping_cost: shippingAmount
    )

    let attributedString = combinedString.attributed(
      with: UIFont.ksr_footnote().weighted(.medium),
      foregroundColor: foregroundColor,
      attributes: [:],
      bolding: []
    )

    let mutableString = NSMutableAttributedString(attributedString: attributedString)
    let amountRange = (combinedString as NSString).localizedStandardRange(of: amountString)

    mutableString.setAttributes([.font: font], range: amountRange)

    return mutableString
  }

  return amountString.attributed(
    with: font,
    foregroundColor: foregroundColor,
    attributes: [:],
    bolding: []
  )
}

@MainActor
private func itemsLabelAttributedText(_ items: [RewardsItem]) -> NSAttributedString? {
  guard !items.isEmpty else { return nil }

  let defaultAttributes: [NSAttributedString.Key: Any] = [
    .font: UIFont.ksr_callout()
  ]
  let bulletPrefix = "•  "

  let paragraphStyle = NSMutableParagraphStyle()
  paragraphStyle.headIndent = (bulletPrefix as NSString).size(withAttributes: defaultAttributes).width
  paragraphStyle.paragraphSpacing = Styles.grid(1)

  let bulletedListAttributes: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraphStyle]

  let attributedString = NSMutableAttributedString()

  items.map { rewardsItem -> NSAttributedString in
    let itemString = rewardsItem.quantity > 1
      ? "\(Format.wholeNumber(rewardsItem.quantity)) x \(rewardsItem.item.name)"
      : rewardsItem.item.name

    let suffix = rewardsItem.item.id == items.last?.item.id ? "" : "\n"

    return NSAttributedString(
      string: "\(bulletPrefix)\(itemString)\(suffix)",
      attributes: defaultAttributes.withAllValuesFrom(bulletedListAttributes)
    )
  }
  .forEach { bulletItem in attributedString.append(bulletItem) }

  return attributedString
}

private func needsConversion(project: Project) -> Bool {
  return project.stats.needsConversion
}

@MainActor
private func pillValues(project: Project, reward: Reward) -> [String] {
  return [
    timeLeftString(project: project, reward: reward),
    remainingString(project: project, reward: reward),
    limitPerBackerString(project: project, reward: reward)
  ]
  .compact()
}

@MainActor
private func timeLeftString(project: Project, reward: Reward) -> String? {
  let isUnlimitedOrAvailable = reward.limit == nil || reward.remaining ?? 0 > 0

  if let endsAt = reward.endsAt,
     let deadline = project.dates.deadline,
     endsAt > 0,
     endsAt >= AppEnvironment.current.dateType.init().timeIntervalSince1970,
     isUnlimitedOrAvailable {
    let (time, unit) = Format.duration(
      secondsInUTC: min(endsAt, deadline),
      abbreviate: true,
      useToGo: false
    )

    return Strings.Time_left_left(time_left: time + " " + unit)
  }

  return nil
}

private func limitPerBackerString(project: Project, reward: Reward) -> String? {
  guard
    let limitPerBacker = rewardLimitPerBackerRemainingForBacker(project: project, reward: reward),
    limitPerBacker > 0
  else { return nil }

  return Strings.limit_limit_per_backer(limit_per_backer: "\(limitPerBacker)")
}

private func remainingString(project: Project, reward: Reward) -> String? {
  guard
    let limit = reward.limit,
    let remaining = rewardLimitRemainingForBacker(project: project, reward: reward),
    remaining > 0
  else { return nil }

  return Strings.remaining_count_left_of_limit_count(
    remaining_count: "\(remaining)",
    limit_count: "\(limit)"
  )
}
