import KsApi
import UIKit

@MainActor
public final class BackingCellViewModel {
  struct Display {
    let isBackingInfoHidden: Bool
    let pledged: String
    let reward: String
    let delivery: String
    let alignment: UIStackView.Alignment
  }
  var onDisplay: ((Display) -> Void)?

  func configureWith(backing: Backing, project: Project, isFromBacking: Bool) {
    let delivery = backing.reward?.estimatedDeliveryOn.map {
      Strings.backing_info_estimated_delivery_date(
        delivery_date: Format.date(secondsInUTC: $0, template: DateFormatter.monthYear, timeZone: UTCTimeZone)
      )
    } ?? ""
    self.onDisplay?(Display(
      isBackingInfoHidden: isFromBacking,
      pledged: Strings.backing_info_pledged_backing_amount(
        backing_amount: Format.currency(backing.amount, currencyCode: project.statsCurrency)
      ),
      reward: backing.reward?.description ?? "",
      delivery: delivery,
      alignment: AppEnvironment.current.isVoiceOverRunning() ? .fill : .leading
    ))
  }
}
