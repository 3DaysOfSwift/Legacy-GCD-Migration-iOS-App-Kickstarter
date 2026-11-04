import Foundation
import KDS
import KsApi
import Observation
import UIKit

@MainActor
@Observable
public final class ProjectPamphletCreatorHeaderCellViewModel {
  public init() {}
  public private(set) var launchDateLabelAttributedText: NSAttributedString?
  public func configure(with project: Project) {
    self.launchDateLabelAttributedText = attributedLaunchDateString(with: project)
  }
}

@MainActor
private func attributedLaunchDateString(with project: Project) -> NSAttributedString? {
  var launchDate = ""

  if let date = project.dates.launchedAt {
    launchDate = Format.date(
      secondsInUTC: date,
      dateStyle: .long,
      timeStyle: .none,
      timeZone: UTCTimeZone
    )
  }

  let fullString = Strings.You_launched_this_project_on_launch_date(launch_date: launchDate)

  let attributedString: NSMutableAttributedString = NSMutableAttributedString(string: fullString)
  let fullRange = (fullString as NSString).localizedStandardRange(of: fullString)
  let rangeDate: NSRange = (fullString as NSString).localizedStandardRange(of: launchDate)

  let paragraphStyle = NSMutableParagraphStyle()
  paragraphStyle.alignment = .left

  let regularFontAttribute = [
    NSAttributedString.Key.paragraphStyle: paragraphStyle,
    NSAttributedString.Key.font: UIFont.ksr_subhead(),
    NSAttributedString.Key.foregroundColor: LegacyColors.ksr_support_700.uiColor()
  ]
  let boldFontAttribute = [NSAttributedString.Key.font: UIFont.ksr_subhead().bolded]

  attributedString.addAttributes(regularFontAttribute, range: fullRange)
  attributedString.addAttributes(boldFontAttribute, range: rangeDate)
  return attributedString
}
