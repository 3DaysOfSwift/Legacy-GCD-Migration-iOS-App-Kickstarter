import KDS
import KsApi
import Observation
import UIKit

@MainActor @Observable
public final class ActivitySurveyResponseCellViewModel {
  public init() {}
  public private(set) var creatorImageURL: URL?
  public private(set) var creatorNameText: String?
  public private(set) var rewardSurveysCountIsHidden = false
  public private(set) var rewardSurveysCountText = ""
  public private(set) var surveyLabelText: NSAttributedString?
  public private(set) var surveyResponse: SurveyResponse?

  public func configureWith(surveyResponse: SurveyResponse, count: Int, position: Int) {
    self.surveyResponse = surveyResponse
    self.rewardSurveysCountIsHidden = count > 1 && position != 0
    self.rewardSurveysCountText = Strings.Reward_Surveys(reward_survey_count: count)
    guard let project = surveyResponse.project else { return }
    self.creatorImageURL = URL(string: project.creator.avatar.small)
    self.creatorNameText = project.creator.name
    let text = Strings.Creator_name_needs_some_information_to_deliver_your_reward_for_project_name(
      creator_name: project.creator.name, project_name: project.name
    )
    self.surveyLabelText = text.simpleHtmlAttributedString(
      base: [.font: UIFont.ksr_subhead(size: 14), .foregroundColor: LegacyColors.ksr_support_700.uiColor()],
      bold: [.font: UIFont.ksr_headline(size: 14), .foregroundColor: LegacyColors.ksr_support_700.uiColor()]
    ) ?? NSAttributedString(string: "")
  }
}
