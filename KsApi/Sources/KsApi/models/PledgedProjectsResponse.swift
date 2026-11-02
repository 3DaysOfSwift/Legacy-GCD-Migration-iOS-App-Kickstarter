import Foundation
import GraphAPI

/// Values copied inside the transport callback, before resuming its caller.
public struct PledgedProjectsResponse: Sendable {
  public let cards: [Card]
  public let cursor: String?
  public let total: Int?

  public init(_ data: GraphAPI.FetchPledgedProjectsQuery.Data) {
    let pledges = data.pledgeProjectsOverview?.pledges
    self.cards = pledges?.edges?.compactMap { $0?.node }.map { Card($0.fragments.pPOCardFragment) } ?? []
    self.cursor = pledges?.pageInfo.endCursor
    self.total = pledges?.totalCount
  }

  public struct Card: Sendable {
    public let imageURL: URL?
    public let projectName: String?
    public let projectId: Int?
    public let creatorName: String?
    public let amount: String?
    public let currency: String?
    public let webviewUrl: String?
    public let tierType: String?
    public let showShippingAddress: Bool
    public let showEditAddressAction: Bool
    public let showRewardReceivedToggle: Bool
    public let backerCompleted: Bool?
    public let backingId: String?
    public let clientSecret: String?
    public let deliveryAddress: Address?
    public let flags: [Flag]
    public let analytics: ProjectAnalyticsSnapshot?
    public let project: ProjectCardResponse?

    public init(_ card: GraphAPI.PPOCardFragment) {
      let backing = card.backing?.fragments.pPOBackingFragment
      let project = backing?.project?.fragments.pPOProjectFragment
      self.imageURL = project?.image.flatMap { URL(string: $0.url) }
      self.projectName = project?.name
      self.projectId = project?.pid
      self.creatorName = project?.creator?.name
      self.amount = backing?.amount.fragments.moneyFragment.amount
      self.currency = backing?.amount.fragments.moneyFragment.currency?.value?.rawValue
      self.webviewUrl = card.webviewUrl ?? backing?.backingDetailsPageRoute
      self.tierType = card.tierType
      self.showShippingAddress = card.showShippingAddress
      self.showEditAddressAction = card.showEditAddressAction
      self.showRewardReceivedToggle = card.showRewardReceivedToggle
      self.backerCompleted = backing?.backerCompleted
      self.backingId = backing?.id
      self.clientSecret = backing?.clientSecret
      self.deliveryAddress = backing?.deliveryAddress.map(Address.init)
      self.flags = card.flags?.map(Flag.init) ?? []
      self.analytics = backing?.project.map { ProjectAnalyticsSnapshot($0.fragments.projectAnalyticsFragment) }
      self.project = backing?.project.map { ProjectCardResponse($0.fragments.projectCardFragment) }
    }
  }

  public struct Address: Sendable {
    public let id: String
    public let recipientName: String?
    public let addressLine1: String?
    public let addressLine2: String?
    public let city: String?
    public let region: String?
    public let postalCode: String?
    public let countryCode: String
    public let phoneNumber: String?

    init(_ address: GraphAPI.PPOBackingFragment.DeliveryAddress) {
      self.id = address.id
      self.recipientName = address.recipientName
      self.addressLine1 = address.addressLine1
      self.addressLine2 = address.addressLine2
      self.city = address.city
      self.region = address.region
      self.postalCode = address.postalCode
      self.countryCode = address.countryCode.rawValue
      self.phoneNumber = address.phoneNumber
    }
  }

  public struct Flag: Sendable {
    public let icon: String?
    public let type: String?
    public let message: String?

    init(_ flag: GraphAPI.PPOCardFragment.Flag) {
      self.icon = flag.icon
      self.type = flag.type
      self.message = flag.message
    }
  }
}
