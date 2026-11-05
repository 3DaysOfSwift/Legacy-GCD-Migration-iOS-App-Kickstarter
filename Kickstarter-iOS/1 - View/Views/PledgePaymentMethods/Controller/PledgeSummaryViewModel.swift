import KDS
import KsApi
import Prelude
import UIKit

private enum Constants {
  public static let dateFormat = "MMMM d, yyyy"
}

public typealias PledgeSummaryViewData = (
  project: Project,
  total: Double,
  confirmationLabelHidden: Bool,
  pledgeHasNoReward: Bool?
)

@MainActor
public final class PledgeSummaryViewModel {
  public var onAmount: ((NSAttributedString) -> Void)?
  public var onConfirmation: ((NSAttributedString) -> Void)?
  public var onConfirmationHidden: ((Bool) -> Void)?
  public var onHelp: ((HelpType) -> Void)?
  public var onPlanHidden: ((Bool) -> Void)?
  public var onCharges: ((String) -> Void)?
  public var onConversion: ((String) -> Void)?
  public var onTitle: ((String) -> Void)?
  private var data: PledgeSummaryViewData?
  private var plan: PledgePaymentPlansAndSelectionData?
  private var hasPlanConfiguration = false
  private var loaded = false

  public init() {}

  public func configure(with data: PledgeSummaryViewData) {
    self.data = data
    guard self.loaded else { return }
    self.publishSummary(data)
    self.publishConfirmationIfReady()
  }

  public func configureWith(pledgeOverTimeData: PledgePaymentPlansAndSelectionData?) {
    self.plan = pledgeOverTimeData
    self.hasPlanConfiguration = true
    guard self.loaded else { return }
    self.publishPlan()
    self.publishConfirmationIfReady()
  }

  public func viewDidLoad() {
    self.loaded = true
    if let data = self.data { self.publishSummary(data) }
    if self.hasPlanConfiguration { self.publishPlan() }
    self.publishConfirmationIfReady()
  }

  public func tapped(_ url: URL) {
    let baseURL = AppEnvironment.current.apiService.serverConfig.webBaseUrl
    guard let type = HelpType.allCases.first(where: { url.absoluteString == $0.url(withBaseUrl: baseURL)?.absoluteString }) else { return }
    self.onHelp?(type)
  }

  private func publishSummary(_ data: PledgeSummaryViewData) {
    let project = data.project
    if let amount = pledgeSummaryViewModelAttributedCurrency(with: project, total: data.total) {
      self.onAmount?(amount)
    }
    if project.stats.needsConversion {
      let converted = data.total * Double(project.stats.userCurrencyRate ?? project.stats.staticUsdRate)
      let currency = project.stats.userCurrency ?? Project.Country.us.currencyCode
      let formatted = Format.currency(converted, currencyCode: currency, omitCurrencyCode: project.stats.omitUSCurrencyCode,
                                     roundingMode: .halfUp, maximumFractionDigits: 2, minimumFractionDigits: 2)
      self.onConversion?(Strings.About_reward_amount(reward_amount: formatted))
    }
    self.onTitle?(data.pledgeHasNoReward == true ? Strings.Pledge_without_a_reward() : Strings.Pledge_amount())
    self.onConfirmationHidden?(project.isInPostCampaignPledgingPhase || data.confirmationLabelHidden)
  }

  private func publishPlan() {
    self.onPlanHidden?(!(self.plan?.isPledgeOverTime ?? false))
    if let text = self.plan?.project.pledgeOverTimeCollectionPlanChargedAsNPayments { self.onCharges?(text) }
  }

  private func publishConfirmationIfReady() {
    guard self.hasPlanConfiguration, let data = self.data else { return }
    self.onConfirmation?(attributedConfirmationString(with: data, pledgeOverTimeData: self.plan))
  }
}

@MainActor
private func pledgeSummaryViewModelAttributedCurrency(with project: Project, total: Double) -> NSAttributedString? {
  let defaultAttributes = checkoutCurrencyDefaultAttributes()
    .withAllValuesFrom([.foregroundColor: LegacyColors.ksr_support_700.uiColor()])

  return Format.attributedCurrency(
    total,
    currencyCode: project.statsCurrency,
    omitCurrencyCode: project.stats.omitUSCurrencyCode,
    defaultAttributes: defaultAttributes,
    superscriptAttributes: checkoutCurrencySuperscriptAttributes()
  )
}

@MainActor
private func attributedConfirmationString(with project: Project, pledgeTotal: Double) -> NSAttributedString {
  var date = ""

  if let deadline = project.dates.deadline {
    date = Format.date(secondsInUTC: deadline, template: Constants.dateFormat)
  }

  let pledgeTotal = Format.currency(pledgeTotal, currencyCode: project.statsCurrency)

  let font = UIFont.ksr_caption1()
  let foregroundColor = LegacyColors.ksr_support_400.uiColor()

  return Strings
    .If_the_project_reaches_its_funding_goal_you_will_be_charged_total_on_project_deadline_and_receive_proof_of_pledge(
      total: pledgeTotal,
      project_deadline: date
    )
    .attributed(
      with: font, foregroundColor: foregroundColor, attributes: [:], bolding: [pledgeTotal, date]
    )
}

@MainActor
private func attributedConfirmationPledgeOverTimeString(
  with project: Project,
  increments: [PledgePaymentIncrement]
) -> NSAttributedString {
  guard let firstIncrement = increments.first else { return NSAttributedString() }

  let date = Format.date(secondsInUTC: firstIncrement.scheduledCollection, template: Constants.dateFormat)

  let projectCurrencyCountry = projectCountry(forCurrency: project.statsCurrency) ?? project.country
  let chargeAmount = firstIncrement.amount.amountFormattedInProjectNativeCurrency

  let font = UIFont.ksr_caption1()
  let foregroundColor = LegacyColors.ksr_support_400.uiColor()

  return Strings
    .If_the_project_reaches_its_funding_goal_the_first_charge_will_be_collected_on_project_deadline(
      amount: chargeAmount,
      project_deadline: date
    )
    .attributed(
      with: font, foregroundColor: foregroundColor, attributes: [:], bolding: [chargeAmount, date]
    )
}

@MainActor
private func attributedConfirmationString(
  with data: PledgeSummaryViewData,
  pledgeOverTimeData: PledgePaymentPlansAndSelectionData?
) -> NSAttributedString {
  if let plotData = pledgeOverTimeData, plotData.isPledgeOverTime {
    return attributedConfirmationPledgeOverTimeString(
      with: data.project,
      increments: plotData.paymentIncrements
    )
  }

  return attributedConfirmationString(with: data.project, pledgeTotal: data.total)
}
