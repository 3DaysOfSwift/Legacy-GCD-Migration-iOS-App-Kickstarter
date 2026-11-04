import Foundation
import KDS
import KsApi
import Prelude
import Observation
import UIKit

@MainActor @Observable
public final class PledgeOverTimePaymentScheduleViewModel {
  public init() {}
  public private(set) var collapsed = true
  public private(set) var paymentScheduleItems: [PLOTPaymentScheduleItem]?
  private var increments: [PledgePaymentIncrement]?
  private var loaded = false

  public func viewDidLoad() {
    self.loaded = true
    if let increments = self.increments {
      self.paymentScheduleItems = increments.map { PLOTPaymentScheduleItem(with: $0) }
    }
  }

  public func configure(with increments: [PledgePaymentIncrement]) {
    self.increments = increments
    if self.loaded { self.paymentScheduleItems = increments.map { PLOTPaymentScheduleItem(with: $0) } }
  }

  public func collapseToggle() {
    self.collapsed.toggle()
  }
}

// MARK: - PLOTPaymentScheduleItem

public struct PLOTPaymentScheduleItem: Equatable {
  public var dateString: String
  public var stateLabel: String
  public var badgeStyle: BadgeStyle
  public var amountString: String

  @MainActor
  init(with increment: PledgePaymentIncrement) {
    self.dateString = Format.date(
      secondsInUTC: increment.scheduledCollection,
      dateStyle: .medium,
      timeStyle: .none
    )

    self.amountString = getAmountString(from: increment)
    self.stateLabel = getStateLabelText(from: increment)
    self.badgeStyle = getBadgeStyle(from: increment)
  }
}

private func getAmountString(from increment: PledgePaymentIncrement) -> String {
  // Only display the adjusted amount if a partial refund was issued.
  // If the payment increment was fully refunded, display the full payment increment amount.
  if case let .partialRefund(refundedAmount) = increment.refundStatus {
    return refundedAmount.amountFormattedInProjectNativeCurrency
  }

  return increment.amount.amountFormattedInProjectNativeCurrency
}

private func getStateLabelText(from increment: PledgePaymentIncrement) -> String {
  guard let badge = increment.badge else {
    assert(false, "Missing badge when it should have been fetched.")
    return ""
  }

  return badge.copy
}

private func getBadgeStyle(from increment: PledgePaymentIncrement) -> BadgeStyle {
  guard let badge = increment.badge else {
    assert(false, "Missing badge when it should have been fetched.")
    return .neutral
  }

  switch badge.variant {
  case .purple:
    return .custom(
      foregroundColor: Colors.PLOT.Badge.Text.purple.uiColor(),
      backgroundColor: Colors.PLOT.Badge.Background.purple.uiColor()
    )
  case .green:
    return .custom(
      foregroundColor: Colors.PLOT.Badge.Text.green.uiColor(),
      backgroundColor: Colors.PLOT.Badge.Background.green.uiColor()
    )
  case .red:
    // TODO: This variant isn't implemented on the backend; I believe it's a bug and should actually be danger.
    fallthrough
  case .danger:
    return BadgeStyle.custom(
      foregroundColor: Colors.PLOT.Badge.Text.danger.uiColor(),
      backgroundColor: Colors.PLOT.Badge.Background.danger.uiColor()
    )
  case .gray:
    return .custom(
      foregroundColor: Colors.PLOT.Badge.Text.gray.uiColor(),
      backgroundColor: Colors.PLOT.Badge.Background.gray.uiColor()
    )
  }
}
