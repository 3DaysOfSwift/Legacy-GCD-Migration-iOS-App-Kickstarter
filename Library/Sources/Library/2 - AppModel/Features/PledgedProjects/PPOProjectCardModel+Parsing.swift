import Foundation
import GraphAPI
import KsApi

private struct PPOParsedAction {
  let action: PPOProjectCardModel.ButtonAction?
  let tierType: PPOTierType
}

@MainActor
extension PPOProjectCardModel {
  public init?(node: GraphAPI.FetchPledgedProjectsQuery.Data.PledgeProjectsOverview.Pledges.Edge.Node) {
    self.init(card: PledgedProjectsResponse.Card(node.fragments.pPOCardFragment))
  }

  public init?(card: PledgedProjectsResponse.Card) {
    let image = card.imageURL
    let projectName = card.projectName
    let projectId = card.projectId
    let formattedPledge: String?
    if let amount = card.amount, let currency = card.currency,
       let decimal = try? Decimal(amount, format: .number) {
      formattedPledge = decimal.formatted(.currency(code: currency).locale(AppEnvironment.current.locale))
    } else {
      formattedPledge = nil
    }
    let creatorName = card.creatorName
    let projectPageParam = card.project.flatMap { ProjectCardProperties($0)?.projectPageParam }

    // Card-specific webview url is based on the card tier type.
    // Fall back to backingDetailsPageRoute if needed.
    let webviewUrl = card.webviewUrl

    let addressWithoutName = Self.addressWithoutName(deliveryAddress: card.deliveryAddress)
    let displayAddress = Self.displayAddress(
      card: card,
      name: card.deliveryAddress?.recipientName,
      addressWithoutName: addressWithoutName,
      webviewUrl: webviewUrl
    )

    let alerts: [PPOProjectCardModel.Alert] = card.flags.compactMap { PPOProjectCardModel.Alert(flag: $0) }

    guard let cardTierType = card.tierType, let tierType = PPOTierType(rawValue: cardTierType)
    else {
      return nil
    }
    let action = Self.actionForTierType(
      tierType: tierType,
      showShippingAddress: card.showShippingAddress,
      addressWithoutName: addressWithoutName,
      webviewUrl: webviewUrl,
      card: card
    )

    let projectAnalytics = card.analytics

    // Show the reward toggle if the backend says to show it and the v2 feature flag is on.
    let showRewardToggle = featurePledgedProjectsOverviewV2Enabled() && card.showRewardReceivedToggle
    let toggleState: PPORewardToggleState
    if !showRewardToggle {
      toggleState = .hidden
    } else if card.backerCompleted == true {
      toggleState = .rewardReceived
    } else {
      toggleState = .notReceived
    }

    let backingId = card.backingId.flatMap { decompose(id: $0) }
    let backingGraphId = card.backingId

    if let image, let projectName, let projectId, let formattedPledge, let creatorName, let action,
       let projectAnalytics, let backingId, let backingGraphId {
      self.init(
        isUnread: true,
        alerts: alerts,
        image: image,
        projectName: projectName,
        projectId: projectId,
        pledge: formattedPledge,
        creatorName: creatorName,
        address: displayAddress,
        rewardReceivedToggleState: toggleState,
        action: action.action,
        tierType: action.tierType,
        backingId: backingId,
        backingGraphId: backingGraphId,
        projectAnalytics: projectAnalytics,
        projectPageParam: projectPageParam
      )
    } else {
      return nil
    }
  }

  // MARK: Address helpers

  private static func addressWithoutName(deliveryAddress: PledgedProjectsResponse.Address?) -> String? {
    guard let deliveryAddress else { return nil }
    let cityRegionFields: [String?] = [
      deliveryAddress.city,
      deliveryAddress.region.flatMap { ", \($0)" },
      deliveryAddress.postalCode.flatMap { " \($0)" }
    ]
    let fields: [String?] = [
      deliveryAddress.addressLine1,
      deliveryAddress.addressLine2,
      cityRegionFields.compactMap { $0 }.joined(),
      deliveryAddress.countryCode,
      deliveryAddress.phoneNumber
    ]
    // Create address from all fields that are not nil and not the empty string.
    return fields.compactMap { ($0 ?? "").isEmpty ? nil : $0 }.joined(separator: "\n")
  }

  private static func displayAddress(
    card: PledgedProjectsResponse.Card,
    name: String?,
    addressWithoutName: String?,
    webviewUrl: String?
  ) -> PPOProjectCardModel.DisplayAddress {
    guard let addressWithoutName else { return .hidden }
    if !card.showShippingAddress { return .hidden }

    let address = (name ?? "") + "\n" + addressWithoutName

    if card.showEditAddressAction, let webviewUrl {
      return .editable(address: address, editUrl: webviewUrl)
    }
    return .locked(address: address)
  }

  // MARK: Action helpers

  private static func actionForTierType(
    tierType: PPOTierType,
    showShippingAddress: Bool,
    addressWithoutName: String?,
    webviewUrl: String?,
    card: PledgedProjectsResponse.Card
  ) -> PPOParsedAction? {
    switch tierType {
    case .fixPayment:
      return self.actionForPaymentFailed()
    case .confirmAddress:
      let addressId: String? = card.deliveryAddress?.id
      // Confirm address action will fall back to complete survey action if no address.
      return self.actionForConfirmAddress(
        showAddress: showShippingAddress,
        address: addressWithoutName,
        addressId: addressId
      ) ?? self.actionForSurvey(url: webviewUrl)
    case .openSurvey:
      return self.actionForSurvey(url: webviewUrl)
    case .authenticateCard:
      return self.actionForAuthentication(clientSecret: card.clientSecret)
    case .pledgeManagement:
      return self.actionForPledgeManagement(url: webviewUrl)
    case .campaignLive, .campaignFunded:
      return PPOParsedAction(action: .manageLivePledge, tierType: tierType)
    case .surveySubmitted, .pledgeCollected, .addressConfirmed, .awaitingReward, .rewardReceived,
         .campaignEnded, .campaignFailed, .pledgeDropped, .pledgeCanceled:
      return PPOParsedAction(action: nil, tierType: tierType)
    }
  }

  private static func actionForPaymentFailed() -> PPOParsedAction {
    PPOParsedAction(
      action: .fixPayment,
      tierType: .fixPayment
    )
  }

  private static func actionForConfirmAddress(showAddress: Bool, address: String?, addressId: String?)
    -> PPOParsedAction? {
    guard showAddress == true,
          let address = address,
          let addressId = addressId else {
      return nil
    }

    return PPOParsedAction(
      action: .confirmAddress(address: address, addressId: addressId),
      tierType: .confirmAddress
    )
  }

  private static func actionForSurvey(url: String?) -> PPOParsedAction? {
    guard let url else { return nil }
    return PPOParsedAction(
      action: .completeSurvey(url: url),
      tierType: .openSurvey
    )
  }

  private static func actionForPledgeManagement(url: String?) -> PPOParsedAction? {
    guard let url else { return nil }
    return PPOParsedAction(
      action: .openPledgeManager(url: url),
      tierType: .pledgeManagement
    )
  }

  private static func actionForAuthentication(clientSecret: String?)
    -> PPOParsedAction? {
    guard let clientSecret = clientSecret else { return nil }

    return PPOParsedAction(
      action: .authenticateCard(clientSecret: clientSecret),
      tierType: .authenticateCard
    )
  }
}
