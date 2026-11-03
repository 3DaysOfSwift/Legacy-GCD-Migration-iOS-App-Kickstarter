import UIKit
import XCTest
import Library

@MainActor
final class KeyboardNotificationTests: XCTestCase {
  func testKeyboardChangeIsDeliveredSynchronouslyWithExistingPayload() {
    var received: Keyboard.Change?
    let observation = Keyboard.change.observeValues { received = $0 }
    defer { observation?.dispose() }
    let frame = CGRect(x: 0, y: 400, width: 320, height: 216)
    NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil, userInfo: [
      UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: frame),
      UIResponder.keyboardAnimationDurationUserInfoKey: NSNumber(value: 0.25),
      UIResponder.keyboardAnimationCurveUserInfoKey: NSNumber(value: UIView.AnimationCurve.easeInOut.rawValue)
    ])
    XCTAssertEqual(received?.frame, frame)
    XCTAssertEqual(received?.duration, 0.25)
    XCTAssertEqual(received?.notificationName, UIResponder.keyboardWillShowNotification)
  }

  func testMalformedKeyboardNotificationDoesNotEmit() {
    var count = 0
    let observation = Keyboard.change.observeValues { _ in count += 1 }
    defer { observation?.dispose() }
    NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil)
    XCTAssertEqual(count, 0)
  }
}
