import KDS
import KsApi
import Prelude
import Observation
import UIKit

public struct ManageViewPledgeRewardReceivedViewData: Equatable {
  public let project: Project
  public let backerCompleted: Bool
  public let estimatedDeliveryOn: TimeInterval
  public let backingState: Backing.Status
  public let estimatedShipping: String?
  public let pledgeDisclaimerViewHidden: Bool
}

@MainActor @Observable
public final class ManageViewPledgeRewardReceivedViewModel {
  public private(set) var cornerRadius: CGFloat = 0
  public private(set) var estimatedDeliveryDateLabelAttributedText: NSAttributedString?
  public private(set) var estimatedShippingAttributedText: NSAttributedString?
  public private(set) var estimatedShippingHidden = true
  public private(set) var layoutMargins: UIEdgeInsets = .zero
  public private(set) var marginWidth: CGFloat = 0
  public private(set) var pledgeDisclaimerViewHidden = false
  public private(set) var rewardReceived = false
  public private(set) var rewardReceivedHidden = true
  @ObservationIgnored public var onChange: (@MainActor () -> Void)?
  @ObservationIgnored private let feature: PledgeFeature
  @ObservationIgnored private let delay: @MainActor () async throws -> Void
  @ObservationIgnored private var observation: Task<Void, Never>?
  private var data: ManageViewPledgeRewardReceivedViewData?
  private var loaded = false

  public init(feature: PledgeFeature = AppModel.shared.pledgeFeature,
              delay: @escaping @MainActor () async throws -> Void = {
    let interval = AppEnvironment.current.apiDelayInterval
    switch interval {
    case .seconds(let n): try await Task.sleep(for: .seconds(n))
    case .milliseconds(let n): try await Task.sleep(for: .milliseconds(n))
    case .microseconds(let n): try await Task.sleep(for: .microseconds(n))
    case .nanoseconds(let n): try await Task.sleep(for: .nanoseconds(n))
    case .never: try await Task.sleep(nanoseconds: UInt64.max)
    @unknown default: break
    }
  }) {
    self.feature = feature
    self.delay = delay
  }

  public func configureWith(_ data: ManageViewPledgeRewardReceivedViewData) {
    self.data = data
    if self.loaded { self.apply(data) }
  }

  public func viewDidLoad() {
    self.loaded = true
    if let data = self.data { self.apply(data) }
  }

  private func apply(_ data: ManageViewPledgeRewardReceivedViewData) {
    self.rewardReceived = data.backerCompleted
    self.estimatedDeliveryDateLabelAttributedText = estimatedDeliveryAttributedText(with: data.estimatedDeliveryOn)
    if let shipping = data.estimatedShipping { self.estimatedShippingAttributedText = formatEstimatedShipping(with: shipping) }
    self.estimatedShippingHidden = data.estimatedShipping == nil
    self.rewardReceivedHidden = data.backingState != .collected
    self.cornerRadius = self.rewardReceivedHidden ? 0 : Styles.grid(2)
    self.layoutMargins = self.rewardReceivedHidden ? .zero : .init(all: Styles.gridHalf(5))
    self.marginWidth = self.rewardReceivedHidden ? 0 : 1
    self.pledgeDisclaimerViewHidden = data.pledgeDisclaimerViewHidden
    self.onChange?()
  }

  public func rewardReceivedToggleTapped(isOn: Bool) {
    guard self.loaded, let data = self.data else { return }
    AppEnvironment.current.ksrAnalytics.trackRewardReceivedToggled(
      toggleOn: isOn, project: data.project, context: .managePledgeScreen
    )
    guard let user = AppEnvironment.current.currentUser else { return }
    let generation = self.feature.sessionFeature.generation
    let sessionUserID = self.feature.sessionFeature.currentUser?.id
    let task = self.feature.startReceived(projectID: data.project.id, userID: user.id, received: isOn)
    self.observation?.cancel()
    self.observation = Task { [weak self] in
      do {
        let backing = try await task.value
        guard let self else { return }
        try await self.delay()
        try Task.checkCancellation()
        guard self.feature.sessionFeature.generation == generation,
              self.feature.sessionFeature.currentUser?.id == sessionUserID else { return }
        self.rewardReceived = backing.backerCompleted ?? false
        self.onChange?()
      } catch { }
    }
  }

  func waitForObservation() async { await self.observation?.value }
  deinit { self.observation?.cancel() }
}

private func formatEstimatedShipping(with shippingRange: String) -> NSAttributedString {
  // In this UI, the title and value are simply separated by a space.
  let totalString = "\(Strings.Estimated_Shipping()) \(shippingRange)"
  return attributedText(totalString: totalString, valueSubstring: shippingRange)
}

@MainActor
private func estimatedDeliveryAttributedText(with date: TimeInterval) -> NSAttributedString {
  let dateString = Format.date(
    secondsInUTC: date,
    template: DateFormatter.monthYear,
    timeZone: UTCTimeZone
  )
  let string = Strings.backing_info_estimated_delivery_date(delivery_date: dateString)

  return attributedText(totalString: string, valueSubstring: dateString)
}

private func attributedText(totalString: String, valueSubstring: String) -> NSAttributedString {
  let font = UIFont.ksr_subhead()

  let attributedText = NSMutableAttributedString(
    attributedString: totalString
      .attributed(
        with: font,
        foregroundColor: LegacyColors.ksr_support_400.uiColor(),
        attributes: [:],
        bolding: [totalString.replacingOccurrences(of: valueSubstring, with: "")]
      )
  )

  attributedText.setAttributes(
    [
      .font: font,
      .foregroundColor: LegacyColors.ksr_support_700.uiColor()
    ],
    range: (totalString as NSString).range(of: valueSubstring)
  )

  return attributedText
}
