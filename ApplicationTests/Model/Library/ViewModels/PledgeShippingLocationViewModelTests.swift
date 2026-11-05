@testable import Kickstarter_iOS
import Foundation
import GraphAPI
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class PledgeShippingLocationViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = PledgeShippingLocationViewModel(rewardsFeature: RewardsFeature(sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
    makeProvider: { AsyncRewardsProvider(service: AppEnvironment.current.apiService) },
    sleep: { _ in try Task.checkCancellation() }
  ), dismissDelay: { try Task.checkCancellation() })

  private let adaptableStackViewIsHidden = ShippingRecording<Bool>()
  private let dismissShippingLocations = ShippingRecording<Void>()
  private let presentShippingLocationsAllLocations = ShippingRecording<[Location]>()
  private let presentShippingLocationsSelectedLocation = ShippingRecording<Location>()
  private let notifyDelegateOfSelectedShippingLocation = ShippingRecording<Location?>()
  private let shimmerLoadingViewIsHidden = ShippingRecording<Bool>()
  private let shippingLocationButtonTitle = ShippingRecording<String>()
  private let shippingRulesError = ShippingRecording<String>()
  private let shippingLocationViewHidden = ShippingRecording<Bool>()

  override func setUp() async throws {
    try await super.setUp()
    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .visibility(hidden): self.shippingLocationViewHidden.append(hidden)
      case let .loading(loading):
        self.adaptableStackViewIsHidden.append(loading)
        self.shimmerLoadingViewIsHidden.append(!loading)
      case let .selected(location):
        self.notifyDelegateOfSelectedShippingLocation.append(location)
        if let location { self.shippingLocationButtonTitle.append(location.localizedName) }
      case let .present(locations, location):
        self.presentShippingLocationsAllLocations.append(locations)
        self.presentShippingLocationsSelectedLocation.append(location)
      case .dismiss: self.dismissShippingLocations.append(())
      case .error: self.shippingRulesError.append(Strings.We_were_unable_to_load_the_shipping_destinations())
      }
    }
  }

  func testDefaultShippingRule_ProjectCountryEqualsProjectCurrencyCountry_US() async {
    let mockService = MockService(fetchGraphQLResponses: [
      (ShippableLocationsForProjectQuery.self, threeShippableCountries)
    ])

    let reward = Reward.shipsToUSAReward

    let project = Project.template
      |> Project.lens.rewardData.rewards .~ [reward]

    await withEnvironment(apiService: mockService, countryCode: "US") {
      self.vm.configureWith(data: PledgeShippingLocationViewData(withProject: project))
      self.vm.viewDidLoad()

      self.adaptableStackViewIsHidden.assertValues([true])
      self.shimmerLoadingViewIsHidden.assertValues([false])
      self.shippingLocationViewHidden.assertValues([false])
      self.notifyDelegateOfSelectedShippingLocation.assertDidNotEmitValue()
      self.shippingLocationButtonTitle.assertValues([])

      await self.vm.loadingTask?.value


      self.adaptableStackViewIsHidden.assertValues([true, false])
      self.shimmerLoadingViewIsHidden.assertValues([false, true])
      self.shippingLocationViewHidden.assertValues([false])
      self.notifyDelegateOfSelectedShippingLocation.assertValues(
        [Location.usa],
        "Because the user has an environment with a US country code, their default location should be the USA."
      )
      self.shippingLocationButtonTitle.assertValues(["United States"])
      self.shippingRulesError.assertDidNotEmitValue()
    }
  }

  func testDefaultShippingRule_US_ProjectCountry_NonUSProjectCurrencyCountry_US_UserLocation() async {
    let mockService = MockService(fetchGraphQLResponses: [
      (ShippableLocationsForProjectQuery.self, threeShippableCountries)
    ])

    let reward = Reward.shipsToUSAReward

    let projectRewards = [reward]

    let project = Project.template
      |> Project.lens.stats.projectCurrency .~ Project.Country.mx.currencyCode
      |> Project.lens.country .~ Project.Country.us
      |> Project.lens.rewardData.rewards .~ projectRewards

    await withEnvironment(apiService: mockService, countryCode: "US") {
      self.vm.configureWith(data: PledgeShippingLocationViewData(withProject: project))

      self.vm.viewDidLoad()

      self.adaptableStackViewIsHidden.assertValues([true])
      self.shimmerLoadingViewIsHidden.assertValues([false])
      self.shippingLocationViewHidden.assertValues([false])
      self.notifyDelegateOfSelectedShippingLocation.assertDidNotEmitValue()
      self.shippingLocationButtonTitle.assertValues([])

      await self.vm.loadingTask?.value


      self.adaptableStackViewIsHidden.assertValues([true, false])
      self.shimmerLoadingViewIsHidden.assertValues([false, true])
      self.shippingLocationViewHidden.assertValues([false])
      self.notifyDelegateOfSelectedShippingLocation.assertValues(
        [Location.usa],
        "Because the user has an environment with a US country code, their default location should be the USA."
      )
      self.shippingLocationButtonTitle.assertValues(["United States"])
      self.shippingRulesError.assertDidNotEmitValue()
    }
  }

  func testDefaultShippingRule_ProjectCountryEqualsProjectCurrencyCountry_US_DefaultsToPreselected() async {
    let mockService = MockService(fetchGraphQLResponses: [
      (ShippableLocationsForProjectQuery.self, threeShippableCountries)
    ])

    let reward = Reward.shipsToAustraliaReward

    let project = Project.template
      |> Project.lens.rewardData.rewards .~ [reward]
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.personalization.backing .~ (
        Backing.template
          |> Backing.lens.locationId .~ Location.australia.id
      )

    await withEnvironment(apiService: mockService, countryCode: "US") {
      self.vm.configureWith(data: PledgeShippingLocationViewData(withProject: project))
      self.vm.viewDidLoad()

      self.adaptableStackViewIsHidden.assertValues([true])
      self.shimmerLoadingViewIsHidden.assertValues([false])
      self.shippingLocationViewHidden.assertValues([false])
      self.notifyDelegateOfSelectedShippingLocation.assertDidNotEmitValue()
      self.shippingLocationButtonTitle.assertValues([])

      await self.vm.loadingTask?.value


      self.adaptableStackViewIsHidden.assertValues([true, false])
      self.shimmerLoadingViewIsHidden.assertValues([false, true])
      self.shippingLocationViewHidden.assertValues([false])
      self.notifyDelegateOfSelectedShippingLocation.assertValues(
        [Location.australia],
        "Because the project has a backing in Australia, the selected shipping location should be Australia."
      )
      self.shippingLocationButtonTitle.assertValues(["Australia"])
      self.shippingRulesError.assertDidNotEmitValue()
    }
  }

  func testDefaultShippingRule_ProjectHasNoShippableRewards_DefaultsToNil() async {
    let reward = Reward.digitalReward

    let project = Project.template
      |> Project.lens.rewardData.rewards .~ [reward]

    // Note that this test has no mockService.
    // We shouldn't hit the network if the project has no shippable rewards.
    await withEnvironment(countryCode: "US") {
      self.vm.configureWith(data: PledgeShippingLocationViewData(withProject: project))
      self.vm.viewDidLoad()

      self.adaptableStackViewIsHidden.assertValues([true])
      self.shimmerLoadingViewIsHidden.assertValues([false])
      self.shippingLocationViewHidden.assertValues(
        [true],
        "Shipping location view should be hidden if project has no shippable rewards"
      )
      self.notifyDelegateOfSelectedShippingLocation.assertDidNotEmitValue()
      self.shippingLocationButtonTitle.assertValues([])

      await self.vm.loadingTask?.value


      self.adaptableStackViewIsHidden.assertValues([true, false])
      self.shimmerLoadingViewIsHidden.assertValues([false, true])
      self.shippingLocationViewHidden.assertValues(
        [true],
        "Shipping location view should be hidden if project has no shippable rewards"
      )
      self.notifyDelegateOfSelectedShippingLocation.assertValues(
        [nil],
        "Because the project has no shippable rewards, the default shipping location should be nil."
      )
      self.shippingLocationButtonTitle.assertDidNotEmitValue()
      self.shippingRulesError.assertDidNotEmitValue()
    }
  }

  func testShippingRulesSelection() async {
    let mockService = MockService(fetchGraphQLResponses: [
      (ShippableLocationsForProjectQuery.self, threeShippableCountries)
    ])
    let reward = Reward.shipsToUSAReward

    let project = Project.template
      |> Project.lens.rewardData.rewards .~ [reward]

    await withEnvironment(apiService: mockService, countryCode: "US") {
      self.vm.configureWith(data: PledgeShippingLocationViewData(withProject: project))
      self.vm.viewDidLoad()

      self.notifyDelegateOfSelectedShippingLocation.assertDidNotEmitValue()

      await self.vm.loadingTask?.value


      self.notifyDelegateOfSelectedShippingLocation.assertValues([Location.usa])

      self.vm.shippingLocationButtonTapped()

      self.dismissShippingLocations.assertDidNotEmitValue()
      self.presentShippingLocationsAllLocations.assertValues([[
        Location.australia,
        Location.canada,
        Location.usa
      ]])
      self.presentShippingLocationsSelectedLocation.assertValues([Location.usa])

      self.vm.shippingLocationUpdated(to: Location.australia)

      await self.vm.dismissTask?.value

      self.dismissShippingLocations.assertValueCount(1)
      self.notifyDelegateOfSelectedShippingLocation.assertValues([
        Location.usa,
        Location.australia
      ])
    }
  }

  func testShippingRulesCancelation() async {
    let mockService = MockService(fetchGraphQLResponses: [
      (ShippableLocationsForProjectQuery.self, threeShippableCountries)
    ])

    let reward = Reward.template
      |> Reward.lens.shipping.enabled .~ true

    let project = Project.template
      |> Project.lens.rewardData.rewards .~ [reward]

    await withEnvironment(apiService: mockService, countryCode: "US") {
      self.vm.configureWith(data: PledgeShippingLocationViewData(withProject: project))
      self.vm.viewDidLoad()

      let defaultShippingLocation = Location.usa

      self.notifyDelegateOfSelectedShippingLocation.assertDidNotEmitValue()

      await self.vm.loadingTask?.value


      self.notifyDelegateOfSelectedShippingLocation.assertValues([defaultShippingLocation])

      self.vm.shippingLocationButtonTapped()

      self.presentShippingLocationsAllLocations.assertValues([shippingLocations])
      self.presentShippingLocationsSelectedLocation.assertValues([defaultShippingLocation])

      self.dismissShippingLocations.assertDidNotEmitValue()
      self.vm.shippingLocationCancelButtonTapped()
      self.dismissShippingLocations.assertValueCount(1)
    }
  }

  func testShippingRulesError_ProjectCountryEqualsProjectCurrencyCountry_US() async {
    let reward = Reward.template
      |> Reward.lens.shipping.enabled .~ true

    let project = Project.template
      |> Project.lens.rewardData.rewards .~ [reward]

    // Leaving the mock unimplemented gives us an ErrorEnvelope, which is what we want to test
    await withEnvironment {
      self.vm.configureWith(data: PledgeShippingLocationViewData(withProject: project))
      self.vm.viewDidLoad()

      self.shippingRulesError.assertValues([])

      await self.vm.loadingTask?.value


      self.adaptableStackViewIsHidden.assertValues([true, false])
      self.shimmerLoadingViewIsHidden.assertValues([false, true])
      self.notifyDelegateOfSelectedShippingLocation.assertDidNotEmitValue()
      self.shippingLocationButtonTitle.assertValues([])
      self.shippingRulesError.assertValues([Strings.We_were_unable_to_load_the_shipping_destinations()])
    }
  }

  func testShippingLocationFromBackingIsDefault_ProjectCountryEqualsProjectCurrencyCountry_US() async {
    let mockService = MockService(fetchGraphQLResponses: [
      (ShippableLocationsForProjectQuery.self, threeShippableCountries)
    ])

    let reward = Reward.template
      |> Reward.lens.shipping.enabled .~ true

    let projectRewards = [reward]

    let project = Project.template
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.personalization.backing .~ (
        .template
          |> Backing.lens.reward .~ Reward.postcards
          |> Backing.lens.rewardId .~ Reward.postcards.id
          |> Backing.lens.shippingAmount .~ 10
          |> Backing.lens.amount .~ 700.0
          |> Backing.lens.locationId .~ Location.canada.id
          |> Backing.lens.locationName .~ Location.canada.name
      )
      |> Project.lens.rewardData.rewards .~ projectRewards

    await withEnvironment(apiService: mockService, countryCode: "US") {
      self.vm.configureWith(data: PledgeShippingLocationViewData(withProject: project))
      self.vm.viewDidLoad()

      self.adaptableStackViewIsHidden.assertValues([true])
      self.shimmerLoadingViewIsHidden.assertValues([false])
      self.notifyDelegateOfSelectedShippingLocation.assertDidNotEmitValue()
      self.shippingLocationButtonTitle.assertValues([])

      await self.vm.loadingTask?.value


      self.adaptableStackViewIsHidden.assertValues([true, false])
      self.shimmerLoadingViewIsHidden.assertValues([false, true])
      self.notifyDelegateOfSelectedShippingLocation.assertValues(
        [Location.canada],
        "Because the backing was made with the location Canada, the selected shipping location should default to Canada."
      )
      self.shippingLocationButtonTitle.assertValues(["Canada"])
      self.shippingRulesError.assertDidNotEmitValue()


    }
  }

  func testShippingLocationFromBackingIsDefault_ProjectCountryEqualsProjectCurrencyCountry_US_NewRewardDoesNotHaveSelectedRule(
  ) async {
    let shippingDataWithoutCanada = GraphAPI.ShippableLocationsForProjectQuery.Data(
      project: GraphAPI.ShippableLocationsForProjectQuery.Data.Project(
        shippableCountriesExpanded: [
          GraphLocation(
            country: "US",
            countryName: "United States",
            displayableName: "United States",
            id: encodeToBase64("Location-5"),
            name: "United States"
          ),
          GraphLocation(
            country: "AU",
            countryName: "Australia",
            displayableName: "Australia",
            id: encodeToBase64("Location-8"),
            name: "Australia"
          )
        ]
      )
    )

    let mockService = MockService(fetchGraphQLResponses: [
      (ShippableLocationsForProjectQuery.self, shippingDataWithoutCanada)
    ])

    let reward = Reward.template
      |> Reward.lens.shipping.enabled .~ true

    let projectRewards = [reward]

    let project = Project.template
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.personalization.backing .~ (
        .template
          |> Backing.lens.reward .~ Reward.postcards
          |> Backing.lens.rewardId .~ Reward.postcards.id
          |> Backing.lens.shippingAmount .~ 10
          |> Backing.lens.amount .~ 700.0
          |> Backing.lens.locationId .~ Location.canada.id
          |> Backing.lens.locationName .~ Location.canada.name
      )
      |> Project.lens.rewardData.rewards .~ projectRewards

    await withEnvironment(apiService: mockService, countryCode: "US") {
      self.vm.configureWith(data: PledgeShippingLocationViewData(withProject: project))
      self.vm.viewDidLoad()

      self.adaptableStackViewIsHidden.assertValues([true])
      self.shimmerLoadingViewIsHidden.assertValues([false])
      self.notifyDelegateOfSelectedShippingLocation.assertDidNotEmitValue()
      self.shippingLocationButtonTitle.assertValues([])

      await self.vm.loadingTask?.value


      self.adaptableStackViewIsHidden.assertValues([true, false])
      self.shimmerLoadingViewIsHidden.assertValues([false, true])
      self.notifyDelegateOfSelectedShippingLocation.assertValues(
        [Location.usa],
        "Because Canada is no longer a valid shipping destination, even though the backing was sent to Canada, the shipping location should default to the user's default location."
      )
      self.shippingLocationButtonTitle.assertValues(["United States"])
      self.shippingRulesError.assertDidNotEmitValue()
    }
  }
}

private let shippingLocations: [Location] = Location.locations(from: threeShippableCountries)

private typealias GraphLocation = GraphAPI.ShippableLocationsForProjectQuery.Data.Project
  .ShippableCountriesExpanded

private let threeShippableCountries = GraphAPI.ShippableLocationsForProjectQuery.Data(
  project: GraphAPI.ShippableLocationsForProjectQuery.Data.Project(
    shippableCountriesExpanded: [
      GraphLocation(
        country: "AU",
        countryName: "Australia",
        displayableName: "Australia",
        id: encodeToBase64("Location-8"),
        name: "Australia"
      ),
      GraphLocation(
        country: "CA",
        countryName: "Canada",
        displayableName: "Canada",
        id: encodeToBase64("Location-6"),
        name: "Canada"
      ),
      GraphLocation(
        country: "US",
        countryName: "United States",
        displayableName: "United States",
        id: encodeToBase64("Location-5"),
        name: "United States"
      )
    ]
  )
)

private final class ShippingRecording<Value> {
  private(set) var values: [Value] = []
  func append(_ value: Value) { self.values.append(value) }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, message, file: file, line: line)
  }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
}
private extension ShippingRecording where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
