import UIKit

// MARK: - UIFeedbackGenerator

@MainActor
protocol UIFeedbackGeneratorType {
  func prepare()
}

// MARK: - UIImpactFeedbackGeneratorType

@MainActor
protocol UIImpactFeedbackGeneratorType: UIFeedbackGeneratorType {
  func impactOccurred()
}

extension UIImpactFeedbackGenerator: UIImpactFeedbackGeneratorType {}

// MARK: - UINotificationFeedbackGeneratorType

@MainActor
protocol UINotificationFeedbackGeneratorType: UIFeedbackGeneratorType {
  func notificationOccurred(_ notificationType: UINotificationFeedbackGenerator.FeedbackType)
}

extension UINotificationFeedbackGenerator: UINotificationFeedbackGeneratorType {}

// MARK: - UISelectionFeedbackGeneratorType

@MainActor
protocol UISelectionFeedbackGeneratorType: UIFeedbackGeneratorType {
  func selectionChanged()
}

extension UISelectionFeedbackGenerator: UISelectionFeedbackGeneratorType {}
