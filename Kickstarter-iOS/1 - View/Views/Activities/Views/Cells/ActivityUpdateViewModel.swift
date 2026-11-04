import KDS
import KsApi
import Prelude
import Observation
import UIKit

@MainActor @Observable
public final class ActivityUpdateViewModel {
  public init() {}
  public private(set) var activity: Activity?
  public private(set) var body: String?
  public private(set) var cellAccessibilityLabel: String?
  public private(set) var projectImageURL: URL?
  public private(set) var projectName: String?
  public private(set) var sequenceTitle: NSAttributedString?
  public private(set) var title: String?

  public func configureWith(activity: Activity) {
    self.activity = activity
    if let project = activity.project {
      self.projectImageURL = URL(string: project.photo.med)
      self.projectName = project.name
    }
    if let update = activity.update {
      self.body = update.body?.htmlStripped()?.truncated(maxLength: 300) ?? ""
      self.title = update.title
    }
    self.sequenceTitle = updatePostedString(forActivity: activity)
    if let projectName = self.projectName, let sequence = self.sequenceTitle {
      self.cellAccessibilityLabel = "\(projectName) \(sequence.string)"
    }
  }
}

private let decimalCharacterSet = NSCharacterSet.decimalDigits.inverted

@MainActor
private func updatePostedString(forActivity activity: Activity) -> NSAttributedString {
  let updateNum = Format.wholeNumber(activity.update?.sequence ?? 1)
  let time = Format.relative(secondsInUTC: activity.createdAt)
  let fullString = Strings.dashboard_activity_update_number_posted_time_count_days_ago(
    space: " ",
    update_number: updateNum,
    time_count_days_ago: time
  )

  let attributedString = fullString.simpleHtmlAttributedString(
    base: [
      NSAttributedString.Key.font: UIFont.ksr_footnote(),
      NSAttributedString.Key.foregroundColor: LegacyColors.ksr_support_700.uiColor()
    ],
    bold: [
      NSAttributedString.Key.font: UIFont.ksr_headline(size: 13.0),
      NSAttributedString.Key.foregroundColor: LegacyColors.ksr_support_700.uiColor()
    ]
  ) ?? .init(string: "")

  let mutableString = NSMutableAttributedString(attributedString: attributedString)

  let timeNumber = time.components(separatedBy: decimalCharacterSet).first

  if let timeRange = mutableString.string.range(of: time), let timeNumber = timeNumber {
    let timeStartIndex = mutableString.string
      .distance(from: mutableString.string.startIndex, to: timeRange.lowerBound)
    let timeNumberStartIndex = mutableString.string
      .distance(from: time.startIndex, to: timeNumber.startIndex)

    mutableString.addAttributes(
      [
        NSAttributedString.Key.font: UIFont.ksr_headline(size: 13.0),
        NSAttributedString.Key.foregroundColor: LegacyColors.ksr_support_700.uiColor()
      ],
      range: NSRange(location: timeStartIndex + timeNumberStartIndex, length: timeNumber.count)
    )
  }

  return mutableString
}
