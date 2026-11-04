import Foundation
import KsApi
import Prelude

public struct PledgeShippingSummaryViewData: Equatable {
  public let locationName: String
  public let omitUSCurrencyCode: Bool
  public let currencyCode: String
  public let total: Double
}

@MainActor
struct PledgeShippingSummaryPresentation {
  let location: String
  let amount: NSAttributedString?

  init(data: PledgeShippingSummaryViewData) {
    self.location = data.locationName
    self.amount = pledgeShippingSummaryViewModelAttributedCurrency(
      with: data.currencyCode, omitCurrencyCode: data.omitUSCurrencyCode, total: data.total
    )
  }
}

@MainActor
private func pledgeShippingSummaryViewModelAttributedCurrency(
  with currencyCode: String,
  omitCurrencyCode: Bool,
  total: Double
) -> NSAttributedString? {
  let defaultAttributes = checkoutCurrencyDefaultAttributes()
  let superscriptAttributes = checkoutCurrencySuperscriptAttributes()
  guard
    let pledgeShippingSummaryViewModelAttributedCurrency = Format.attributedCurrency(
      total,
      currencyCode: currencyCode,
      omitCurrencyCode: omitCurrencyCode,
      defaultAttributes: defaultAttributes,
      superscriptAttributes: superscriptAttributes
    ) else { return nil }

  let combinedAttributes = defaultAttributes.withAllValuesFrom(superscriptAttributes)

  return Format.attributedPlusSign(combinedAttributes) + pledgeShippingSummaryViewModelAttributedCurrency
}
