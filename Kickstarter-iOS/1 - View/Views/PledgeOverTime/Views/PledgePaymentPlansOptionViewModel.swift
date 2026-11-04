import Foundation
import KsApi

public struct PledgePaymentPlanOptionData: Equatable {
  public var ineligible: Bool = false
  public var type: PledgePaymentPlansType
  public var selectedType: PledgePaymentPlansType
  // TODO: replece with API model in [MBL-1838](https://kickstarter.atlassian.net/browse/MBL-1838)
  public var paymentIncrements: [PledgePaymentIncrement]
  public var project: Project

  public init(
    ineligible: Bool,
    type: PledgePaymentPlansType,
    selectedType: PledgePaymentPlansType,
    paymentIncrements: [PledgePaymentIncrement],
    project: Project
  ) {
    self.ineligible = ineligible
    self.type = type
    self.selectedType = selectedType
    self.paymentIncrements = paymentIncrements
    self.project = project
  }
}

public enum SelectionIndicatorImageName: String {
  case selected = "icon-payment-method-selected"
  case unselected = "icon-payment-method-unselected"
}

@MainActor
public final class PledgePaymentPlansOptionViewModel {
  struct Display {
    let title: String
    let subtitle: String
    let subtitleHidden: Bool
    let selectionImage: String
    let ineligibleHidden: Bool
    let ineligibleText: String?
    let enabled: Bool
    let increments: [PledgePaymentIncrementFormatted]?
    let plotHidden: Bool
  }
  private var data: PledgePaymentPlanOptionData?
  private var didProvideIncrements = false
  var onSelected: ((PledgePaymentPlansType) -> Void)?
  var onTerms: ((HelpType) -> Void)?
  public init() {}

  func configureWith(data: PledgePaymentPlanOptionData) -> Display {
    self.data = data
    return self.display(data)
  }

  func refreshSelectedType(_ type: PledgePaymentPlansType) -> Display? {
    guard var data = self.data else { return nil }
    data.selectedType = type
    self.data = data
    return self.display(data)
  }

  func optionTapped() { if let data = self.data { self.onSelected?(data.type) } }
  func termsOfUseTapped() { self.onTerms?(.terms) }

  private func display(_ data: PledgePaymentPlanOptionData) -> Display {
    let ineligible = data.type == .pledgeOverTime && data.ineligible
    let selected = data.selectedType == data.type
    let subtitle = getSubtitleText(by: data.type, isSelected: selected, project: data.project)
    var increments: [PledgePaymentIncrementFormatted]?
    if !self.didProvideIncrements, !data.ineligible, data.type == .pledgeOverTime, selected {
      let values = data.paymentIncrements.enumerated().map { PledgePaymentIncrementFormatted(from: $1, index: $0) }
      if !values.isEmpty { increments = values; self.didProvideIncrements = true }
    }
    return Display(
      title: getTitleText(by: data.type), subtitle: subtitle, subtitleHidden: ineligible || subtitle.isEmpty,
      selectionImage: selected ? SelectionIndicatorImageName.selected.rawValue : SelectionIndicatorImageName.unselected.rawValue,
      ineligibleHidden: !ineligible, ineligibleText: ineligible ? data.project.pledgeOverTimeMinimumExplanation : nil,
      enabled: !ineligible, increments: increments, plotHidden: !(data.type == .pledgeOverTime && selected)
    )
  }
}

private func getTitleText(by type: PledgePaymentPlansType) -> String {
  switch type {
  case .pledgeInFull: Strings.Pledge_in_full()
  case .pledgeOverTime: Strings.Pledge_Over_Time()
  }
}

private func getSubtitleText(by type: PledgePaymentPlansType, isSelected: Bool, project: Project) -> String {
  switch type {
  case .pledgeInFull:
    return ""
  case .pledgeOverTime:
    return makePledgeOverTimeSubtitle(isSelected: isSelected, project: project)
  }
}

private func makePledgeOverTimeSubtitle(isSelected: Bool, project: Project) -> String {
  guard let subtitle = project.pledgeOverTimeCollectionPlanShortPitch else {
    return ""
  }

  guard isSelected, let chargeExplanation = project.pledgeOverTimeCollectionPlanChargeExplanation else {
    return subtitle
  }

  return """
  \(subtitle)

  \(chargeExplanation)
  """
}
