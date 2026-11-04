import KsApi
import Observation

@MainActor
@Observable
public final class SettingsNotificationPickerViewModel {
  public init() {}
  public private(set) var frequencyValueText: String?

  public func configure(with cellValue: SettingsNotificationCellValue) {
    guard let digest = cellValue.user[keyPath: UserAttribute.notification(.creatorDigest).keyPath] else { return }
    self.frequencyValueText = (digest ? EmailFrequency.dailySummary : .twiceADaySummary).descriptionText
  }
}
