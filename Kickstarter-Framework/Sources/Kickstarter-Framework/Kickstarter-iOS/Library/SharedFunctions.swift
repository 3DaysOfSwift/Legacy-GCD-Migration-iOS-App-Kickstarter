import Library
import UIKit

// MARK: - Haptic feedback

@MainActor
func generateImpactFeedback(
  feedbackGenerator: UIImpactFeedbackGeneratorType = UIImpactFeedbackGenerator(style: .light)
) {
  feedbackGenerator.prepare()
  feedbackGenerator.impactOccurred()
}

@MainActor
func generateNotificationSuccessFeedback(
  feedbackGenerator: UINotificationFeedbackGeneratorType = UINotificationFeedbackGenerator()
) {
  feedbackGenerator.prepare()
  feedbackGenerator.notificationOccurred(.success)
}

@MainActor
func generateNotificationWarningFeedback(
  feedbackGenerator: UINotificationFeedbackGeneratorType = UINotificationFeedbackGenerator()
) {
  feedbackGenerator.prepare()
  feedbackGenerator.notificationOccurred(.warning)
}

@MainActor
func generateSelectionFeedback(
  feedbackGenerator: UISelectionFeedbackGeneratorType = UISelectionFeedbackGenerator()
) {
  feedbackGenerator.prepare()
  feedbackGenerator.selectionChanged()
}

// MARK: - Login workflow

@MainActor
public func logoutAndDismiss(
  viewController: UIViewController,
  appEnvironment: AppEnvironmentType.Type = AppEnvironment.self,
  pushNotificationDialog: PushNotificationDialogType.Type =
    PushNotificationDialog.self
) {
  appEnvironment.logout()

  pushNotificationDialog.resetAllContexts()

  NotificationCenter.default.post(.init(name: .ksr_sessionEnded))

  viewController.dismiss(animated: true, completion: nil)
}
