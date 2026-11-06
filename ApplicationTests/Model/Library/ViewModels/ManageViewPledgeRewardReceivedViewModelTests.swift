@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class ManageViewPledgeRewardReceivedViewModelTests: TestCase {

  private func advancePledges(by interval: DispatchTimeInterval = .seconds(0)) async {
    await self.vm.waitForObservation()
    await self.feature.waitForOperations()
  }

  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = PledgeFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
    makeProvider: {
      precondition(AppEnvironment.current.apiService is MockService)
      return AsyncPledgeProvider(service: AppEnvironment.current.apiService)
    }
  )
  private lazy var vm = ManageViewPledgeRewardReceivedViewModel(feature: self.feature, delay: {})

  func testAttributedText() async {
    let backing = Backing.template
      |> Backing.lens.backerCompleted .~ false

    let project = Project.template
      |> Project.lens.personalization .. Project.Personalization.lens.backing .~ backing

    let data = ManageViewPledgeRewardReceivedViewData(
      project: project,
      backerCompleted: false,
      estimatedDeliveryOn: 1_475_361_315,
      backingState: .pledged,
      estimatedShipping: "About $1-$10",
      pledgeDisclaimerViewHidden: false
    )


    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    XCTAssertEqual(self.vm.estimatedDeliveryDateLabelAttributedText?.string, "Estimated delivery October 2016")
    XCTAssertEqual(self.vm.estimatedShippingAttributedText?.string, "Estimated Shipping About $1-$10")
    await self.feature.waitForOperations()
  }

  func testRewardReceived_NotReceived() async {
    let backing = Backing.template
      |> Backing.lens.backerCompleted .~ false

    let project = Project.template
      |> Project.lens.personalization .. Project.Personalization.lens.backing .~ backing

    let data = ManageViewPledgeRewardReceivedViewData(
      project: project,
      backerCompleted: false,
      estimatedDeliveryOn: 1_475_361_315,
      backingState: .pledged,
      estimatedShipping: nil,
      pledgeDisclaimerViewHidden: false
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    XCTAssertEqual(self.vm.rewardReceived, false)
    await self.feature.waitForOperations()
  }

  func testRewardReceived_Received() async {
    let backing = Backing.template
      |> Backing.lens.backerCompleted .~ true

    let project = Project.template
      |> Project.lens.personalization .. Project.Personalization.lens.backing .~ backing

    let data = ManageViewPledgeRewardReceivedViewData(
      project: project,
      backerCompleted: true,
      estimatedDeliveryOn: 1_475_361_315,
      backingState: .pledged,
      estimatedShipping: nil,
      pledgeDisclaimerViewHidden: false
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    XCTAssertEqual(self.vm.rewardReceived, true)
    await self.feature.waitForOperations()
  }

  func testRewardReceived_Toggle() async {
    let backing = Backing.template
      |> Backing.lens.backerCompleted .~ false

    let project = Project.template
      |> Project.lens.personalization .. Project.Personalization.lens.backing .~ backing

    let data = ManageViewPledgeRewardReceivedViewData(
      project: project,
      backerCompleted: false,
      estimatedDeliveryOn: 1_475_361_315,
      backingState: .pledged,
      estimatedShipping: nil,
      pledgeDisclaimerViewHidden: false
    )

    await withEnvironment(apiService: MockService(backingUpdate: .template), currentUser: User.template) {
      self.vm.configureWith(data)
      self.vm.viewDidLoad()

      XCTAssertEqual(self.vm.rewardReceived, false)

      self.vm.rewardReceivedToggleTapped(isOn: true)

      await self.advancePledges(by: AppEnvironment.current.apiDelayInterval)

      XCTAssertEqual(self.vm.rewardReceived, true)

      self.vm.rewardReceivedToggleTapped(isOn: false)

      await self.advancePledges(by: AppEnvironment.current.apiDelayInterval)

      XCTAssertEqual(self.vm.rewardReceived, false)
      await self.feature.waitForOperations()
    }
    await self.feature.waitForOperations()
  }

  func testRapidToggleKeepsLatestDisplayedResult() async {
    let data = ManageViewPledgeRewardReceivedViewData(
      project: .template, backerCompleted: false, estimatedDeliveryOn: 1_475_361_315,
      backingState: .pledged, estimatedShipping: nil, pledgeDisclaimerViewHidden: false
    )
    await withEnvironment(apiService: MockService(backingUpdate: .template), currentUser: User.template) {
      self.vm.configureWith(data)
      self.vm.viewDidLoad()
      self.vm.rewardReceivedToggleTapped(isOn: true)
      self.vm.rewardReceivedToggleTapped(isOn: false)
      await self.vm.waitForObservation()
      await self.feature.waitForOperations()
      XCTAssertFalse(self.vm.rewardReceived)
    }
  }

  func testRewardReceivedHidden_Dropped() async {
    let backing = Backing.template
      |> Backing.lens.backerCompleted .~ false

    let project = Project.template
      |> Project.lens.personalization .. Project.Personalization.lens.backing .~ backing

    let data = ManageViewPledgeRewardReceivedViewData(
      project: project,
      backerCompleted: false,
      estimatedDeliveryOn: 1_475_361_315,
      backingState: .dropped,
      estimatedShipping: nil,
      pledgeDisclaimerViewHidden: false
    )


    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    await self.advancePledges()

    XCTAssertEqual(self.vm.rewardReceivedHidden, true)
    await self.feature.waitForOperations()
  }

  func testRewardReceivedHidden_Pledged() async {
    let backing = Backing.template
      |> Backing.lens.backerCompleted .~ false

    let project = Project.template
      |> Project.lens.personalization .. Project.Personalization.lens.backing .~ backing

    let data = ManageViewPledgeRewardReceivedViewData(
      project: project,
      backerCompleted: false,
      estimatedDeliveryOn: 1_475_361_315,
      backingState: .pledged,
      estimatedShipping: nil,
      pledgeDisclaimerViewHidden: false
    )


    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    await self.advancePledges()

    XCTAssertEqual(self.vm.rewardReceivedHidden, true)
    await self.feature.waitForOperations()
  }

  func testRewardReceivedHidden_Preauth() async {
    let backing = Backing.template
      |> Backing.lens.backerCompleted .~ false

    let project = Project.template
      |> Project.lens.personalization .. Project.Personalization.lens.backing .~ backing

    let data = ManageViewPledgeRewardReceivedViewData(
      project: project,
      backerCompleted: false,
      estimatedDeliveryOn: 1_475_361_315,
      backingState: .preauth,
      estimatedShipping: nil,
      pledgeDisclaimerViewHidden: false
    )


    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    await self.advancePledges()

    XCTAssertEqual(self.vm.rewardReceivedHidden, true)
    await self.feature.waitForOperations()
  }

  func testRewardReceivedHidden_Canceled() async {
    let backing = Backing.template
      |> Backing.lens.backerCompleted .~ false

    let project = Project.template
      |> Project.lens.personalization .. Project.Personalization.lens.backing .~ backing

    let data = ManageViewPledgeRewardReceivedViewData(
      project: project,
      backerCompleted: false,
      estimatedDeliveryOn: 1_475_361_315,
      backingState: .canceled,
      estimatedShipping: nil,
      pledgeDisclaimerViewHidden: false
    )


    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    await self.advancePledges()

    XCTAssertEqual(self.vm.rewardReceivedHidden, true)
    await self.feature.waitForOperations()
  }

  func testRewardReceivedHidden_Collected() async {
    let backing = Backing.template
      |> Backing.lens.backerCompleted .~ false

    let project = Project.template
      |> Project.lens.personalization .. Project.Personalization.lens.backing .~ backing

    let data = ManageViewPledgeRewardReceivedViewData(
      project: project,
      backerCompleted: false,
      estimatedDeliveryOn: 1_475_361_315,
      backingState: .dropped,
      estimatedShipping: nil,
      pledgeDisclaimerViewHidden: false
    )


    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    await self.advancePledges()

    XCTAssertEqual(self.vm.rewardReceivedHidden, true)
    await self.feature.waitForOperations()
  }

  func testPledgeDisclaimerViewHidden() async {
    let backing = Backing.template
      |> Backing.lens.backerCompleted .~ false

    let project = Project.template
      |> Project.lens.personalization .. Project.Personalization.lens.backing .~ backing

    let data = ManageViewPledgeRewardReceivedViewData(
      project: project,
      backerCompleted: false,
      estimatedDeliveryOn: 1_475_361_315,
      backingState: .dropped,
      estimatedShipping: nil,
      pledgeDisclaimerViewHidden: true
    )


    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    await self.advancePledges()

    XCTAssertEqual(self.vm.pledgeDisclaimerViewHidden, true)
    await self.feature.waitForOperations()
  }
}
