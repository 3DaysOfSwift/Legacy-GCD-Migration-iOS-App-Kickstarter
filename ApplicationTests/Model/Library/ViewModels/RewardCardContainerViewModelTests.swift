@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class RewardCardContainerViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  fileprivate let vm = RewardCardContainerViewModel()

  private let pledgeButtonStyleType = Recorder<ButtonStyleType>()
  private let pledgeButtonEnabled = Recorder<Bool>()
  private let pledgeButtonHidden = Recorder<Bool>()
  private let pledgeButtonTitleText = Recorder<String?>()
  private let rewardSelected = Recorder<Int>()

  let availableHasAddOns = Reward.postcards
    |> Reward.lens.hasAddOns .~ true
    |> Reward.lens.isAvailable .~ true
  let availableLimitedReward = Reward.postcards
    |> Reward.lens.limit .~ 100
    |> Reward.lens.remaining .~ 25
    |> Reward.lens.endsAt .~ nil
    |> Reward.lens.isAvailable .~ true
  let availableTimebasedReward = Reward.postcards
    |> Reward.lens.limit .~ nil
    |> Reward.lens.remaining .~ nil
    |> Reward.lens.endsAt .~ (MockDate().timeIntervalSince1970 + 60.0 * 60.0 * 24.0)
    |> Reward.lens.isAvailable .~ true
  let availableLimitedTimebasedReward = Reward.postcards
    |> Reward.lens.limit .~ 100
    |> Reward.lens.remaining .~ 25
    |> Reward.lens.endsAt .~ (MockDate().timeIntervalSince1970 + 60.0 * 60.0 * 24.0)
    |> Reward.lens.isAvailable .~ true
  let availableNonLimitedReward = Reward.postcards
    |> Reward.lens.limit .~ nil
    |> Reward.lens.remaining .~ nil
    |> Reward.lens.endsAt .~ nil
    |> Reward.lens.isAvailable .~ true
  let unavailableLimitedReward = Reward.postcards
    |> Reward.lens.limit .~ 100
    |> Reward.lens.remaining .~ 0
    |> Reward.lens.endsAt .~ nil
    |> Reward.lens.isAvailable .~ false
  let unavailableTimebasedReward = Reward.postcards
    |> Reward.lens.limit .~ nil
    |> Reward.lens.remaining .~ nil
    |> Reward.lens.endsAt .~ (MockDate().date.timeIntervalSince1970 - 1)
  let unavailableLimitedTimebasedReward = Reward.postcards
    |> Reward.lens.limit .~ 100
    |> Reward.lens.remaining .~ 0
    |> Reward.lens.endsAt .~ (MockDate().date.timeIntervalSince1970 - 1)
  let availableLimitedUnavailableTimebasedReward = Reward.postcards
    |> Reward.lens.limit .~ 100
    |> Reward.lens.remaining .~ 25
    |> Reward.lens.endsAt .~ (MockDate().date.timeIntervalSince1970 - 1)

  private var allRewards: [Reward] {
    return [
      self.availableHasAddOns,
      self.availableLimitedReward,
      self.availableTimebasedReward,
      self.availableLimitedTimebasedReward,
      self.availableNonLimitedReward,
      self.unavailableLimitedReward,
      self.unavailableTimebasedReward,
      self.unavailableLimitedTimebasedReward,
      self.availableLimitedUnavailableTimebasedReward,
      Reward.noReward
    ]
  }

  override func setUp() async throws {
    try await super.setUp()

    self.vm.onDisplay = { [weak self] display in
      self?.pledgeButtonStyleType.record(display.style)
      self?.pledgeButtonEnabled.record(display.enabled)
      self?.pledgeButtonHidden.record(display.hidden)
      self?.pledgeButtonTitleText.record(display.title)
    }
    self.vm.onRewardSelected = { [weak self] in self?.rewardSelected.record($0) }
  }

  func testLive_BackedProject_BackedReward() {
    self.pledgeButtonStyleType.assertValueCount(0)
    self.pledgeButtonEnabled.assertValueCount(0)
    self.pledgeButtonHidden.assertValueCount(0)
    self.pledgeButtonTitleText.assertValueCount(0)

    for (index, reward) in self.allRewards.enumerated() {
      let project = Project.cosmicSurgery
        |> Project.lens.state .~ .live
        |> Project.lens.personalization.isBacking .~ true
        |> Project.lens.personalization.backing .~ (
          .template
            |> Backing.lens.reward .~ reward
            |> Backing.lens.rewardId .~ reward.id
            |> Backing.lens.shippingAmount .~ 10
            |> Backing.lens.amount .~ 700.0
        )

      self.vm.configureWith(data: RewardCardViewData(
        project: project,
        reward: reward,
        context: .pledge,
        currentShippingLocation: nil
      ))

      let emissionCount = index + 1

      self.pledgeButtonStyleType.assertValueCount(emissionCount)
      self.pledgeButtonEnabled.assertValueCount(emissionCount)
      self.pledgeButtonHidden.assertValueCount(emissionCount)
      self.pledgeButtonTitleText.assertValueCount(emissionCount)
    }

    self.pledgeButtonStyleType.assertValueCount(self.allRewards.count)
    self.pledgeButtonEnabled.assertValueCount(self.allRewards.count)
    self.pledgeButtonHidden.assertValueCount(self.allRewards.count)
    self.pledgeButtonTitleText.assertValueCount(self.allRewards.count)

    self.pledgeButtonStyleType.assertValues([
      .green, .green, .green, .green, .green, .green, .green, .green, .green, .green
    ])
    self.pledgeButtonEnabled.assertValues(
      [true, true, true, true, true, true, true, true, true, true]
    )
    self.pledgeButtonHidden.assertValues(
      [false, false, false, false, false, false, false, false, false, false]
    )
    self.pledgeButtonTitleText.assertValues([
      "Continue",
      "Continue",
      "Continue",
      "Continue",
      "Continue",
      "Continue",
      "Continue",
      "Continue",
      "Continue",
      "Continue"
    ])
  }

  func testLive_BackedProject_NonBackedReward() {
    self.pledgeButtonStyleType.assertValueCount(0)
    self.pledgeButtonEnabled.assertValueCount(0)
    self.pledgeButtonHidden.assertValueCount(0)
    self.pledgeButtonTitleText.assertValueCount(0)

    for (index, reward) in self.allRewards.enumerated() {
      let project = Project.cosmicSurgery
        |> Project.lens.state .~ .live
        |> Project.lens.personalization.isBacking .~ true
        |> Project.lens.personalization.backing .~ (
          .template
            |> Backing.lens.reward .~ Reward.otherReward
            |> Backing.lens.rewardId .~ Reward.otherReward.id
            |> Backing.lens.shippingAmount .~ 10
            |> Backing.lens.amount .~ 700.0
        )

      self.vm.configureWith(data: RewardCardViewData(
        project: project,
        reward: reward,
        context: .pledge,
        currentShippingLocation: nil
      ))

      let emissionCount = index + 1

      self.pledgeButtonStyleType.assertValueCount(emissionCount)
      self.pledgeButtonEnabled.assertValueCount(emissionCount)
      self.pledgeButtonHidden.assertValueCount(emissionCount)
      self.pledgeButtonTitleText.assertValueCount(emissionCount)
    }

    self.pledgeButtonStyleType.assertValueCount(self.allRewards.count)
    self.pledgeButtonEnabled.assertValueCount(self.allRewards.count)
    self.pledgeButtonHidden.assertValueCount(self.allRewards.count)
    self.pledgeButtonTitleText.assertValueCount(self.allRewards.count)

    self.pledgeButtonStyleType.assertValues(
      [.green, .green, .green, .green, .green, .green, .green, .green, .green, .green]
    )

    self.pledgeButtonEnabled.assertValues([true, true, true, true, true, false, false, false, false, true])
    self.pledgeButtonHidden.assertValues(
      [false, false, false, false, false, false, false, false, false, false]
    )
    self.pledgeButtonTitleText.assertValues([
      "Select",
      "Select",
      "Select",
      "Select",
      "Select",
      "No longer available",
      "No longer available",
      "No longer available",
      "No longer available",
      "Select"
    ])
  }

  func testLive_NonBackedProject_LoggedIn() {
    withEnvironment(currentUser: .template) {
      self.pledgeButtonStyleType.assertValueCount(0)
      self.pledgeButtonEnabled.assertValueCount(0)
      self.pledgeButtonHidden.assertValueCount(0)
      self.pledgeButtonTitleText.assertValueCount(0)

      for (index, reward) in self.allRewards.enumerated() {
        let project = Project.cosmicSurgery
          |> Project.lens.state .~ .live
          |> Project.lens.personalization.isBacking .~ false

        self.vm.configureWith(data: RewardCardViewData(
          project: project,
          reward: reward,
          context: .pledge,
          currentShippingLocation: nil
        ))

        let emissionCount = index + 1

        self.pledgeButtonStyleType.assertValueCount(emissionCount)
        self.pledgeButtonEnabled.assertValueCount(emissionCount)
        self.pledgeButtonHidden.assertValueCount(emissionCount)
        self.pledgeButtonTitleText.assertValueCount(emissionCount)
      }

      self.pledgeButtonStyleType.assertValueCount(self.allRewards.count)
      self.pledgeButtonEnabled.assertValueCount(self.allRewards.count)
      self.pledgeButtonHidden.assertValueCount(self.allRewards.count)
      self.pledgeButtonTitleText.assertValueCount(self.allRewards.count)

      self.pledgeButtonStyleType.assertValues(
        [.green, .green, .green, .green, .green, .green, .green, .green, .green, .green]
      )
      self.pledgeButtonEnabled.assertValues([true, true, true, true, true, false, false, false, false, true])
      self.pledgeButtonHidden.assertValues(
        [false, false, false, false, false, false, false, false, false, false]
      )
      self.pledgeButtonTitleText.assertValues([
        "Select",
        "Select",
        "Select",
        "Select",
        "Select",
        "No longer available",
        "No longer available",
        "No longer available",
        "No longer available",
        "Select"
      ])
    }
  }

  func testLive_NonBackedProject_LoggedOut() {
    withEnvironment(currentUser: nil) {
      self.pledgeButtonStyleType.assertValueCount(0)
      self.pledgeButtonEnabled.assertValueCount(0)
      self.pledgeButtonHidden.assertValueCount(0)
      self.pledgeButtonTitleText.assertValueCount(0)

      for (index, reward) in self.allRewards.enumerated() {
        let project = Project.cosmicSurgery
          |> Project.lens.state .~ .live
          |> Project.lens.personalization.isBacking .~ nil
          |> Project.lens.personalization.backing .~ nil

        self.vm.configureWith(data: RewardCardViewData(
          project: project,
          reward: reward,
          context: .pledge,
          currentShippingLocation: nil
        ))

        let emissionCount = index + 1

        self.pledgeButtonStyleType.assertValueCount(emissionCount)
        self.pledgeButtonEnabled.assertValueCount(emissionCount)
        self.pledgeButtonHidden.assertValueCount(emissionCount)
        self.pledgeButtonTitleText.assertValueCount(emissionCount)
      }

      self.pledgeButtonStyleType.assertValueCount(self.allRewards.count)
      self.pledgeButtonEnabled.assertValueCount(self.allRewards.count)
      self.pledgeButtonHidden.assertValueCount(self.allRewards.count)
      self.pledgeButtonTitleText.assertValueCount(self.allRewards.count)

      self.pledgeButtonStyleType.assertValues(
        [.green, .green, .green, .green, .green, .green, .green, .green, .green, .green]
      )
      self.pledgeButtonEnabled.assertValues([true, true, true, true, true, false, false, false, false, true])
      self.pledgeButtonHidden.assertValues(
        [false, false, false, false, false, false, false, false, false, false]
      )
      self.pledgeButtonTitleText.assertValues([
        "Select",
        "Select",
        "Select",
        "Select",
        "Select",
        "No longer available",
        "No longer available",
        "No longer available",
        "No longer available",
        "Select"
      ])
    }
  }

  func testNonLive_BackedProject_BackedReward() {
    self.pledgeButtonStyleType.assertValueCount(0)
    self.pledgeButtonEnabled.assertValueCount(0)
    self.pledgeButtonHidden.assertValueCount(0)
    self.pledgeButtonTitleText.assertValueCount(0)

    for (index, reward) in self.allRewards.enumerated() {
      let project = Project.cosmicSurgery
        |> Project.lens.state .~ .successful
        |> Project.lens.personalization.isBacking .~ true
        |> Project.lens.personalization.backing .~ (
          .template
            |> Backing.lens.reward .~ reward
            |> Backing.lens.rewardId .~ reward.id
            |> Backing.lens.shippingAmount .~ 10
            |> Backing.lens.amount .~ 700.0
        )

      self.vm.configureWith(data: RewardCardViewData(
        project: project,
        reward: reward,
        context: .pledge,
        currentShippingLocation: nil
      ))

      let emissionCount = index + 1

      self.pledgeButtonStyleType.assertValueCount(emissionCount)
      self.pledgeButtonEnabled.assertValueCount(emissionCount)
      self.pledgeButtonHidden.assertValueCount(emissionCount)
      self.pledgeButtonTitleText.assertValueCount(emissionCount)
    }

    self.pledgeButtonStyleType.assertValueCount(self.allRewards.count)
    self.pledgeButtonEnabled.assertValueCount(self.allRewards.count)
    self.pledgeButtonHidden.assertValueCount(self.allRewards.count)
    self.pledgeButtonTitleText.assertValueCount(self.allRewards.count)

    self.pledgeButtonStyleType.assertValues(
      [.black, .black, .black, .black, .black, .black, .black, .black, .black, .black]
    )
    self.pledgeButtonEnabled.assertValues(
      [false, false, false, false, false, false, false, false, false, false]
    )
    self.pledgeButtonHidden.assertValues(
      [false, false, false, false, false, false, false, false, false, false]
    )
    self.pledgeButtonTitleText.assertValues([
      "Selected",
      "Selected",
      "Selected",
      "Selected",
      "Selected",
      "Selected",
      "Selected",
      "Selected",
      "Selected",
      "Selected"
    ])
  }

  func testNonLive_BackedProject_NonBackedReward() {
    self.pledgeButtonStyleType.assertValueCount(0)
    self.pledgeButtonEnabled.assertValueCount(0)
    self.pledgeButtonHidden.assertValueCount(0)
    self.pledgeButtonTitleText.assertValueCount(0)

    for (index, reward) in self.allRewards.enumerated() {
      let project = Project.cosmicSurgery
        |> Project.lens.state .~ .successful
        |> Project.lens.personalization.isBacking .~ true
        |> Project.lens.personalization.backing .~ (
          .template
            |> Backing.lens.reward .~ Reward.otherReward
            |> Backing.lens.rewardId .~ Reward.otherReward.id
            |> Backing.lens.shippingAmount .~ 10
            |> Backing.lens.amount .~ 700.0
        )

      self.vm.configureWith(data: RewardCardViewData(
        project: project,
        reward: reward,
        context: .pledge,
        currentShippingLocation: nil
      ))

      let emissionCount = index + 1

      self.pledgeButtonStyleType.assertValueCount(emissionCount)
      self.pledgeButtonEnabled.assertValueCount(emissionCount)
      self.pledgeButtonHidden.assertValueCount(emissionCount)
      self.pledgeButtonTitleText.assertValueCount(emissionCount)
    }

    self.pledgeButtonStyleType.assertValueCount(self.allRewards.count)
    self.pledgeButtonEnabled.assertValueCount(self.allRewards.count)
    self.pledgeButtonHidden.assertValueCount(self.allRewards.count)
    self.pledgeButtonTitleText.assertValueCount(self.allRewards.count)

    self.pledgeButtonStyleType.assertValues([
      .none, .none, .none, .none, .none, .none, .none, .none, .none, .none
    ])
    self.pledgeButtonEnabled.assertValues(
      [false, false, false, false, false, false, false, false, false, false]
    )
    self.pledgeButtonHidden.assertValues([true, true, true, true, true, true, true, true, true, true])
    self.pledgeButtonTitleText.assertValues([nil, nil, nil, nil, nil, nil, nil, nil, nil, nil])
  }

  func testNonLive_NonBackedProject() {
    self.pledgeButtonStyleType.assertValueCount(0)
    self.pledgeButtonEnabled.assertValueCount(0)
    self.pledgeButtonHidden.assertValueCount(0)
    self.pledgeButtonTitleText.assertValueCount(0)

    for (index, reward) in self.allRewards.enumerated() {
      let project = Project.cosmicSurgery
        |> Project.lens.state .~ .successful
        |> Project.lens.personalization.isBacking .~ false

      self.vm.configureWith(data: RewardCardViewData(
        project: project,
        reward: reward,
        context: .pledge,
        currentShippingLocation: nil
      ))

      let emissionCount = index + 1

      self.pledgeButtonStyleType.assertValueCount(emissionCount)
      self.pledgeButtonEnabled.assertValueCount(emissionCount)
      self.pledgeButtonHidden.assertValueCount(emissionCount)
      self.pledgeButtonTitleText.assertValueCount(emissionCount)
    }

    self.pledgeButtonStyleType.assertValueCount(self.allRewards.count)
    self.pledgeButtonEnabled.assertValueCount(self.allRewards.count)
    self.pledgeButtonHidden.assertValueCount(self.allRewards.count)
    self.pledgeButtonTitleText.assertValueCount(self.allRewards.count)

    self.pledgeButtonStyleType.assertValues([
      .none, .none, .none, .none, .none, .none, .none, .none, .none, .none
    ])
    self.pledgeButtonEnabled.assertValues(
      [false, false, false, false, false, false, false, false, false, false]
    )
    self.pledgeButtonHidden.assertValues(
      [true, true, true, true, true, true, true, true, true, true]
    )
    self.pledgeButtonTitleText.assertValues(
      [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil]
    )
  }

  func testNonLive_BackedProject_BackedReward_Errored() {
    // only test reward states that we can get to
    let rewards = [
      availableLimitedReward,
      availableTimebasedReward,
      availableLimitedTimebasedReward,
      availableNonLimitedReward,
      Reward.noReward
    ]

    self.pledgeButtonStyleType.assertValueCount(0)
    self.pledgeButtonEnabled.assertValueCount(0)
    self.pledgeButtonHidden.assertValueCount(0)
    self.pledgeButtonTitleText.assertValueCount(0)

    for (index, reward) in rewards.enumerated() {
      let project = Project.cosmicSurgery
        |> Project.lens.state .~ .successful
        |> Project.lens.personalization.isBacking .~ true
        |> Project.lens.personalization.backing .~ (
          .template
            |> Backing.lens.reward .~ reward
            |> Backing.lens.rewardId .~ reward.id
            |> Backing.lens.shippingAmount .~ 10
            |> Backing.lens.amount .~ 700.0
            |> Backing.lens.status .~ .errored
        )

      self.vm.configureWith(data: RewardCardViewData(
        project: project,
        reward: reward,
        context: .pledge,
        currentShippingLocation: nil
      ))

      let emissionCount = index + 1

      self.pledgeButtonStyleType.assertValueCount(emissionCount)
      self.pledgeButtonEnabled.assertValueCount(emissionCount)
      self.pledgeButtonHidden.assertValueCount(emissionCount)
      self.pledgeButtonTitleText.assertValueCount(emissionCount)
    }

    self.pledgeButtonStyleType.assertValueCount(rewards.count)
    self.pledgeButtonEnabled.assertValueCount(rewards.count)
    self.pledgeButtonHidden.assertValueCount(rewards.count)
    self.pledgeButtonTitleText.assertValueCount(rewards.count)

    self.pledgeButtonStyleType.assertValues([.black, .black, .black, .black, .black])
    self.pledgeButtonEnabled.assertValues([false, false, false, false, false])
    self.pledgeButtonHidden.assertValues([false, false, false, false, false])
    self.pledgeButtonTitleText.assertValues([
      "Selected",
      "Selected",
      "Selected",
      "Selected",
      "Selected"
    ])
  }

  func testLive_IsCreator_LoggedIn() {
    let creator = User.projectCreator
      |> User.lens.id .~ 5
    withEnvironment(currentUser: creator) {
      self.pledgeButtonStyleType.assertValueCount(0)
      self.pledgeButtonEnabled.assertValueCount(0)
      self.pledgeButtonHidden.assertValueCount(0)
      self.pledgeButtonTitleText.assertValueCount(0)

      for (index, reward) in self.allRewards.enumerated() {
        let project = Project.cosmicSurgery
          |> Project.lens.creator .~ creator
          |> Project.lens.state .~ .live
          |> Project.lens.personalization.isBacking .~ false

        self.vm.configureWith(data: RewardCardViewData(
          project: project,
          reward: reward,
          context: .pledge,
          currentShippingLocation: nil
        ))

        let emissionCount = index + 1

        self.pledgeButtonStyleType.assertValueCount(emissionCount)
        self.pledgeButtonEnabled.assertValueCount(emissionCount)
        self.pledgeButtonHidden.assertValueCount(emissionCount)
        self.pledgeButtonTitleText.assertValueCount(emissionCount)
      }

      self.pledgeButtonStyleType.assertValueCount(self.allRewards.count)
      self.pledgeButtonEnabled.assertValueCount(self.allRewards.count)
      self.pledgeButtonHidden.assertValueCount(self.allRewards.count)
      self.pledgeButtonTitleText.assertValueCount(self.allRewards.count)

      self.pledgeButtonStyleType.assertValues(
        [.none, .none, .none, .none, .none, .none, .none, .none, .none, .none]
      )
      self.pledgeButtonEnabled.assertValues(
        [false, false, false, false, false, false, false, false, false, false]
      )
      self.pledgeButtonHidden.assertValues(
        [true, true, true, true, true, true, true, true, true, true]
      )
      self.pledgeButtonTitleText.assertValues([nil, nil, nil, nil, nil, nil, nil, nil, nil, nil])
    }
  }

  func testNonLive_IsCreator_LoggedIn() {
    let creator = User.projectCreator
      |> User.lens.id .~ 5

    withEnvironment(currentUser: creator) {
      self.pledgeButtonStyleType.assertValueCount(0)
      self.pledgeButtonEnabled.assertValueCount(0)
      self.pledgeButtonHidden.assertValueCount(0)
      self.pledgeButtonTitleText.assertValueCount(0)

      for (index, reward) in self.allRewards.enumerated() {
        let project = Project.cosmicSurgery
          |> Project.lens.creator .~ creator
          |> Project.lens.state .~ .successful
          |> Project.lens.personalization.isBacking .~ false

        self.vm.configureWith(data: RewardCardViewData(
          project: project,
          reward: reward,
          context: .pledge,
          currentShippingLocation: nil
        ))

        let emissionCount = index + 1

        self.pledgeButtonStyleType.assertValueCount(emissionCount)
        self.pledgeButtonEnabled.assertValueCount(emissionCount)
        self.pledgeButtonHidden.assertValueCount(emissionCount)
        self.pledgeButtonTitleText.assertValueCount(emissionCount)
      }

      self.pledgeButtonStyleType.assertValueCount(self.allRewards.count)
      self.pledgeButtonEnabled.assertValueCount(self.allRewards.count)
      self.pledgeButtonHidden.assertValueCount(self.allRewards.count)
      self.pledgeButtonTitleText.assertValueCount(self.allRewards.count)

      self.pledgeButtonStyleType.assertValues(
        [.none, .none, .none, .none, .none, .none, .none, .none, .none, .none]
      )
      self.pledgeButtonEnabled.assertValues(
        [false, false, false, false, false, false, false, false, false, false]
      )
      self.pledgeButtonHidden.assertValues(
        [true, true, true, true, true, true, true, true, true, true]
      )
      self.pledgeButtonTitleText.assertValues(
        [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil]
      )
    }
  }

  func testPledgeButtonTitle_RestrictedShipping_validLocation() {
    let shipsToUSAReward = Reward.shipsToUSAReward
      |> Reward.lens.endsAt .~ (MockDate().timeIntervalSince1970 + 60)

    let project = Project.template
      |> Project.lens.rewardData.rewards .~ [shipsToUSAReward]
      |> Project.lens.rewardData.addOns .~ nil

    let data = RewardCardViewData(
      project: project,
      reward: shipsToUSAReward,
      context: .pledge,
      currentShippingLocation: .usa
    )

    self.vm.configureWith(data: data)

    self.pledgeButtonEnabled.assertLastValue(true)
    self.pledgeButtonTitleText.assertLastValue("Select")
  }

  func testPledgeButtonTitle_RestrictedShipping_invalidLocation() {
    let shipsToUSAReward = Reward.shipsToUSAReward
      |> Reward.lens.endsAt .~ (MockDate().timeIntervalSince1970 + 60)

    let project = Project.template
      |> Project.lens.rewardData.rewards .~ [shipsToUSAReward]
      |> Project.lens.rewardData.addOns .~ nil

    let data = RewardCardViewData(
      project: project,
      reward: shipsToUSAReward,
      context: .pledge,
      currentShippingLocation: .australia
    )

    self.vm.configureWith(data: data)

    self.pledgeButtonEnabled.assertLastValue(false)
    self.pledgeButtonTitleText.assertLastValue("Not available in selected country")
  }

  func testPledgeButtonTitle_RestrictedShipping_invalidLocation_postCampaignPledging() {
    let shipsToUSAReward = Reward.shipsToUSAReward
      |> Reward.lens.endsAt .~ (MockDate().timeIntervalSince1970 + 60)

    let project = Project.template
      |> Project.lens.state .~ .successful
      |> Project.lens.isInPostCampaignPledgingPhase .~ true
      |> Project.lens.rewardData.rewards .~ [shipsToUSAReward]
      |> Project.lens.rewardData.addOns .~ nil

    let data = RewardCardViewData(
      project: project,
      reward: shipsToUSAReward,
      context: .pledge,
      currentShippingLocation: .australia
    )

    self.vm.configureWith(data: data)

    self.pledgeButtonEnabled.assertLastValue(false)
    self.pledgeButtonTitleText.assertLastValue("Not available in selected country")
  }

  func testPledgeButtonTitle_RestrictedShipping_invalidLocation_backingThisReward() {
    let shipsToUSAReward = Reward.shipsToUSAReward
      |> Reward.lens.endsAt .~ (MockDate().timeIntervalSince1970 + 60)

    let backing = Backing.template
      |> Backing.lens.rewardId .~ shipsToUSAReward.id
      |> Backing.lens.reward .~ shipsToUSAReward

    let project = Project.template
      |> Project.lens.state .~ .live
      |> Project.lens.personalization.backing .~ backing
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.rewardData.rewards .~ [shipsToUSAReward]
      |> Project.lens.rewardData.addOns .~ nil

    let data = RewardCardViewData(
      project: project,
      reward: shipsToUSAReward,
      context: .pledge,
      currentShippingLocation: .australia
    )

    self.vm.configureWith(data: data)

    self.pledgeButtonEnabled.assertLastValue(true)
    self.pledgeButtonTitleText.assertLastValue("Continue")
  }

  func testPledgeButtonTitle_RestrictedShipping_invalidLocation_backingAnotherReward() {
    let anotherReward = Reward.template
      |> Reward.lens.id .~ 1
    let shipsToUSAReward = Reward.shipsToUSAReward
      |> Reward.lens.id .~ 2
      |> Reward.lens.endsAt .~ (MockDate().timeIntervalSince1970 + 60)

    let backing = Backing.template
      |> Backing.lens.rewardId .~ anotherReward.id
      |> Backing.lens.reward .~ anotherReward

    let project = Project.template
      |> Project.lens.state .~ .live
      |> Project.lens.personalization.backing .~ backing
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.rewardData.rewards .~ [shipsToUSAReward, anotherReward]
      |> Project.lens.rewardData.addOns .~ nil

    let data = RewardCardViewData(
      project: project,
      reward: shipsToUSAReward,
      context: .pledge,
      currentShippingLocation: .australia
    )

    self.vm.configureWith(data: data)

    self.pledgeButtonEnabled.assertLastValue(false)
    self.pledgeButtonTitleText.assertLastValue("Not available in selected country")
  }

  func testPledgeButtonTitle_DigitalReward_noLocation() {
    let digitalReward = Reward.digitalReward
      |> Reward.lens.endsAt .~ (MockDate().timeIntervalSince1970 + 60)

    let project = Project.template
      |> Project.lens.rewardData.rewards .~ [digitalReward]
      |> Project.lens.rewardData.addOns .~ nil

    let data = RewardCardViewData(
      project: project,
      reward: digitalReward,
      context: .pledge,
      currentShippingLocation: nil
    )

    self.vm.configureWith(data: data)

    self.pledgeButtonEnabled.assertLastValue(true)
    self.pledgeButtonTitleText.assertLastValue("Select")
  }

  func testPledgeButtonTitle_RestrictedShipping_BackedReward_invalidLocation() {
    let shipsToUSAReward = Reward.shipsToUSAReward
      |> Reward.lens.endsAt .~ (MockDate().timeIntervalSince1970 + 60)
      |> Reward.lens.isAvailable .~ true

    let project = Project.template
      |> Project.lens.rewardData.rewards .~ [shipsToUSAReward]
      |> Project.lens.rewardData.addOns .~ nil
      |> Project.lens.personalization.backing .~ (
        .template
          |> Backing.lens.reward .~ shipsToUSAReward
          |> Backing.lens.rewardId .~ shipsToUSAReward.id
      )

    let data = RewardCardViewData(
      project: project,
      reward: shipsToUSAReward,
      context: .pledge,
      currentShippingLocation: .australia
    )

    self.vm.configureWith(data: data)

    self.pledgeButtonEnabled.assertLastValue(
      true,
      "If a reward is backed, you should always be able to select and edit that reward (to edit your add-ons and bonus), even if it is unavailable"
    )
    self.pledgeButtonTitleText.assertLastValue(
      "Continue",
      "If a reward is backed, you should always be able to select and edit that reward (to edit your add-ons and bonus), even if it is unavailable"
    )
  }

  func testPledgeButtonTapped() {
    self.vm.configureWith(data: RewardCardViewData(
      project: Project.template,
      reward: Reward.template,
      context: .pledge,
      currentShippingLocation: nil
    ))

    self.vm.pledgeButtonTapped()

    self.rewardSelected.assertValues([Reward.template.id])
  }
}

private final class Recorder<Value> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(self.values.count, count, file: file, line: line) }
  func assertValues(_ expected: [Value], file: StaticString = #filePath, line: UInt = #line) where Value: Equatable { XCTAssertEqual(self.values, expected, file: file, line: line) }
  func assertLastValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) where Value: Equatable { XCTAssertEqual(self.values.last, expected, message, file: file, line: line) }
}
