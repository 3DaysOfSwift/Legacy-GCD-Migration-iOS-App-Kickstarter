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
final class ManageViewPledgeRewardReceivedViewModelTests: TestCase {

  private func advancePledges(by interval: DispatchTimeInterval = .seconds(0)) async {
    await self.feature.waitForOperations()
    await self.scheduler.advance(by: interval)
    await self.feature.waitForOperations()
    await self.scheduler.advance()
  }
  private func runPledges() async {
    await self.feature.waitForOperations()
    await self.scheduler.run()
    await self.feature.waitForOperations()
    await self.scheduler.run()
  }

  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = PledgeFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
    makeProvider: {
      precondition(AppEnvironment.current.apiService is MockService)
      return AsyncPledgeProvider(service: AppEnvironment.current.apiService)
    }
  )
  private lazy var vm: ManageViewPledgeRewardReceivedViewModelType = ManageViewPledgeRewardReceivedViewModel(feature: self.feature)

  private let estimatedDeliveryDateLabelAttributedText = TestObserver<String, Never>()
  private let estimatedShippingAttributedText = TestObserver<String, Never>()
  private let cornerRadius = TestObserver<CGFloat, Never>()
  private let layoutMargins = TestObserver<UIEdgeInsets, Never>()
  private let marginWidth = TestObserver<CGFloat, Never>()
  private let rewardReceived = TestObserver<Bool, Never>()
  private let rewardReceivedHidden = TestObserver<Bool, Never>()
  private let pledgeDisclaimerViewHidden = TestObserver<Bool, Never>()

  override func setUp() {
    super.setUp()
    MainActor.assumeIsolated {

      self.vm.outputs.estimatedDeliveryDateLabelAttributedText
        .map { $0.string }
        .observe(self.estimatedDeliveryDateLabelAttributedText.observer)
      self.vm.outputs.estimatedShippingAttributedText
        .map { $0.string }
        .observe(self.estimatedShippingAttributedText.observer)
      self.vm.outputs.cornerRadius.observe(self.cornerRadius.observer)
      self.vm.outputs.layoutMargins.observe(self.layoutMargins.observer)
      self.vm.outputs.marginWidth.observe(self.marginWidth.observer)
      self.vm.outputs.rewardReceived.observe(self.rewardReceived.observer)
      self.vm.outputs.rewardReceivedHidden.observe(self.rewardReceivedHidden.observer)
      self.vm.outputs.pledgeDisclaimerViewHidden.observe(self.pledgeDisclaimerViewHidden.observer)
    }
  }

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

    self.estimatedDeliveryDateLabelAttributedText.assertDidNotEmitValue()

    self.vm.inputs.configureWith(data)
    self.vm.inputs.viewDidLoad()

    self.estimatedDeliveryDateLabelAttributedText.assertValues(["Estimated delivery October 2016"])
    self.estimatedShippingAttributedText.assertValues(["Estimated Shipping About $1-$10"])
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

    self.vm.inputs.configureWith(data)
    self.vm.inputs.viewDidLoad()

    self.rewardReceived.assertValues([false])
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

    self.vm.inputs.configureWith(data)
    self.vm.inputs.viewDidLoad()

    self.rewardReceived.assertValues([true])
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
      self.vm.inputs.configureWith(data)
      self.vm.inputs.viewDidLoad()

      self.rewardReceived.assertValues([false])

      self.vm.inputs.rewardReceivedToggleTapped(isOn: true)

      await self.advancePledges(by: AppEnvironment.current.apiDelayInterval)

      self.rewardReceived.assertValues([false, true])

      self.vm.inputs.rewardReceivedToggleTapped(isOn: false)

      await self.advancePledges(by: AppEnvironment.current.apiDelayInterval)

      self.rewardReceived.assertValues([false, true, false])
      await self.feature.waitForOperations()
    }
    await self.feature.waitForOperations()
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

    self.rewardReceivedHidden.assertDidNotEmitValue()

    self.vm.inputs.configureWith(data)
    self.vm.inputs.viewDidLoad()

    await self.advancePledges()

    self.rewardReceivedHidden.assertValues([true])
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

    self.rewardReceivedHidden.assertDidNotEmitValue()

    self.vm.inputs.configureWith(data)
    self.vm.inputs.viewDidLoad()

    await self.advancePledges()

    self.rewardReceivedHidden.assertValues([true])
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

    self.rewardReceivedHidden.assertDidNotEmitValue()

    self.vm.inputs.configureWith(data)
    self.vm.inputs.viewDidLoad()

    await self.advancePledges()

    self.rewardReceivedHidden.assertValues([true])
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

    self.rewardReceivedHidden.assertDidNotEmitValue()

    self.vm.inputs.configureWith(data)
    self.vm.inputs.viewDidLoad()

    await self.advancePledges()

    self.rewardReceivedHidden.assertValues([true])
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

    self.rewardReceivedHidden.assertDidNotEmitValue()

    self.vm.inputs.configureWith(data)
    self.vm.inputs.viewDidLoad()

    await self.advancePledges()

    self.rewardReceivedHidden.assertValues([true])
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

    self.rewardReceivedHidden.assertDidNotEmitValue()

    self.vm.inputs.configureWith(data)
    self.vm.inputs.viewDidLoad()

    await self.advancePledges()

    self.pledgeDisclaimerViewHidden.assertValues([true])
    await self.feature.waitForOperations()
  }
}
