import Foundation
import KsApi
import Prelude
import ReactiveSwift

@MainActor
public protocol ErroredBackingViewViewModelInputs {
  func configure(with value: ProjectAndBackingEnvelope)
  func manageButtonTapped()
}

@MainActor
public protocol ErroredBackingViewViewModelOutputs {
  var finalCollectionDateText: Signal<String, Never> { get }
  var notifyDelegateManageButtonTapped: Signal<ProjectAndBackingEnvelope, Never> { get }
  var projectName: Signal<String, Never> { get }
}

@MainActor
public protocol ErroredBackingViewViewModelType {
  var inputs: ErroredBackingViewViewModelInputs { get }
  var outputs: ErroredBackingViewViewModelOutputs { get }
}

@MainActor
public final class ErroredBackingViewViewModel: ErroredBackingViewViewModelType,
  ErroredBackingViewViewModelInputs, ErroredBackingViewViewModelOutputs {
  public init() {
    let project = self.configDataSignal.map(\.project)

    self.projectName = project
      .map(\.name)

    let collectionDate = project
      .map(\.dates.finalCollectionDate)
      .skipNil()

    self.finalCollectionDateText = collectionDate
      .map { timeLeftString(finalCollectionDate: $0) }

    self.notifyDelegateManageButtonTapped = self.configDataSignal
      .takeWhen(self.manageButtonTappedSignal)
  }

  private let (configDataSignal, configDataObserver) = Signal<ProjectAndBackingEnvelope, Never>.pipe()
  public func configure(with value: ProjectAndBackingEnvelope) {
    self.configDataObserver.send(value: value)
  }

  private let (manageButtonTappedSignal, manageButtonTappedObserver) = Signal<Void, Never>.pipe()
  public func manageButtonTapped() {
    self.manageButtonTappedObserver.send(value: ())
  }

  public let finalCollectionDateText: Signal<String, Never>
  public let notifyDelegateManageButtonTapped: Signal<ProjectAndBackingEnvelope, Never>
  public let projectName: Signal<String, Never>

  public var inputs: ErroredBackingViewViewModelInputs { return self }
  public var outputs: ErroredBackingViewViewModelOutputs { return self }
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
