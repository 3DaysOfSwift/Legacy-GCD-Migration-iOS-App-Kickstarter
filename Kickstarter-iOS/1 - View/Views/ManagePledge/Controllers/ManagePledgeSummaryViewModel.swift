import KDS
import KsApi
import Prelude
import Observation
import UIKit

public struct ManagePledgeSummaryViewData: Equatable {
  public let backerId: Int
  public let backerName: String
  public let backerSequence: Int
  public let backingState: Backing.Status
  public let bonusAmount: Double?
  public let currentUserIsCreatorOfProject: Bool
  public let isNoReward: Bool
  public let locationName: String?
  public let needsConversion: Bool
  public let omitUSCurrencyCode: Bool
  public let pledgeAmount: Double
  public let pledgedOn: TimeInterval
  public let currencyCode: String
  public let projectDeadline: TimeInterval
  public let projectState: Project.State
  public let rewardMinimum: Double
  public let rewardReceivedViewControllerViewIsHidden: Bool
  public let rewardReceivedWithData: ManageViewPledgeRewardReceivedViewData
  public let shippingAmount: Double?
  public let shippingAmountHidden: Bool
  public let rewardIsLocalPickup: Bool
  public let paymentIncrements: [PledgePaymentIncrement]?
  // Temporary property
  public let project: Project?
}

@MainActor @Observable
public final class ManagePledgeSummaryViewModel {
  public init() {}
  public private(set) var data: ManagePledgeSummaryViewData?
  public private(set) var backerNameLabelHidden: Bool?
  public private(set) var backerNameText: String?
  public private(set) var backerImageURLAndPlaceholderImageName: (URL, String)?
  public private(set) var backerNumberText: String?
  public private(set) var backingDateText: String?
  public private(set) var totalAmountText: NSAttributedString?
  public private(set) var configurePledgeAmountSummaryViewWithData: PledgeAmountSummaryViewData?
  public private(set) var configurePledgeStatusLabelViewWithProject: PledgeStatusLabelViewData?
  private var pending: ManagePledgeSummaryViewData?
  private var loaded = false

  public func configureWith(_ data: ManagePledgeSummaryViewData) {
    self.pending = data
    if self.loaded { self.apply(data) }
  }

  public func viewDidLoad() {
    self.loaded = true
    if let pending = self.pending { self.apply(pending) }
  }

  private func apply(_ data: ManagePledgeSummaryViewData) {
    self.data = data
    self.configurePledgeStatusLabelViewWithProject = pledgeStatusLabelViewData(with: data)
    self.configurePledgeAmountSummaryViewWithData = pledgeAmountSummaryViewData(with: data)
    if let user = AppEnvironment.current.currentUser {
      let isBacker = data.backerId == user.id
      self.backerNameLabelHidden = !isBacker
      if isBacker {
        self.backerNameText = user.name
        if let url = URL(string: user.avatar.small) { self.backerImageURLAndPlaceholderImageName = (url, "avatar--placeholder") }
      }
    }
    self.backerNumberText = Strings.backer_modal_backer_number(backer_number: Format.wholeNumber(data.backerSequence))
    self.backingDateText = formattedPledgeDate(data.pledgedOn)
    if let amount = managePledgeSummaryViewModelAttributedCurrency(with: data.currencyCode, amount: data.pledgeAmount, omitUSCurrencyCode: data.omitUSCurrencyCode) {
      self.totalAmountText = amount
    }
  }
}

@MainActor
private func formattedPledgeDate(_ timeInterval: TimeInterval) -> String {
  let formattedDate = Format.date(secondsInUTC: timeInterval, dateStyle: .long, timeStyle: .none)
  return Strings.As_of_pledge_date(pledge_date: formattedDate)
}

private func pledgeAmountSummaryViewData(
  with data: ManagePledgeSummaryViewData
) -> PledgeAmountSummaryViewData {
  return .init(
    bonusAmount: data.bonusAmount,
    bonusAmountHidden: false,
    isNoReward: data.isNoReward,
    locationName: data.locationName,
    omitUSCurrencyCode: data.omitUSCurrencyCode,
    currencyCode: data.currencyCode,
    pledgedOn: data.pledgedOn,
    rewardMinimum: data.rewardMinimum,
    shippingAmount: data.shippingAmount,
    shippingAmountHidden: data.shippingAmountHidden,
    rewardIsLocalPickup: data.rewardIsLocalPickup
  )
}

private func pledgeStatusLabelViewData(with data: ManagePledgeSummaryViewData) -> PledgeStatusLabelViewData {
  return PledgeStatusLabelViewData(
    currentUserIsCreatorOfProject: data.currentUserIsCreatorOfProject,
    needsConversion: data.needsConversion,
    pledgeAmount: data.pledgeAmount,
    currencyCode: data.currencyCode,
    projectDeadline: data.projectDeadline,
    projectState: data.projectState,
    backingState: data.backingState,
    paymentIncrements: data.paymentIncrements,
    project: data.project
  )
}

@MainActor
private func managePledgeSummaryViewModelAttributedCurrency(
  with currencyCode: String,
  amount: Double,
  omitUSCurrencyCode: Bool
) -> NSAttributedString? {
  let defaultAttributes = checkoutCurrencyDefaultAttributes()
    .withAllValuesFrom([.foregroundColor: LegacyColors.ksr_support_700.uiColor()])
  let superscriptAttributes = checkoutCurrencySuperscriptAttributes()
  guard
    let managePledgeSummaryViewModelAttributedCurrency = Format.attributedCurrency(
      amount,
      currencyCode: currencyCode,
      omitCurrencyCode: omitUSCurrencyCode,
      defaultAttributes: defaultAttributes,
      superscriptAttributes: superscriptAttributes
    ) else { return nil }

  return managePledgeSummaryViewModelAttributedCurrency
}
