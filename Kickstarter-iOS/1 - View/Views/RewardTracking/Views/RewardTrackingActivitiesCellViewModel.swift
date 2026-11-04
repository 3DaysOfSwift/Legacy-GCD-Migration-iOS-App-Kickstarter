import Foundation
import KsApi

public struct RewardTrackingActivitiesCellData {
  public let trackingData: RewardTrackingDetailsViewData
  public let project: Project

  public init(trackingData: RewardTrackingDetailsViewData, project: Project) {
    self.trackingData = trackingData
    self.project = project
  }
}
