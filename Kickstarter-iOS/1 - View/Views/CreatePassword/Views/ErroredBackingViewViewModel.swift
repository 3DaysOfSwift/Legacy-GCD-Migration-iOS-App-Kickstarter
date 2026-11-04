import Foundation
import KsApi
import Prelude
import Observation

@MainActor @Observable
public final class ErroredBackingViewViewModel {
  public init() {}

  public private(set) var projectName: String?
  public private(set) var finalCollectionDateText: String?
  private var backing: ProjectAndBackingEnvelope?

  public func configure(with value: ProjectAndBackingEnvelope) {
    self.backing = value
    self.projectName = value.project.name
    if let date = value.project.dates.finalCollectionDate {
      self.finalCollectionDateText = timeLeftString(finalCollectionDate: date)
    }
  }

  public func backingForManageAction() -> ProjectAndBackingEnvelope? {
    self.backing
  }
}

@MainActor
private func timeLeftString(finalCollectionDate: TimeInterval) -> String {
  let (time, unit) = timeLeft(
    secondsInUTC: finalCollectionDate, env: AppEnvironment.current
  )
  return Strings.Time_left_left(time_left: time + " " + unit)
}

@MainActor
private func timeLeft(
  secondsInUTC seconds: TimeInterval,
  env: Environment
)
  -> (time: String, unit: String) {
  let components = env.calendar.dateComponents(
    [.day, .hour],
    from: env.dateType.init().date,
    to: env.dateType.init(timeIntervalSince1970: seconds).date
  )

  let (day, hour) = (
    components.day ?? 0,
    components.hour ?? 0
  )

  let string: String
  if day > 1 {
    string = Strings.dates_time_days(time_count: day)
  } else if day == 1 || hour > 0 {
    let count = day * 24 + hour
    string = Strings.dates_time_hours(time_count: count)
  } else if hour <= 1 {
    let count = 1
    string = Strings.dates_time_hours(time_count: count)
  } else {
    string = ""
  }

  let split = string
    .replacingOccurrences(of: "(\\d+) *", with: "$1 ", options: .regularExpression)
    .components(separatedBy: " ")

  guard split.count >= 1 else { return ("", "") }

  let result = (
    time: split.first ?? "",
    unit: split.suffix(from: 1).joined(separator: " ")
  )

  return result
}
