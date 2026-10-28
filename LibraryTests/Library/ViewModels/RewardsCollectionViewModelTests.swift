import Foundation
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@MainActor
final class RewardsCollectionViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testFailedCountryRefreshKeepsSuccessfulCardsAndTheirShippingContextThenRetries() async {
    let rewards = [Reward.noReward, Reward.shipsToUSAReward]
    let project = Project.template |> Project.lens.rewardData.rewards .~ rewards
    let locations = TestObserver<String?, Never>()
    let observation = self.vm.outputs.reloadDataWithValues
      .map { $0.last?.currentShippingLocation?.country }.observe(locations.observer)
    defer { observation?.dispose() }
    await withEnvironment(apiService: MockService(fetchProjectRewardsResult: .success(rewards))) {
      self.vm.configure(with: project, refTag: nil, context: .createPledge, secretRewardToken: nil)
      self.vm.viewDidLoad()
      self.vm.shippingLocationSelected(.usa)
      await self.vm.loadingTask?.value
      locations.assertValues(["US"])
      await withEnvironment(apiService: MockService(
        fetchProjectRewardsResult: .failure(.couldNotParseJSON)
      )) {
        self.vm.shippingLocationSelected(.australia)
        await self.vm.loadingTask?.value
        self.reloadDataWithValues.assertValues([rewards, rewards])
        locations.assertValues(["US", "US"], "A failed refresh must not relabel US cards as Australian")
      }
      self.vm.shippingLocationSelected(nil)
      await self.vm.loadingTask?.value
      locations.assertValues(["US", "US", nil])
    }
  }

  private let reloadDataWithValues = TestObserver<[Reward], Never>()
  private let scrollToRewardIndex = TestObserver<Int, Never>()
  private let goToCustomizeYourReward = TestObserver<PledgeViewData, Never>()
  private let showPlaceholderRewardCards = TestObserver<Int, Never>()

  private let vm = RewardsCollectionViewModel(rewardsFeature: RewardsFeature(
    makeProvider: { AsyncRewardsProvider(service: AppEnvironment.current.apiService) },
    sleep: { _ in try Task.checkCancellation() }
  ))

  override func setUp() {
    super.setUp()
    MainActor.assumeIsolated {
      self.vm.outputs.reloadDataWithValues.map { $0.map { $0.reward } }
        .observe(self.reloadDataWithValues.observer)

      self.vm.outputs.scrollToRewardIndexPath.map { $0.row }.observe(self.scrollToRewardIndex.observer)

      self.vm.outputs.goToCustomizeYourReward.observe(self.goToCustomizeYourReward.observer)

      self.vm.outputs.showPlaceholderRewardCards.observe(self.showPlaceholderRewardCards.observer)
    }
  }

  func testRewardsFiltered() async {
    let availableReward = Reward.template
      |> Reward.lens.isAvailable .~ true

    let notAvailableReward = Reward.template
      |> Reward.lens.isAvailable .~ false

    let notStartedYetReward = Reward.template
      |> Reward.lens.startsAt .~ NSDate.distantFuture.timeIntervalSince1970

    let onlyShipsToUSAReward = Reward.shipsToUSAReward

    let digitalReward = Reward.digitalReward
      |> Reward.lens.id .~ 1

    let localShippingReward = Reward.localShippingReward
      |> Reward.lens.id .~ 2

    let rewards = [
      Reward.noReward,
      Reward.secretRewardTemplate,
      availableReward,
      digitalReward,
      localShippingReward,
      notStartedYetReward,
      onlyShipsToUSAReward,
      notAvailableReward
    ]

    let testProject = Project.template
      |> Project.lens.rewardData.rewards .~ rewards

    let mockService = MockService(fetchProjectRewardsResult: .success(rewards))

    await withEnvironment(apiService: mockService) {
      self.vm.configure(with: testProject, refTag: nil, context: .createPledge, secretRewardToken: "34342")
      self.vm.viewDidLoad()

      self.reloadDataWithValues
        .assertDidNotEmitValue(
          "Shouldn't load rewards until a shipping location is selected "
        )

      self.vm.shippingLocationSelected(Location.australia)

      await self.vm.loadingTask?.value
      await self.scheduler.advance()

      self.reloadDataWithValues.assertLastValue([
        Reward.noReward,
        Reward.secretRewardTemplate,
        availableReward,
        digitalReward,
        localShippingReward,
        onlyShipsToUSAReward,
        notAvailableReward
      ], "Rewards that haven't started yet should be filtered from results")
    }
  }

  func test_scrollsToFirstSecretReward_whenSecretRewardTokenIsProvided() async {
    let availableReward = Reward.template
      |> Reward.lens.isAvailable .~ true
    let notAvailableReward = Reward.template
      |> Reward.lens.isAvailable .~ false

    let rewards = [
      Reward.noReward,
      Reward.secretRewardTemplate,
      availableReward,
      notAvailableReward
    ]

    let testProject = Project.template
      |> Project.lens.rewardData.rewards .~ rewards

    let mockService = MockService(fetchProjectRewardsResult: .success(rewards))

    await withEnvironment(apiService: mockService) {
      self.vm.configure(with: testProject, refTag: nil, context: .createPledge, secretRewardToken: "34342")
      self.vm.shippingLocationSelected(nil)

      self.vm.viewDidLoad()
      self.vm.viewDidLayoutSubviews()

      self.reloadDataWithValues.assertDidNotEmitValue("Shouldn't load data until rewards are fetched")
      self.scrollToRewardIndex
        .assertDidNotEmitValue("Shouldn't scroll to secret reward until rewards are fetched")

      await self.vm.loadingTask?.value
      await self.scheduler.advance()

      self.reloadDataWithValues.assertLastValue(rewards)
      self.scrollToRewardIndex.assertValues([1])
    }
  }

  func test_autoscrollsToBackedReward_whenProjectIsBacked() async {
    let availableReward = Reward.template
      |> Reward.lens.isAvailable .~ true
    let notAvailableReward = Reward.template
      |> Reward.lens.isAvailable .~ false

    let rewards = [
      Reward.noReward,
      Reward.secretRewardTemplate,
      availableReward,
      notAvailableReward
    ]

    let backing = Backing.template
      |> Backing.lens.amount .~ 22
      |> Backing.lens.reward .~ availableReward
      |> Backing.lens.rewardId .~ availableReward.id
      |> Backing.lens.paymentSource .~ Backing.PaymentSource.template

    let testProject = Project.template
      |> Project.lens.rewardData.rewards .~ rewards
      |> Project.lens.personalization.backing .~ backing

    let mockService = MockService(fetchProjectRewardsResult: .success(rewards))

    await withEnvironment(apiService: mockService) {
      self.vm.configure(with: testProject, refTag: nil, context: .createPledge, secretRewardToken: nil)

      self.vm.shippingLocationSelected(nil)

      self.vm.viewDidLoad()
      self.vm.viewDidLayoutSubviews()

      self.reloadDataWithValues.assertDidNotEmitValue("Shouldn't load data until rewards are fetched")
      self.scrollToRewardIndex
        .assertDidNotEmitValue("Shouldn't scroll to backed reward until rewards are fetched")

      await self.vm.loadingTask?.value
      await self.scheduler.advance()

      self.reloadDataWithValues.assertValues([rewards])
      self.scrollToRewardIndex.assertValues([2])
    }
  }

  func test_doesNotScroll_whenNoBackedRewardAndNoSecretRewardToken() async {
    let availableReward = Reward.template
      |> Reward.lens.isAvailable .~ true
    let notAvailableReward = Reward.template
      |> Reward.lens.isAvailable .~ false

    let rewards = [
      availableReward,
      Reward.noReward,
      notAvailableReward,
      Reward.secretRewardTemplate
    ]

    let testProject = Project.template
      |> Project.lens.rewardData.rewards .~ rewards

    let mockService = MockService(fetchProjectRewardsResult: .success(rewards))

    await withEnvironment(apiService: mockService) {
      self.vm.configure(with: testProject, refTag: nil, context: .createPledge, secretRewardToken: nil)
      self.vm.shippingLocationSelected(nil)

      self.vm.viewDidLoad()
      self.vm.viewDidLayoutSubviews()

      await self.vm.loadingTask?.value
      await self.scheduler.advance()

      self.reloadDataWithValues.assertValues([rewards])
      self.scrollToRewardIndex.assertDidNotEmitValue()
    }
  }

  func test_selectLocation_outputsShippingRule_forRewardWithShipping() async {
    let location1 = Location(
      country: "Country 1",
      displayableName: "Country 1",
      id: 1,
      localizedName: "Country 1",
      name: "Country 1"
    )
    let location2 = Location(
      country: "Country 2",
      displayableName: "Country 2",
      id: 2,
      localizedName: "Country 2",
      name: "Country 2"
    )

    let shippingRule1 = ShippingRule(
      cost: 10,
      id: 1,
      location: location1,
      estimatedMin: nil,
      estimatedMax: nil
    )
    let shippingRule2 = ShippingRule(
      cost: 72,
      id: 2,
      location: location2,
      estimatedMin: nil,
      estimatedMax: nil
    )

    let reward = Reward.template
      |> Reward.lens.isAvailable .~ true
      |> Reward.lens.shippingRulesExpanded .~ [shippingRule1, shippingRule2]
      |> Reward.lens.shipping .~ Reward.Shipping(
        enabled: true,
        location: nil,
        preference: .restricted,
        summary: "Restricted shipping",
        type: .multipleLocations
      )

    let rewards = [
      reward
    ]

    let testProject = Project.template
      |> Project.lens.rewardData.rewards .~ rewards

    let mockService = MockService(fetchProjectRewardsResult: .success(rewards))

    await withEnvironment(apiService: mockService) {
      self.vm.configure(with: testProject, refTag: nil, context: .createPledge, secretRewardToken: nil)
      self.vm.inputs.shippingLocationSelected(nil)

      self.vm.viewDidLoad()
      self.vm.viewDidLayoutSubviews()

      await self.vm.loadingTask?.value
      await self.scheduler.advance()
      self.reloadDataWithValues.assertDidEmitValue()
      self.goToCustomizeYourReward.assertDidNotEmitValue()

      self.vm.inputs.shippingLocationSelected(location2)
      self.vm.inputs.rewardSelected(with: reward.id)

      self.goToCustomizeYourReward.assertDidEmitValue()

      if let pledgeData = self.goToCustomizeYourReward.lastValue {
        XCTAssertEqual(
          pledgeData.selectedShippingRule,
          shippingRule2,
          "Pledge data should include shipping rule for location 2"
        )
      }
      // Location selection starts another read. Finish it before releasing its fixture.
      await self.vm.loadingTask?.value
    }
  }

  func test_selectLocation_outputsNilShippingRule_forRewardWithoutShipping() async {
    let shippingRule1 = ShippingRule(
      cost: 10,
      id: 1,
      location: Location.usa,
      estimatedMin: nil,
      estimatedMax: nil
    )

    let physicalReward = Reward.template
      |> Reward.lens.title .~ "Physical Reward"
      |> Reward.lens.id .~ 1
      |> Reward.lens.isAvailable .~ true
      |> Reward.lens.shippingRulesExpanded .~ [
        shippingRule1
      ]
      |> Reward.lens.shipping .~ Reward.Shipping(
        enabled: true,
        location: nil,
        preference: .restricted,
        summary: "Physical reward",
        type: .singleLocation
      )

    let digitalReward = Reward.digitalReward
      |> Reward.lens.id .~ 2

    let rewards = [
      physicalReward,
      digitalReward
    ]

    let testProject = Project.template
      |> Project.lens.rewardData.rewards .~ rewards

    let mockService = MockService(fetchProjectRewardsResult: .success(rewards))

    await withEnvironment(apiService: mockService) {
      self.vm.configure(with: testProject, refTag: nil, context: .createPledge, secretRewardToken: nil)
      self.vm.inputs.shippingLocationSelected(nil)

      self.vm.viewDidLoad()
      self.vm.viewDidLayoutSubviews()

      await self.vm.loadingTask?.value
      await self.scheduler.advance()
      self.reloadDataWithValues.assertDidEmitValue()

      self.vm.inputs.shippingLocationSelected(Location.usa)

      self.vm.inputs.rewardSelected(with: digitalReward.id)
      self.goToCustomizeYourReward.assertDidEmitValue()

      if let pledgeData = self.goToCustomizeYourReward.lastValue {
        XCTAssertEqual(
          pledgeData.selectedShippingRule,
          nil,
          "Pledge data should have no shipping rule, because the reward is digital"
        )
      }
      await self.vm.loadingTask?.value
    }
  }

  func test_selectLocation_outputsNilShippingRule_forProjectWithNoShippableRewards() async {
    let noReward = Reward.noReward
    let digitalReward = Reward.digitalReward

    let localShippingReward = Reward.localShippingReward
      |> Reward.lens.id .~ 2

    let rewards = [
      noReward,
      digitalReward,
      localShippingReward
    ]

    let testProject = Project.template
      |> Project.lens.rewardData.rewards .~ rewards

    let mockService = MockService(fetchProjectRewardsResult: .success(rewards))

    await withEnvironment(apiService: mockService) {
      self.vm.configure(with: testProject, refTag: nil, context: .createPledge, secretRewardToken: nil)
      // If there are no shippable rewards, the location element will be hidden.
      // The shipping location view will output `nil` immediately if there are no shippable rewards.
      self.vm.inputs.shippingLocationSelected(nil)

      self.vm.viewDidLoad()
      self.vm.viewDidLayoutSubviews()

      await self.vm.loadingTask?.value
      await self.scheduler.advance()
      self.reloadDataWithValues.assertDidEmitValue()

      self.vm.inputs.rewardSelected(with: localShippingReward.id)

      self.goToCustomizeYourReward.assertDidEmitValue()

      if let pledgeData = self.goToCustomizeYourReward.lastValue {
        XCTAssertEqual(
          pledgeData.selectedShippingRule,
          nil,
          "Pledge data should have no shipping rule, because the reward is local."
        )
      }
    }
  }

  func test_projectWithShippableRewards_showsLoadingState_whileRewardsLoad() async {
    let onlyShipsToUSAReward = Reward.shipsToUSAReward

    let rewards = [
      Reward.noReward,
      onlyShipsToUSAReward
    ]

    let project = Project.template
      |> Project.lens.rewardData.rewards .~ rewards

    let mockService = MockService(fetchProjectRewardsResult: .success(rewards))

    await withEnvironment(apiService: mockService) {
      // The initial state of the page
      self.vm.configure(with: project, refTag: nil, context: .createPledge, secretRewardToken: nil)
      self.vm.viewDidLoad()

      self.reloadDataWithValues.assertDidNotEmitValue()
      self.showPlaceholderRewardCards.assertValueCount(
        1,
        "Should show loading placeholder rewards until location is selected"
      )
      self.showPlaceholderRewardCards.assertLastValue(2, "Should show 2 loading cards")

      // PledgeShippingLocationViewModel finishes loading and outputs the actual selected shipping location
      self.vm.shippingLocationSelected(.usa)
      self.reloadDataWithValues.assertDidNotEmitValue("Should still be loading")
      self.showPlaceholderRewardCards.assertValueCount(1, "Should still be loading")

      // Wait for the network fetch
      await self.vm.loadingTask?.value
      await self.scheduler.advance()
      self.reloadDataWithValues.assertValueCount(
        1,
        "Selecting shipping location should fetch and load cards, with new shipping location"
      )
      self.showPlaceholderRewardCards.assertValueCount(1)

      // The user picks a new shipping location from the dropdown.
      // PledgeShippingLocationViewModel outputs the new selected shipping location.
      self.vm.shippingLocationSelected(Location.australia)
      self.showPlaceholderRewardCards.assertValueCount(
        2,
        "Changing selected shipping location should cause loading screen to appear again"
      )
      self.reloadDataWithValues.assertValueCount(1)

      // Wait for a fetch to load the new rewards
      await self.vm.loadingTask?.value
      await self.scheduler.advance()
      self.reloadDataWithValues.assertValueCount(
        2,
        "Changing selected shipping location should re-fetch new cards"
      )
      self.showPlaceholderRewardCards.assertValueCount(2, "Done loading")
    }
  }

  func test_projectWithNoShippableRewards_showsLoadingState_andFetchesRewards() async {
    let digitalReward = Reward.digitalReward

    let rewards = [
      Reward.noReward,
      digitalReward
    ]

    let project = Project.template
      |> Project.lens.rewardData.rewards .~ rewards

    let mockService = MockService(fetchProjectRewardsResult: .success(rewards))

    await withEnvironment(apiService: mockService) {
      self.vm.configure(with: project, refTag: nil, context: .createPledge, secretRewardToken: nil)
      self.vm.viewDidLoad()

      self.reloadDataWithValues.assertDidNotEmitValue()
      self.showPlaceholderRewardCards.assertValueCount(
        1,
        "Should show loading placeholder until rewards have loaded"
      )
      self.showPlaceholderRewardCards.assertLastValue(2, "Should show 2 loading cards")

      // PledgeShippingLocationViewModel outputs a nil selected location
      self.vm.inputs.shippingLocationSelected(nil)
      self.reloadDataWithValues.assertDidNotEmitValue("Should still be loading")
      self.showPlaceholderRewardCards.assertValueCount(1, "Should still be loading")

      // Wait for a network fetch to load the rewards
      await self.vm.loadingTask?.value
      await self.scheduler.advance()
      self.reloadDataWithValues.assertLastValue(rewards, "Should have fetched rewards")
      self.showPlaceholderRewardCards.assertValueCount(1, "Should no longer be loading")
    }
  }
}
