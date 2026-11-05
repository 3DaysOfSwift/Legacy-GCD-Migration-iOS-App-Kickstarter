import Foundation
import GraphAPI

extension ClearUserUnseenActivityEnvelope {
  /**
   Map `GraphAPI.ClearUserUnseenActivityMutation.Data` to a `ClearUserUnseenActivityEnvelope`, otherwise return `nil`
   */
  static func from(
    _ data: GraphAPI.ClearUserUnseenActivityMutation
      .Data
  ) -> ClearUserUnseenActivityEnvelope? {
    guard let count = data.clearUserUnseenActivity?.activityIndicatorCount else { return nil }
    return ClearUserUnseenActivityEnvelope(activityIndicatorCount: count)
  }

}
