@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class RewardAddOnCardViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  fileprivate let vm = RewardAddOnCardViewModel()

  private let addButtonHidden = Recorder<Bool>()
  private let amountConversionLabelHidden = Recorder<Bool>()
  private let amountConversionLabelText = Recorder<String>()
  private let amountLabelAttributedText = Recorder<String>()
  private let descriptionLabelText = Recorder<String>()
  private let estimatedDeliveryDateLabelHidden = Recorder<Bool>()
  private let estimatedDeliveryDateLabelText = Recorder<String>()
  private let generateSelectionFeedback = Recorder<Void>()
  private let generateNotificationWarningFeedback = Recorder<Void>()
  private let includedItemsLabelAttributedText = Recorder<String>()
  private let includedItemsStackViewHidden = Recorder<Bool>()
  private let notifiyDelegateDidSelectQuantityQuantity = Recorder<Int>()
  private let notifiyDelegateDidSelectQuantityRewardId = Recorder<Int>()
  private let pillsViewHidden = Recorder<Bool>()
  private let quantityLabelText = Recorder<String>()
  private let reloadPills = Recorder<[String]>()
  private let rewardTitleLabelText = Recorder<String>()
  private let rewardLocationPickupLabelText = Recorder<String>()
  private let rewardLocationStackViewHidden = Recorder<Bool>()
  private let stepperMaxValue = Recorder<Double>()
  private let stepperStackViewHidden = Recorder<Bool>()
  private let stepperValue = Recorder<Double>()
  private let rewardImageURL = Recorder<String>()
  private let rewardImageHidden = Recorder<Bool>()

  override func setUp() async throws {
    try await super.setUp()
    self.vm.onQuantity = { [weak self] quantity in
      self?.addButtonHidden.record(quantity > 0)
      self?.quantityLabelText.record(String(quantity))
      self?.stepperStackViewHidden.record(quantity == 0)
      self?.stepperValue.record(Double(quantity))
    }
    self.vm.onQuantitySelected = { [weak self] quantity, rewardId in
      self?.notifiyDelegateDidSelectQuantityQuantity.record(quantity)
      self?.notifiyDelegateDidSelectQuantityRewardId.record(rewardId)
    }
    self.vm.onSelectionFeedback = { [weak self] in self?.generateSelectionFeedback.record(()) }
    self.vm.onWarningFeedback = { [weak self] in self?.generateNotificationWarningFeedback.record(()) }

    var previousItemsHidden: Bool?
    self.vm.onDisplay = { [weak self] display in
      guard let self else { return }
      self.amountLabelAttributedText.record(display.amount.string)
      self.amountConversionLabelHidden.record(display.conversionHidden)
      if let text = display.conversion { self.amountConversionLabelText.record(text) }
      self.descriptionLabelText.record(display.description)
      if let items = display.includedItems { self.includedItemsLabelAttributedText.record(items.string) }
      if previousItemsHidden != display.includedItemsHidden {
        self.includedItemsStackViewHidden.record(display.includedItemsHidden)
        previousItemsHidden = display.includedItemsHidden
      }
      self.pillsViewHidden.record(display.pills.isEmpty)
      self.reloadPills.record(display.pills)
      if let title = display.title { self.rewardTitleLabelText.record(title) }
      self.rewardLocationStackViewHidden.record(display.pickupHidden)
      if let pickup = display.pickup { self.rewardLocationPickupLabelText.record(pickup) }
      self.stepperMaxValue.record(display.maximum)
      if let url = display.image?.url { self.rewardImageURL.record(url) }
      self.rewardImageHidden.record(display.image == nil)
    }
  }

  // MARK: - Reward Title

  func testTitleLabel() {
    let reward = .template
      |> Reward.lens.title .~ "The thing"
      |> Reward.lens.remaining .~ nil

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.rewardTitleLabelText.assertValues(["The thing"])
  }

  func testRewardWithImage() {
    let imageURL = "https://ksr.com/image.jpg"

    let reward = .template
      |> Reward.lens.image .~ Reward.Image(altText: "The image", url: imageURL)

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.rewardImageURL.assertValue(imageURL)
    self.rewardImageHidden.assertValue(false)
  }

  func testRewardNotImage() {
    let reward = .template
      |> Reward.lens.image .~ nil

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.rewardImageURL.assertDidNotEmitValue()
    self.rewardImageHidden.assertValue(true)
  }

  func testTitleLabel_NoTitle() {
    let reward = .template
      |> Reward.lens.title .~ nil
      |> Reward.lens.remaining .~ nil

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.rewardTitleLabelText.assertValues([])
  }

  func testTitleLabel_Backed_AddOn() {
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ true

    let reward = .template
      |> Reward.lens.title .~ "The thing"
      |> Reward.lens.remaining .~ nil

    self.vm
      .configure(with: .init(
        project: project,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [reward.id: 2]
      ))

    self.rewardTitleLabelText.assertValues(["The thing"])
  }

  // MARK: - Reward Minimum

  func testMinimumLabel_US_Project_US_ProjectCurrency_US_UserLocation() {
    let project = Project.template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode
    let reward = .template |> Reward.lens.minimum .~ 1_000

    withEnvironment(countryCode: "US") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountLabelAttributedText.assertValues(
        ["$1,000"],
        "Reward minimum appears in project's currency, without a currency symbol."
      )
    }
  }

  func testMinimumLabel_US_Project_US_ProjectCurrency_NonUS_UserLocation() {
    let project = Project.template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode
    let reward = .template |> Reward.lens.minimum .~ 1_000

    withEnvironment(countryCode: "MX") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountLabelAttributedText.assertValues(
        ["US$ 1,000"],
        "Reward minimum appears in project's currency, with a currency symbol."
      )
    }
  }

  func testMinimumLabel_NonUS_Project_NonUs_ProjectCurrency_US_User_Currency_US_UserLocation() {
    let project = Project.template
      |> Project.lens.country .~ .gb
      |> Project.lens.stats.projectCurrency .~ Project.Country.gb.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 0.5
    let reward = .template |> Reward.lens.minimum .~ 1_000

    withEnvironment(countryCode: "US") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountLabelAttributedText.assertValues(
        ["£1,000"],
        "Reward minimum always appears in the project's currency."
      )
    }
  }

  func testMinimumLabel_US_Project_NonUS_ProjectCurrency_US_User_Currency_US_UserLocation() {
    let project = Project.template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.gb.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 0.5
    let reward = .template |> Reward.lens.minimum .~ 1_000

    withEnvironment(countryCode: "US") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountLabelAttributedText.assertValues(
        ["£1,000"],
        "Reward minimum always appears in the project's currency not the project's country."
      )
    }
  }

  func testMinimumLabel_NonUs_Project_NonUS_Currency_US_UserCurrency_NonUS_UserLocation() {
    let project = Project.template
      |> Project.lens.country .~ .gb
      |> Project.lens.stats.projectCurrency .~ Project.Country.gb.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 0.5
    let reward = .template |> Reward.lens.minimum .~ 1_000

    withEnvironment(countryCode: "MX") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountLabelAttributedText.assertValues(
        ["£1,000"],
        "Reward minimum always appears in the project's currency."
      )
    }
  }

  func testMinimumLabel_NoReward_US_Project_US_ProjectCurrency_US_UserLocation() {
    let project = Project.template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode
    let reward = Reward.noReward

    withEnvironment(countryCode: "US") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountLabelAttributedText.assertValues(
        ["$1"],
        "No-reward min appears in the project's currency without a currency symbol"
      )
    }
  }

  func testMinimumLabel_NoReward_US_Project_US_ProjectCurrency_NonUS_UserLocation() {
    let project = Project.template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode
    let reward = Reward.noReward

    withEnvironment(countryCode: "MX") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountLabelAttributedText.assertValues(
        ["US$ 1"],
        "No-reward min appears in the project's currency with a currency symbol"
      )
    }
  }

  func testMinimumLabel_NoReward_NonUS_ProjectCurrency_US_ProjectCountry_US_UserLocation() {
    let project = Project.template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.mx.currencyCode
    let reward = Reward.noReward

    withEnvironment(countryCode: "US") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountLabelAttributedText.assertValues(
        ["MX$ 10"],
        """
        No-reward min always appears in the project's currency,
        with the amount depending on the project's currency's country
        """
      )
    }
  }

  func testMinimumLabel_NoReward_NonUS_ProjectCurrency_US_ProjectCountry_NonUS_UserLocation() {
    let project = Project.template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.mx.currencyCode
    let reward = Reward.noReward

    withEnvironment(countryCode: "CA") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountLabelAttributedText.assertValues(
        ["MX$ 10"],
        """
        No-reward min always appears in the project's currency,
        with the amount depending on the project's currency's country.
        """
      )
    }
  }

  // MARK: - Included Items

  func testItems() {
    let reward = .template
      |> Reward.lens.rewardsItems .~ [
        .template
          |> RewardsItem.lens.item .~ (
            .template
              |> Item.lens.name .~ "The thing"
          ),
        .template
          |> RewardsItem.lens.quantity .~ 1_000
          |> RewardsItem.lens.item .~ (
            .template
              |> Item.lens.name .~ "The other thing"
          )
      ]

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.includedItemsLabelAttributedText.assertValues(["•  The thing•  1,000 x The other thing"])
    self.includedItemsStackViewHidden.assertValues([false])
  }

  func testItemsContainerHidden_WithNoItems() {
    self.vm.configure(with: .init(
      project: .template,
      reward: .template |> Reward.lens.rewardsItems .~ [],
      context: .pledge,
      shippingRule: nil,
      selectedQuantities: [:]
    ))

    self.includedItemsStackViewHidden.assertValues([true])
  }

  func testRewardLocalPickup_WithNoLocation() {
    self.rewardLocationStackViewHidden.assertDidNotEmitValue()
    self.rewardLocationPickupLabelText.assertDidNotEmitValue()

    let reward = .template
      |> Reward.lens.localPickup .~ nil
      |> Reward.lens.shipping.preference .~ .local

    self.vm.configure(with: .init(
      project: .template,
      reward: reward,
      context: .pledge,
      shippingRule: nil,
      selectedQuantities: [:]
    ))

    self.rewardLocationStackViewHidden.assertValues([true])
    self.rewardLocationPickupLabelText.assertDidNotEmitValue()
  }

  func testRewardLocalPickup_WithLocation() {
    self.rewardLocationStackViewHidden.assertDidNotEmitValue()
    self.rewardLocationPickupLabelText.assertDidNotEmitValue()

    let reward = .template
      |> Reward.lens.localPickup .~ .brooklyn
      |> Reward.lens.shipping.preference .~ .local

    self.vm.configure(with: .init(
      project: .template,
      reward: reward,
      context: .pledge,
      shippingRule: nil,
      selectedQuantities: [:]
    ))

    self.rewardLocationStackViewHidden.assertValues([false])
    self.rewardLocationPickupLabelText.assertValue("Brooklyn, NY")
  }

  func testRewardLocalPickup_WithLocationAndNoShippingPreference() {
    self.rewardLocationStackViewHidden.assertDidNotEmitValue()
    self.rewardLocationPickupLabelText.assertDidNotEmitValue()

    let reward = .template
      |> Reward.lens.localPickup .~ .brooklyn
      |> Reward.lens.shipping.preference .~ Reward.Shipping.Preference.none

    self.vm.configure(with: .init(
      project: .template,
      reward: reward,
      context: .pledge,
      shippingRule: nil,
      selectedQuantities: [:]
    ))

    self.rewardLocationStackViewHidden.assertValues([true])
    self.rewardLocationPickupLabelText.assertValue("Brooklyn, NY")
  }

  // MARK: Description Label

  func testDescriptionLabel() {
    let project = Project.template
    let reward = Reward.template

    self.vm
      .configure(with: .init(
        project: project,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.descriptionLabelText.assertValues([reward.description])
  }

  // MARK: - Conversion Label

  func testConversionLabel_US_UserCurrency_US_Location_US_Project_US_ProjectCurrency_ConfiguredWithReward() {
    let project = .template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ "USD"
      |> Project.lens.stats.userCurrency .~ "USD"
    let reward = .template |> Reward.lens.minimum .~ 1_000

    withEnvironment(countryCode: "US") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountConversionLabelHidden.assertValues(
        [true],
        "US user with US currency preferences, viewing US project does not see conversion."
      )
      self.amountConversionLabelText.assertValueCount(0)
    }
  }

  func testConversionLabel_US_UserCurrency_US_Location_NonUS_Project_NonUS_ProjectCurrency_ConfiguredWithReward(
  ) {
    let project = .template
      |> Project.lens.country .~ .ca
      |> Project.lens.stats.projectCurrency .~ Project.Country.ca.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 2
    let reward = .template |> Reward.lens.minimum .~ 1

    withEnvironment(countryCode: "US") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountConversionLabelHidden.assertValues(
        [false],
        """
        US user with US currency preferences, viewing non-US project sees conversion.
        """
      )
      self.amountConversionLabelText.assertValues(["About $2"], "Conversion without a currency symbol")
    }
  }

  func testConversionLabel_US_Currency_NonUS_Location_NonUS_ProjectCurrency_ConfiguredWithReward() {
    let project = .template
      |> Project.lens.country .~ .ca
      |> Project.lens.stats.projectCurrency .~ Project.Country.ca.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 2
    let reward = .template |> Reward.lens.minimum .~ 1

    withEnvironment(countryCode: "MX") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountConversionLabelHidden.assertValues(
        [false],
        """
        User with US currency preferences, non-US location, viewing non-US project sees conversion.
        """
      )
      self.amountConversionLabelText.assertValues(["About US$ 2"], "Conversion label shows US symbol.")
    }
  }

  func testConversionLabel_US_Currency_NonUS_Location_NonUS_Project_NonUSProjectCurrency_ConversionRoundedUp(
  ) {
    let project = .template
      |> Project.lens.country .~ .mx
      |> Project.lens.stats.projectCurrency .~ Project.Country.mx.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 0.05
    let reward = .template |> Reward.lens.minimum .~ 10

    withEnvironment(countryCode: "CA") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountConversionLabelHidden.assertValues(
        [false],
        """
        User with US currency preferences, non-US location, viewing non-US project sees conversion rounded up.
        """
      )
      self.amountConversionLabelText.assertValues(["About US$ 1"], "Conversion label shows US symbol.")
    }
  }

  func testConversionLabel_US_Currency_NonUS_Location_NonUS_Project_NonUS_ProjectCurrency_ConversionRoundedUp(
  ) {
    let project = .template
      |> Project.lens.country .~ .hk
      |> Project.lens.stats.projectCurrency .~ Project.Country.mx.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 0.05
    let reward = .template |> Reward.lens.minimum .~ 10

    withEnvironment(countryCode: "CA") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountConversionLabelHidden.assertValues(
        [false],
        """
        User with US currency preferences, non-US location, viewing non-US project sees conversion rounded up.
        """
      )
      self.amountConversionLabelText.assertValues(["About US$ 1"], "Conversion label shows US symbol.")
    }
  }

  func testConversionLabel_Unknown_Location_US_Project_US_ProjectCurrency_ConfiguredWithReward_WithoutUserCurrency(
  ) {
    let project = .template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrency .~ nil
      |> Project.lens.stats.userCurrencyRate .~ nil
    let reward = .template |> Reward.lens.minimum .~ 1

    withEnvironment(countryCode: "XX") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountConversionLabelHidden.assertValues(
        [true],
        "Unknown-location, unknown-currency user viewing US project does not see conversion."
      )
    }
  }

  func testConversionLabel_Unknown_Location_NonUS_Project_NonUS_ProjectCurrency_ConfiguredWithReward_WithoutUserCurrency(
  ) {
    let project = .template
      |> Project.lens.country .~ .ca
      |> Project.lens.stats.projectCurrency .~ Project.Country.ca.currencyCode
      |> Project.lens.stats.userCurrency .~ nil
      |> Project.lens.stats.userCurrencyRate .~ nil
    let reward = .template
      |> Reward.lens.minimum .~ 2

    withEnvironment(countryCode: "XX") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountConversionLabelHidden.assertValues(
        [false],
        "Unknown-location, unknown-currency user viewing non-US project sees conversion to USD."
      )
      self.amountConversionLabelText.assertValues(
        ["About US$ 2"],
        "Conversion label shows convertedMinimum value."
      )
    }
  }

  func testConversionLabel_NonUS_Location_NonUS_Locale_US_Project_US_ProjectCurrency_ConfiguredWithReward() {
    let project = .template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.mx.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 2
    let reward = .template
      |> Reward.lens.minimum .~ 1

    withEnvironment(
      apiService: MockService(currency: "MXN"), countryCode: "MX"
    ) {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountConversionLabelHidden.assertValues(
        [false],
        "Mexican user viewing US project sees conversion."
      )
      self.amountConversionLabelText.assertValues(
        ["About MX$ 2"],
        "Conversion label shows convertedMinimum value."
      )
    }
  }

  func testConversionLabel_NonUS_Location_NonUS_Locale_US_Project_US_ProjectCurrency_ConfiguredWithReward_WithShippingRule(
  ) {
    let project = .template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.mx.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 2
    let reward = .template
      |> Reward.lens.minimum .~ 1
      |> Reward.lens.shipping.enabled .~ true

    withEnvironment(
      apiService: MockService(currency: "MXN"), countryCode: "MX"
    ) {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: .template,
          selectedQuantities: [:]
        ))

      self.amountConversionLabelHidden.assertValues(
        [false],
        "Mexican user viewing US project sees conversion."
      )
      self.amountConversionLabelText.assertValues(
        ["About MX$ 12"],
        "Conversion label shows convertedMinimum value including shipping amount."
      )
    }
  }

  func testConversionLabel_NonUS_Location_NonUS_Locale_US_Project_NonUS_ProjectCurrency_ConfiguredWithReward_WithShippingRule(
  ) {
    let project = .template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.es.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.mx.currencyCode
      |> Project.lens.stats.userCurrencyRate .~ 2
    let reward = .template
      |> Reward.lens.minimum .~ 1
      |> Reward.lens.shipping.enabled .~ true

    withEnvironment(
      apiService: MockService(currency: "MXN"), countryCode: "MX"
    ) {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: .template,
          selectedQuantities: [:]
        ))

      self.amountConversionLabelHidden.assertValues(
        [false],
        "Mexican user viewing US project sees conversion, even if project currency is different from project currency."
      )
      self.amountConversionLabelText.assertValues(
        ["About MX$ 12"],
        "Conversion label shows convertedMinimum value including shipping amount."
      )
    }
  }

  func testConversionLabel_NonUS_Location_US_UserCurrency_US_Project_US_ProjectCurrency_ConfiguredWithReward(
  ) {
    let project = .template
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode
      |> Project.lens.stats.userCurrency .~ Project.Country.us.currencyCode
    let reward = .template |> Reward.lens.minimum .~ 1_000

    withEnvironment(countryCode: "GB") {
      self.vm
        .configure(with: .init(
          project: project,
          reward: reward,
          context: .pledge,
          shippingRule: nil,
          selectedQuantities: [:]
        ))

      self.amountConversionLabelHidden.assertValues(
        [true],
        "Non-US user location with USD user preferences viewing US project does not see conversion."
      )
      self.amountConversionLabelText.assertValueCount(0)
    }
  }

  // MARK: - Pills

  func testPillsLimitedReward() {
    self.pillsViewHidden.assertValueCount(0)
    self.reloadPills.assertValueCount(0)

    let reward = Reward.postcards
      |> Reward.lens.limit .~ 100
      |> Reward.lens.remaining .~ 25

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.pillsViewHidden.assertValues([false])
    self.reloadPills.assertValues([
      ["25 left of 100"]
    ])
  }

  func testPillsLimitedReward_HasBackers() {
    self.pillsViewHidden.assertValueCount(0)
    self.reloadPills.assertValueCount(0)

    let reward = Reward.postcards
      |> Reward.lens.limit .~ 100
      |> Reward.lens.backersCount .~ 25
      |> Reward.lens.remaining .~ 25

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.pillsViewHidden.assertValues([false])
    self.reloadPills.assertValues([
      ["25 left of 100"]
    ])
  }

  func testPillsTimebasedReward_24hrs() {
    self.pillsViewHidden.assertValueCount(0)
    self.reloadPills.assertValueCount(0)

    let reward = Reward.postcards
      |> Reward.lens.limit .~ nil
      |> Reward.lens.backersCount .~ nil
      |> Reward.lens.remaining .~ nil
      |> Reward.lens.endsAt .~ (MockDate().timeIntervalSince1970 + 60.0 * 60.0 * 24.0)

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.pillsViewHidden.assertValues([false])
    self.reloadPills.assertValues([
      ["24 hrs left"]
    ])
  }

  func testPillsTimebasedReward_4days() {
    self.pillsViewHidden.assertValueCount(0)
    self.reloadPills.assertValueCount(0)

    let date = AppEnvironment.current.calendar.date(byAdding: DateComponents(day: 4), to: MockDate().date)

    let reward = Reward.postcards
      |> Reward.lens.limit .~ nil
      |> Reward.lens.backersCount .~ nil
      |> Reward.lens.remaining .~ nil
      |> Reward.lens.endsAt .~ date?.timeIntervalSince1970

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.pillsViewHidden.assertValues([false])
    self.reloadPills.assertValues([
      ["4 days left"]
    ])
  }

  func testPillsTimebasedAndLimitedReward() {
    self.pillsViewHidden.assertValueCount(0)
    self.reloadPills.assertValueCount(0)

    let date = AppEnvironment.current.calendar.date(byAdding: DateComponents(day: 4), to: MockDate().date)

    let reward = Reward.postcards
      |> Reward.lens.limit .~ 100
      |> Reward.lens.backersCount .~ nil
      |> Reward.lens.remaining .~ 75
      |> Reward.lens.endsAt .~ date?.timeIntervalSince1970

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.pillsViewHidden.assertValues([false])
    self.reloadPills.assertValues([
      ["4 days left", "75 left of 100"]
    ])
  }

  func testPillsTimebasedAndLimitedRewardLimitPerBacker() {
    self.pillsViewHidden.assertValueCount(0)
    self.reloadPills.assertValueCount(0)

    let date = AppEnvironment.current.calendar.date(byAdding: DateComponents(day: 4), to: MockDate().date)

    let reward = Reward.postcards
      |> Reward.lens.limit .~ 100
      |> Reward.lens.limitPerBacker .~ 2
      |> Reward.lens.backersCount .~ nil
      |> Reward.lens.remaining .~ 75
      |> Reward.lens.endsAt .~ date?.timeIntervalSince1970

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.pillsViewHidden.assertValues([false])
    self.reloadPills.assertValues([
      ["4 days left", "75 left of 100", "Limit 2"]
    ])
  }

  func testPillsTimebasedAndLimitedReward_Unavailable_NoBackers() {
    self.pillsViewHidden.assertValueCount(0)
    self.reloadPills.assertValueCount(0)

    let reward = Reward.postcards
      |> Reward.lens.limit .~ 100
      |> Reward.lens.backersCount .~ nil
      |> Reward.lens.remaining .~ 0
      |> Reward.lens.endsAt .~ (MockDate().date.timeIntervalSince1970 - 1)

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.pillsViewHidden.assertValues([true])
    self.reloadPills.assertValues([[]])
  }

  func testPillsNonLimitedReward() {
    self.pillsViewHidden.assertValueCount(0)
    self.reloadPills.assertValueCount(0)

    let reward = Reward.postcards
      |> Reward.lens.limit .~ nil
      |> Reward.lens.backersCount .~ nil
      |> Reward.lens.endsAt .~ nil

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.pillsViewHidden.assertValues([true])
    self.reloadPills.assertValues([[]])
  }

  func testPillsLimitedReward_LiveProject_HasBackers() {
    self.pillsViewHidden.assertValueCount(0)
    self.reloadPills.assertValueCount(0)

    let reward = Reward.postcards
      |> Reward.lens.limit .~ 100
      |> Reward.lens.remaining .~ 50
      |> Reward.lens.backersCount .~ 50

    let project = Project.template
      |> Project.lens.state .~ .live

    self.vm
      .configure(with: .init(
        project: project,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.pillsViewHidden.assertValues([false])
    self.reloadPills.assertValues([["50 left of 100"]])
  }

  func testAddButtonAndStepper() {
    self.addButtonHidden.assertDidNotEmitValue()
    self.quantityLabelText.assertDidNotEmitValue()
    self.stepperMaxValue.assertDidNotEmitValue()
    self.stepperStackViewHidden.assertDidNotEmitValue()
    self.stepperValue.assertDidNotEmitValue()

    let reward = Reward.template
      |> Reward.lens.limitPerBacker .~ 10

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.addButtonHidden.assertValues([false])
    self.quantityLabelText.assertValues(["0"])
    self.stepperMaxValue.assertValues([10])
    self.stepperStackViewHidden.assertValues([true])
    self.stepperValue.assertValues([0])

    self.vm.addButtonTapped()

    self.addButtonHidden.assertValues([false, true])
    self.quantityLabelText.assertValues(["0", "1"])
    self.stepperMaxValue.assertValues([10])
    self.stepperStackViewHidden.assertValues([true, false])
    self.stepperValue.assertValues([0, 1])

    self.vm.stepperValueChanged(0)

    self.addButtonHidden.assertValues([false, true, false])
    self.quantityLabelText.assertValues(["0", "1", "0"])
    self.stepperMaxValue.assertValues([10])
    self.stepperStackViewHidden.assertValues([true, false, true])
    self.stepperValue.assertValues([0, 1, 0])
  }

  func testNotifiyDelegateDidSelectQuantity_NoPreviousSelection() {
    self.notifiyDelegateDidSelectQuantityRewardId.assertDidNotEmitValue()
    self.notifiyDelegateDidSelectQuantityQuantity.assertDidNotEmitValue()
    self.quantityLabelText.assertDidNotEmitValue()

    let reward = Reward.template
      |> Reward.lens.limitPerBacker .~ 10

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.quantityLabelText.assertValues(["0"])
    self.notifiyDelegateDidSelectQuantityRewardId.assertDidNotEmitValue()
    self.notifiyDelegateDidSelectQuantityQuantity.assertDidNotEmitValue()

    self.vm.addButtonTapped()

    self.quantityLabelText.assertValues(["0", "1"])
    self.notifiyDelegateDidSelectQuantityRewardId.assertValues([1])
    self.notifiyDelegateDidSelectQuantityQuantity.assertValues([1])

    self.vm.stepperValueChanged(2)

    self.quantityLabelText.assertValues(["0", "1", "2"])
    self.notifiyDelegateDidSelectQuantityRewardId.assertValues([1, 1])
    self.notifiyDelegateDidSelectQuantityQuantity.assertValues([1, 2])
  }

  func testNotifiyDelegateDidSelectQuantity_HasPreviousSelection() {
    self.notifiyDelegateDidSelectQuantityRewardId.assertDidNotEmitValue()
    self.notifiyDelegateDidSelectQuantityQuantity.assertDidNotEmitValue()
    self.quantityLabelText.assertDidNotEmitValue()

    let reward = Reward.template
      |> Reward.lens.limitPerBacker .~ 10

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [reward.id: 5]
      ))

    self.quantityLabelText.assertValues(["5"])
    self.notifiyDelegateDidSelectQuantityRewardId.assertDidNotEmitValue()
    self.notifiyDelegateDidSelectQuantityQuantity.assertDidNotEmitValue()

    self.vm.stepperValueChanged(4)

    self.quantityLabelText.assertValues(["5", "4"])
    self.notifiyDelegateDidSelectQuantityRewardId.assertValues([1])
    self.notifiyDelegateDidSelectQuantityQuantity.assertValues([4])

    self.vm.stepperValueChanged(3)

    self.quantityLabelText.assertValues(["5", "4", "3"])
    self.notifiyDelegateDidSelectQuantityRewardId.assertValues([1, 1])
    self.notifiyDelegateDidSelectQuantityQuantity.assertValues([4, 3])
  }

  func testReusedCardReportsCurrentRewardAndDoesNotNotifyOnConfiguration() {
    let first = Reward.template |> Reward.lens.id .~ 123 |> Reward.lens.limitPerBacker .~ 10
    let second = Reward.template |> Reward.lens.id .~ 456 |> Reward.lens.limitPerBacker .~ 10
    self.vm.configure(with: .init(project: .template, reward: first, context: .pledge,
                                 shippingRule: nil, selectedQuantities: [123: 2]))
    self.vm.stepperValueChanged(3)
    self.vm.configure(with: .init(project: .template, reward: second, context: .pledge,
                                 shippingRule: nil, selectedQuantities: [456: 4]))
    self.notifiyDelegateDidSelectQuantityRewardId.assertValues([123])
    self.quantityLabelText.assertValues(["2", "3", "4"])
    self.vm.stepperValueChanged(5)
    self.notifiyDelegateDidSelectQuantityRewardId.assertValues([123, 456])
    self.notifiyDelegateDidSelectQuantityQuantity.assertValues([3, 5])
  }

  func testGenerateFeedback() {
    let reward = Reward.template
      |> Reward.lens.limitPerBacker .~ 10

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    self.generateSelectionFeedback.assertDidNotEmitValue()
    self.generateNotificationWarningFeedback.assertDidNotEmitValue()

    self.vm.stepperValueChanged(1)
    self.generateSelectionFeedback.assertValueCount(1)
    self.generateNotificationWarningFeedback.assertValueCount(0)

    self.vm.stepperValueChanged(5)
    self.generateSelectionFeedback.assertValueCount(2)
    self.generateNotificationWarningFeedback.assertValueCount(0)

    self.vm.stepperValueChanged(10)
    self.generateSelectionFeedback.assertValueCount(2)
    self.generateNotificationWarningFeedback.assertValueCount(1)

    self.vm.stepperValueChanged(4)
    self.generateSelectionFeedback.assertValueCount(3)
    self.generateNotificationWarningFeedback.assertValueCount(1)

    self.vm.stepperValueChanged(0)
    self.generateSelectionFeedback.assertValueCount(3)
    self.generateNotificationWarningFeedback.assertValueCount(2)

    self.vm
      .configure(with: .init(
        project: .template,
        reward: reward,
        context: .pledge,
        shippingRule: nil,
        selectedQuantities: [:]
      ))

    // Does not generate feedback when reconfigured for cell re-use.
    self.generateSelectionFeedback.assertValueCount(3)
    self.generateNotificationWarningFeedback.assertValueCount(2)
  }
}

private final class Recorder<Value> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertDidNotEmitValue(file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(self.values.isEmpty, file: file, line: line) }
  func assertValueCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(self.values.count, count, file: file, line: line) }
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) where Value: Equatable { XCTAssertEqual(self.values, expected, message, file: file, line: line) }
  func assertValue(_ expected: Value, file: StaticString = #filePath, line: UInt = #line) where Value: Equatable { XCTAssertEqual(self.values.last, expected, file: file, line: line) }
}
