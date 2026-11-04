import Foundation
import KDS
import UIKit

public enum EmptyStateViewType {
  case errorPullToRefresh
  case addOnsUnavailable

  var imageName: String? {
    switch self {
    case .errorPullToRefresh: return "icon-exclamation"
    case .addOnsUnavailable: return "icon-globe"
    }
  }

  var leftRightMargins: CGFloat {
    switch self {
    case .errorPullToRefresh: return Styles.grid(10)
    case .addOnsUnavailable: return Styles.grid(3)
    }
  }

  var titleLabelHidden: Bool {
    switch self {
    case .errorPullToRefresh: return true
    case .addOnsUnavailable: return false
    }
  }

  var bodyLabelHidden: Bool {
    return false
  }

  var titleLabelText: String {
    switch self {
    case .errorPullToRefresh: return ""
    case .addOnsUnavailable:
      return Strings.Add_ons_unavailable()
    }
  }

  var bodyLabelText: String {
    switch self {
    case .errorPullToRefresh:
      return Strings.Something_went_wrong_pull_to_refresh()
    case .addOnsUnavailable:
      return Strings.Change_your_shipping_location_or_skip_add_ons_to_continue()
    }
  }

  var bodyLabelTextColor: UIColor {
    switch self {
    case .errorPullToRefresh:
      return LegacyColors.ksr_support_700.uiColor()
    case .addOnsUnavailable:
      return LegacyColors.ksr_support_400.uiColor()
    }
  }
}
