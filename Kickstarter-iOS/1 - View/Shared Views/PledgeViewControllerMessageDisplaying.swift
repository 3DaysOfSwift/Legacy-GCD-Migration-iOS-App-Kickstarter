import Foundation
import UIKit

@MainActor
protocol PledgeViewControllerMessageDisplaying: AnyObject {
  func pledgeViewController(
    _ pledgeViewController: UIViewController,
    didErrorWith message: String,
    error: Error?
  )
  func pledgeViewController(_ pledgeViewController: UIViewController, didSucceedWith message: String)
}
