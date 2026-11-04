@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class ManagePledgeSummaryViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  private let vm = ManagePledgeSummaryViewModel()

  func testTextOutputsEmitTheCorrectValue_US_ProjectCountryCurrency() {
    let data = ManagePledgeSummaryViewData(
      backerId: 1,
      backerName: "Backer McGee",
      backerSequence: 999,
      backingState: Backing.Status.pledged,
      bonusAmount: nil,
      currentUserIsCreatorOfProject: false,
      isNoReward: false,
      locationName: nil,
      needsConversion: false,
      omitUSCurrencyCode: true,
      pledgeAmount: 30,
      pledgedOn: 1_568_666_243.0,
      currencyCode: Project.Country.us.currencyCode,
      projectDeadline: 1_572_626_213.0,
      projectState: Project.State.live,
      rewardMinimum: 30,
      rewardReceivedViewControllerViewIsHidden: false,
      rewardReceivedWithData: .init(
        project: .template,
        backerCompleted: true,
        estimatedDeliveryOn: 1_475_361_315,
        backingState: .collected,
        estimatedShipping: nil,
        pledgeDisclaimerViewHidden: false
      ),
      shippingAmount: nil,
      shippingAmountHidden: true,
      rewardIsLocalPickup: false,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configureWith(data)
    XCTAssertNil(self.vm.data)
    self.vm.viewDidLoad()

    XCTAssertEqual(self.vm.backerNumberText, "Backer #999")
    XCTAssertEqual(self.vm.backingDateText, "As of September 16, 2019")
    XCTAssertEqual(self.vm.totalAmountText?.string, "$30.00")
  }

  func testTextOutputsEmitTheCorrectValue_NonUS_ProjectCountryCurrency() {
    let data = ManagePledgeSummaryViewData(
      backerId: 1,
      backerName: "Backer McGee",
      backerSequence: 999,
      backingState: Backing.Status.pledged,
      bonusAmount: nil,
      currentUserIsCreatorOfProject: false,
      isNoReward: false,
      locationName: nil,
      needsConversion: false,
      omitUSCurrencyCode: true,
      pledgeAmount: 30,
      pledgedOn: 1_568_666_243.0,
      currencyCode: Project.Country.mx.currencyCode,
      projectDeadline: 1_572_626_213.0,
      projectState: Project.State.live,
      rewardMinimum: 30,
      rewardReceivedViewControllerViewIsHidden: false,
      rewardReceivedWithData: .init(
        project: .template,
        backerCompleted: true,
        estimatedDeliveryOn: 1_475_361_315,
        backingState: .collected,
        estimatedShipping: nil,
        pledgeDisclaimerViewHidden: false
      ),
      shippingAmount: nil,
      shippingAmountHidden: true,
      rewardIsLocalPickup: false,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    XCTAssertEqual(self.vm.backerNumberText, "Backer #999")
    XCTAssertEqual(self.vm.backingDateText, "As of September 16, 2019")
    XCTAssertEqual(self.vm.totalAmountText?.string, " MX$ 30.00")
  }

  func testBackerUserInfo_UserIsBacker() {
    let user = User.template
      |> User.lens.id .~ 123
      |> User.lens.name .~ "Blob"

    let data = ManagePledgeSummaryViewData(
      backerId: 123,
      backerName: "Blob",
      backerSequence: 999,
      backingState: Backing.Status.pledged,
      bonusAmount: nil,
      currentUserIsCreatorOfProject: false,
      isNoReward: false,
      locationName: nil,
      needsConversion: false,
      omitUSCurrencyCode: true,
      pledgeAmount: 30,
      pledgedOn: 1_568_666_243.0,
      currencyCode: Project.Country.us.currencyCode,
      projectDeadline: 1_572_626_213.0,
      projectState: Project.State.live,
      rewardMinimum: 30,
      rewardReceivedViewControllerViewIsHidden: false,
      rewardReceivedWithData: .init(
        project: .template,
        backerCompleted: true,
        estimatedDeliveryOn: 1_475_361_315,
        backingState: .collected,
        estimatedShipping: nil,
        pledgeDisclaimerViewHidden: false
      ),
      shippingAmount: nil,
      shippingAmountHidden: true,
      rewardIsLocalPickup: false,
      paymentIncrements: nil,
      project: nil
    )

    withEnvironment(currentUser: user) {
      self.vm.configureWith(data)
      self.vm.viewDidLoad()

      XCTAssertEqual(self.vm.backerNameText, "Blob")
      XCTAssertEqual(self.vm.backerNameLabelHidden, false)
      XCTAssertEqual(self.vm.backerImageURLAndPlaceholderImageName?.0, URL(string: "http://www.kickstarter.com/small.jpg")!)
      XCTAssertEqual(self.vm.backerImageURLAndPlaceholderImageName?.1, "avatar--placeholder")
      XCTAssertEqual(self.vm.backerNameLabelHidden, false)
    }
  }

  func testBackerUserInfo_UserIsNotBacker() {
    let user = User.template
      |> User.lens.id .~ 123

    let data = ManagePledgeSummaryViewData(
      backerId: 321,
      backerName: "Backer McGee",
      backerSequence: 999,
      backingState: Backing.Status.pledged,
      bonusAmount: nil,
      currentUserIsCreatorOfProject: false,
      isNoReward: false,
      locationName: nil,
      needsConversion: false,
      omitUSCurrencyCode: true,
      pledgeAmount: 30,
      pledgedOn: 1_568_666_243.0,
      currencyCode: Project.Country.us.currencyCode,
      projectDeadline: 1_572_626_213.0,
      projectState: Project.State.live,
      rewardMinimum: 30,
      rewardReceivedViewControllerViewIsHidden: false,
      rewardReceivedWithData: .init(
        project: .template,
        backerCompleted: true,
        estimatedDeliveryOn: 1_475_361_315,
        backingState: .collected,
        estimatedShipping: nil,
        pledgeDisclaimerViewHidden: false
      ),
      shippingAmount: nil,
      shippingAmountHidden: true,
      rewardIsLocalPickup: false,
      paymentIncrements: nil,
      project: nil
    )

    withEnvironment(currentUser: user) {
      self.vm.configureWith(data)
      self.vm.viewDidLoad()

      XCTAssertNil(self.vm.backerNameText)
      XCTAssertEqual(self.vm.backerNameLabelHidden, true)
      XCTAssertNil(self.vm.backerImageURLAndPlaceholderImageName?.0)
      XCTAssertNil(self.vm.backerImageURLAndPlaceholderImageName?.1)
      XCTAssertEqual(self.vm.backerNameLabelHidden, true)
    }
  }

  func testConfiguringPledgeAmountSummaryViewData_Success() {
    let data = ManagePledgeSummaryViewData(
      backerId: 1,
      backerName: "Backer McGee",
      backerSequence: 999,
      backingState: Backing.Status.pledged,
      bonusAmount: nil,
      currentUserIsCreatorOfProject: false,
      isNoReward: false,
      locationName: nil,
      needsConversion: false,
      omitUSCurrencyCode: true,
      pledgeAmount: 30,
      pledgedOn: 1_568_666_243.0,
      currencyCode: Project.Country.us.currencyCode,
      projectDeadline: 1_572_626_213.0,
      projectState: Project.State.live,
      rewardMinimum: 30,
      rewardReceivedViewControllerViewIsHidden: false,
      rewardReceivedWithData: .init(
        project: .template,
        backerCompleted: true,
        estimatedDeliveryOn: 1_475_361_315,
        backingState: .collected,
        estimatedShipping: nil,
        pledgeDisclaimerViewHidden: false
      ),
      shippingAmount: nil,
      shippingAmountHidden: true,
      rewardIsLocalPickup: true,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    guard let pledgeAmountSummaryValue = self.vm.configurePledgeAmountSummaryViewWithData else {
      XCTFail("pledge amount summary view data should exist")
      return
    }

    XCTAssertTrue(pledgeAmountSummaryValue.omitUSCurrencyCode)
    XCTAssertNil(pledgeAmountSummaryValue.bonusAmount)
    XCTAssertFalse(pledgeAmountSummaryValue.bonusAmountHidden)
    XCTAssertFalse(pledgeAmountSummaryValue.isNoReward)
    XCTAssertNil(pledgeAmountSummaryValue.locationName)
    XCTAssertNil(pledgeAmountSummaryValue.shippingAmount)
    XCTAssertEqual(pledgeAmountSummaryValue.currencyCode, Project.Country.us.currencyCode)
    XCTAssertEqual(pledgeAmountSummaryValue.pledgedOn, 1_568_666_243.0)
    XCTAssertEqual(pledgeAmountSummaryValue.rewardMinimum, 30)
    XCTAssertTrue(pledgeAmountSummaryValue.shippingAmountHidden)
    XCTAssertTrue(pledgeAmountSummaryValue.rewardIsLocalPickup)
  }
}
