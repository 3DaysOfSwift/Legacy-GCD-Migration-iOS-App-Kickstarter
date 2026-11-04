import Foundation
import UIKit

@MainActor
public enum Keyboard {
  public typealias Change = (
    frame: CGRect, duration: TimeInterval, options: UIView.AnimationOptions,
    notificationName: Notification.Name
  )

  @MainActor public final class Observation {
    private var observations: [MainActorNotificationObservation] = []

    fileprivate init(handler: @escaping @MainActor (Change) -> Void) {
      for name in [UIResponder.keyboardWillShowNotification, UIResponder.keyboardWillHideNotification] {
        self.observations.append(MainActorNotificationObservation(name: name) { notification in
          guard let userInfo = notification.userInfo,
                let frame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
                let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber,
                let curveNumber = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber,
                let curve = UIView.AnimationCurve(rawValue: curveNumber.intValue) else { return }
          handler((frame.cgRectValue, duration.doubleValue,
                   UIView.AnimationOptions(rawValue: UInt(curve.rawValue)), notification.name))
        })
      }
    }
    public func cancel() { self.observations.forEach { $0.cancel() }; self.observations.removeAll() }
  }

  public static func observe(_ handler: @escaping @MainActor (Change) -> Void) -> Observation {
    Observation(handler: handler)
  }
}
