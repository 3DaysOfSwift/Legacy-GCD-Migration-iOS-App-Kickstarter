import Foundation
import KsApi
import Prelude
import ReactiveSwift

public struct PledgeShippingSummaryViewData: Equatable {
  public let locationName: String
  public let omitUSCurrencyCode: Bool
  public let currencyCode: String
  public let total: Double
}

@MainActor
public protocol PledgeShippingSummaryViewModelInputs {
  func configure(with data: PledgeShippingSummaryViewData)
}

@MainActor
public protocol PledgeShippingSummaryViewModelOutputs {
  var amountLabelAttributedText: Signal<NSAttributedString, Never> { get }
  var locationLabelText: Signal<String, Never> { get }
}

@MainActor
public protocol PledgeShippingSummaryViewModelType {
  var inputs: PledgeShippingSummaryViewModelInputs { get }
  var outputs: PledgeShippingSummaryViewModelOutputs { get }
}

@MainActor
public class PledgeShippingSummaryViewModel: PledgeShippingSummaryViewModelType,
  PledgeShippingSummaryViewModelInputs, PledgeShippingSummaryViewModelOutputs {
  public init() {
    let configData = self.configureWithDataProperty.signal.skipNil()

    self.locationLabelText = configData.map(\.locationName)

    self.amountLabelAttributedText = configData.map {
      data in (data.currencyCode, data.omitUSCurrencyCode, data.total)
    }
    .map(pledgeShippingSummaryViewModelAttributedCurrency)
    .skipNil()
  }

  private let configureWithDataProperty = MutableProperty<PledgeShippingSummaryViewData?>(nil)
  public func configure(with data: PledgeShippingSummaryViewData) {
    self.configureWithDataProperty.value = data
  }

  public let amountLabelAttributedText: Signal<NSAttributedString, Never>
  public let locationLabelText: Signal<String, Never>

  public var inputs: PledgeShippingSummaryViewModelInputs { return self }
  public var outputs: PledgeShippingSummaryViewModelOutputs { return self }
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
