import Foundation

public struct RewardTrackingDetailsViewData {
  public let trackingNumber: String
  public let trackingURL: URL?

  public init(trackingNumber: String, trackingURL: URL?) {
    self.trackingNumber = trackingNumber
    self.trackingURL = trackingURL
  }
}
