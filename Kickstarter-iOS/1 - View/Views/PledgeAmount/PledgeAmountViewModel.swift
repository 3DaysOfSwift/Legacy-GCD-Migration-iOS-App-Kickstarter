import KDS
import KsApi
import Prelude
import UIKit

public typealias PledgeAmountData = (amount: Double, min: Double, max: Double, isValid: Bool)

public typealias PledgeAmountViewConfigData = (
  project: Project,
  reward: Reward,
  currentAmount: Double
)

public enum PledgeAmountStepperConstants {
  static let max: Double = 1_000_000_000
}

@MainActor
final class PledgeAmountViewModel {
  enum Event {
    case currency(String), valid(Bool), selectionFeedback, warningFeedback
    case color(UIColor), maxErrorHidden(Bool), maxErrorText(String), amount(PledgeAmountData)
    case noReward(Bool), stepperMax(Double), stepperMin(Double), stepperValue(Double)
    case endEditing, text(String), title(String)
  }
  var onEvent: ((Event) -> Void)?
  private var config: PledgeAmountViewConfigData?
  private var minimum: Double = 0
  private var baseMaximum: Double = 0
  private var unavailableAmount: Double = 0
  private var hasUnavailableAmount = false
  private var value: Double = 0
  private var previousValidity: Bool?
  private var previousStepperValue: Double?
  private var lastStepperInput: Double?
  private var previousMaxErrorText: String?

  func configureWith(data: PledgeAmountViewConfigData) {
    self.config = data
    let (minValue, maxValue) = minAndMaxPledgeAmount(forProject: data.project, reward: data.reward)
    self.minimum = data.reward.isNoReward ? minValue : 0
    self.baseMaximum = maxValue
    if !self.hasUnavailableAmount { self.unavailableAmount = 0 }
    self.value = initialPledgeAmount(from: data.project, currentAmount: data.currentAmount, minValue: self.minimum)
    self.onEvent?(.currency(currencySymbol(forCurrencyCode: data.project.stats.projectCurrency).trimmed()))
    self.onEvent?(.stepperMax(PledgeAmountStepperConstants.max))
    self.onEvent?(.noReward(data.reward.isNoReward))
    self.onEvent?(.title(data.reward.isNoReward ? Strings.Your_pledge_amount() : Strings.Bonus_support()))
    self.publishText()
    self.publishAmount()
  }

  func doneButtonTapped() { self.onEvent?(.endEditing) }

  func stepperValueChanged(_ value: Double) {
    self.value = value
    self.publishText()
    self.publishAmount()
    self.lastStepperInput = value
    if self.config != nil { self.publishFeedback(for: value, minValue: min(self.minimum, value)) }
  }

  func textFieldDidEndEditing(_ value: String?) {
    guard let value, let number = Double(value) else { return }
    self.value = pledgeAmountViewModelRounded(number, places: 2)
    self.publishText()
    self.publishAmount()
  }

  func textFieldValueChanged(_ value: String?) {
    self.value = Double(value ?? "") ?? 0
    self.publishAmount()
  }

  func unavailableAmountChanged(to amount: Double) {
    self.hasUnavailableAmount = true
    self.unavailableAmount = amount
    self.publishAmount()
  }

  private func publishFeedback(for value: Double, minValue: Double) {
    self.onEvent?(minValue < value && value < PledgeAmountStepperConstants.max ? .selectionFeedback : .warningFeedback)
  }

  private func publishText() {
    let places = self.value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
    self.onEvent?(.text(String(format: "%.*f", places, self.value)))
  }

  private func publishAmount() {
    guard let config else { return }
    let maxValue = self.baseMaximum - self.unavailableAmount
    let valid = self.minimum <= self.value && self.value <= maxValue
    let rounded = pledgeAmountViewModelRounded(self.value, places: 2)
    let stepperMinimum = min(self.minimum, self.value)
    self.onEvent?(.stepperMin(stepperMinimum))
    // Preserve the previous stepper feedback when its dynamic minimum is recalculated.
    if let lastStepperInput { self.publishFeedback(for: lastStepperInput, minValue: stepperMinimum) }
    self.onEvent?(.amount((rounded, self.minimum, maxValue, valid)))
    self.onEvent?(.maxErrorHidden(self.value <= maxValue))
    let maxPledge = Format.currency(maxValue, currencyCode: config.project.statsCurrency, omitCurrencyCode: false)
    let errorText = Strings.Enter_an_amount_less_than_max_pledge(max_pledge: maxPledge)
    if self.previousMaxErrorText != errorText {
      self.previousMaxErrorText = errorText
      self.onEvent?(.maxErrorText(errorText))
    }
    if self.previousValidity != valid {
      self.previousValidity = valid
      self.onEvent?(.valid(valid))
      self.onEvent?(.color(valid ? LegacyColors.ksr_create_700.uiColor() : LegacyColors.ksr_alert.uiColor()))
    }
    if self.previousStepperValue != rounded {
      self.previousStepperValue = rounded
      self.onEvent?(.stepperValue(rounded))
    }
  }
}

// MARK: - Functions

private func initialPledgeAmount(
  from _: Project,
  currentAmount: Double,
  minValue: Double
) -> Double {
  return max(currentAmount, minValue)
}

/*
 A helper that assists in rounding a Double to a given number of decimal places
 NB: Do not use this for rounding elsewhere.
 */
private func pledgeAmountViewModelRounded(_ value: Double, places: Int) -> Double {
  let divisor = pow(10.0, Double(places))
  return (value * divisor).rounded() / divisor
}
