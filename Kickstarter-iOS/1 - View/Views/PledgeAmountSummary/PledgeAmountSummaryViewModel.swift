import Foundation
import KsApi
import Prelude

public struct PledgeAmountSummaryViewData {
  public let bonusAmount: Double?
  public let bonusAmountHidden: Bool
  public let isNoReward: Bool
  public let locationName: String?
  public let omitUSCurrencyCode: Bool
  public let currencyCode: String
  public let pledgedOn: TimeInterval
  public let rewardMinimum: Double
  public let shippingAmount: Double?
  public let shippingAmountHidden: Bool
  public let rewardIsLocalPickup: Bool
}

@MainActor
public final class PledgeAmountSummaryViewModel {
  struct Display {
    let bonus: NSAttributedString?
    let bonusHidden: Bool
    let pledge: NSAttributedString?
    let shipping: NSAttributedString?
    let shippingHidden: Bool
    let location: String?
  }
  var onDisplay: ((Display) -> Void)?
  private var data: PledgeAmountSummaryViewData?
  private var loaded = false
  public init() {}

  public func configureWith(_ data: PledgeAmountSummaryViewData) {
    self.data = data
    if self.loaded { self.publish(data) }
  }
  public func viewDidLoad() {
    self.loaded = true
    if let data = self.data { self.publish(data) }
  }
  private func publish(_ data: PledgeAmountSummaryViewData) {
    self.onDisplay?(Display(
      bonus: plusSignAmount(with: data.currencyCode, amount: data.bonusAmount ?? 0, omitUSCurrencyCode: data.omitUSCurrencyCode),
      bonusHidden: data.isNoReward || data.bonusAmountHidden,
      pledge: pledgeAmountSummaryViewModelAttributedCurrency(
        with: data.currencyCode, amount: data.isNoReward ? (data.bonusAmount ?? 0) : data.rewardMinimum,
        omitUSCurrencyCode: data.omitUSCurrencyCode
      ),
      shipping: plusSignAmount(with: data.currencyCode, amount: data.shippingAmount ?? 0, omitUSCurrencyCode: data.omitUSCurrencyCode),
      shippingHidden: data.rewardIsLocalPickup || data.locationName == nil || data.shippingAmountHidden,
      location: data.locationName.map { Strings.Shipping_to_country(country: $0) }
    ))
  }
}

@MainActor
private func pledgeAmountSummaryViewModelAttributedCurrency(
  with currencyCode: String,
  amount: Double,
  omitUSCurrencyCode: Bool
) -> NSAttributedString? {
  let defaultAttributes = checkoutCurrencyDefaultAttributes()
  let superscriptAttributes = checkoutCurrencySuperscriptAttributes()
  guard
    let pledgeAmountSummaryViewModelAttributedCurrency = Format.attributedCurrency(
      amount,
      currencyCode: currencyCode,
      omitCurrencyCode: omitUSCurrencyCode,
      defaultAttributes: defaultAttributes,
      superscriptAttributes: superscriptAttributes
    ) else { return nil }

  return pledgeAmountSummaryViewModelAttributedCurrency
}

@MainActor
private func plusSignAmount(
  with currencyCode: String,
  amount: Double,
  omitUSCurrencyCode: Bool
) -> NSAttributedString? {
  let defaultAttributes = checkoutCurrencyDefaultAttributes()
  let superscriptAttributes = checkoutCurrencySuperscriptAttributes()
  guard
    let pledgeAmountSummaryViewModelAttributedCurrency = Format.attributedCurrency(
      amount,
      currencyCode: currencyCode,
      omitCurrencyCode: omitUSCurrencyCode,
      defaultAttributes: defaultAttributes,
      superscriptAttributes: superscriptAttributes
    ) else { return nil }

  let combinedAttributes = defaultAttributes.withAllValuesFrom(superscriptAttributes)

  return Format.attributedPlusSign(combinedAttributes) + pledgeAmountSummaryViewModelAttributedCurrency
}
