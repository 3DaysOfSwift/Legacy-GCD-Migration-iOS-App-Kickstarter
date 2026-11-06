@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class PledgeStatusLabelViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = PledgeStatusLabelViewModel()

  func testBadgeAndMissingTextPreserveExistingLabel() {
    let first = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false, needsConversion: false, pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode, projectDeadline: 1_476_657_315,
      projectState: .live, backingState: .canceled, paymentIncrements: nil, project: nil
    )
    let second = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false, needsConversion: false, pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode, projectDeadline: 1_476_657_315,
      projectState: .live, backingState: .authenticationRequired, paymentIncrements: nil, project: nil
    )
    self.vm.configure(with: first)
    let previous = self.vm.labelText?.string
    XCTAssertTrue(self.vm.badgeHidden)
    self.vm.configure(with: second)
    XCTAssertEqual(self.vm.labelText?.string, previous)
    XCTAssertTrue(self.vm.badgeHidden)
  }

  func testProjectStatusCanceled_Backer() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.canceled,
      backingState: Backing.Status.pledged,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "The creator canceled this project, so your payment method was never charged."
    ])
  }

  func testProjectStatusFailed_Backer() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.failed,
      backingState: Backing.Status.pledged,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "This project didn’t reach its funding goal, so your payment method was never charged."
    ])
  }

  func testBackingStatus_Canceled_Backer() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.live,
      backingState: Backing.Status.canceled,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "You canceled your pledge for this project."
    ])
  }

  func testBackingStatus_Collected_Backer() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.successful,
      backingState: Backing.Status.collected,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "We collected your pledge for this project."
    ])
  }

  func testBackingStatus_Dummy_Backer() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false,
      needsConversion: false,
      pledgeAmount: 0,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.successful,
      backingState: Backing.Status.dummy,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "We collected your pledge for this project."
    ])
  }

  func testBackingStatus_Dropped_Backer() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.successful,
      backingState: Backing.Status.dropped,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "Your pledge was dropped because of payment errors."
    ])
  }

  func testBackingStatus_Errored_Backer() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.successful,
      backingState: Backing.Status.errored,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "We can’t process your pledge. Please update your payment method."
    ])
  }

  func testBackingStatus_AuthenticationRequired_Backer() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.successful,
      backingState: Backing.Status.authenticationRequired,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    // TODO: for now we expected a nil `labelTextString`, this will be addressed when we get to the native implementation in this ticket [MBL-2012](https://kickstarter.atlassian.net/browse/MBL-2012)
    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [])
  }

  func testBackingStatus_Preauth_Backer() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.live,
      backingState: Backing.Status.preauth,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "We're processing your pledge—pull to refresh."
    ])
  }

  func testBackingStatus_Pledged_Backer() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.successful,
      backingState: Backing.Status.pledged,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "If the project reaches its funding goal, you will be charged on October 16, 2016."
    ])
  }

  func testBackingStatus_Pledged_OtherCurrency_Backer() {
    withEnvironment(locale: Locale(identifier: "en")) {
      let data = PledgeStatusLabelViewData(
        currentUserIsCreatorOfProject: false,
        needsConversion: true,
        pledgeAmount: 10,
        currencyCode: Project.Country.hk.currencyCode,
        projectDeadline: 1_476_657_315,
        projectState: Project.State.successful,
        backingState: Backing.Status.pledged,
        paymentIncrements: nil,
        project: nil
      )

      self.vm.configure(with: data)

      XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
        "If the project reaches its funding goal, you will be charged HK$ 10 on October 16, 2016. You will receive a proof of pledge that will be redeemable if the project is funded and the creator is successful at completing the creative venture."
      ])
    }
  }

  func testBackingStatus_AllOtherStatuses_Backer() {
    let statuses = Backing.Status.allCases
      .filter {
        ![.canceled, .collected, .dropped, .dummy, .errored, .authenticationRequired, .pledged, .preauth]
          .contains($0)
      }

    statuses.forEach { backingState in
      let data = PledgeStatusLabelViewData(
        currentUserIsCreatorOfProject: false,
        needsConversion: false,
        pledgeAmount: 10,
        currencyCode: Project.Country.hk.currencyCode,
        projectDeadline: 1_476_657_315,
        projectState: Project.State.successful,
        backingState: backingState,
        paymentIncrements: nil,
        project: nil
      )

      self.vm.configure(with: data)
    }

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [])
  }

  func testProjectStatusCanceled_Creator() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: true,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.canceled,
      backingState: Backing.Status.pledged,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "You canceled this project, so the backer’s payment method was never charged."
    ])
  }

  func testProjectStatusFailed_Creator() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: true,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.failed,
      backingState: Backing.Status.pledged,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "Your project didn’t reach its funding goal, so the backer’s payment method was never charged."
    ])
  }

  func testBackingStatus_Canceled_Creator() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: true,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.live,
      backingState: Backing.Status.canceled,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "The backer canceled their pledge for this project."
    ])
  }

  func testBackingStatus_Collected_Creator() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: true,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.successful,
      backingState: Backing.Status.collected,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "We collected the backer’s pledge for this project."
    ])
  }

  func testBackingStatus_Dropped_Creator() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: true,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.successful,
      backingState: Backing.Status.dropped,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "This pledge was dropped because of payment errors."
    ])
  }

  func testBackingStatus_Errored_Creator() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: true,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.successful,
      backingState: Backing.Status.errored,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "We can’t process this pledge because of a problem with the backer’s payment method."
    ])
  }

  func testBackingStatus_Pledged_Creator() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: true,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.live,
      backingState: Backing.Status.pledged,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "If your project reaches its funding goal, the backer will be charged on October 16, 2016."
    ])
  }

  func testBackingStatus_Pledged_OtherCurrency_Creator() {
    withEnvironment(locale: Locale(identifier: "en")) {
      let data = PledgeStatusLabelViewData(
        currentUserIsCreatorOfProject: true,
        needsConversion: true,
        pledgeAmount: 10,
        currencyCode: Project.Country.hk.currencyCode,
        projectDeadline: 1_476_657_315,
        projectState: Project.State.successful,
        backingState: Backing.Status.pledged,
        paymentIncrements: nil,
        project: nil
      )

      self.vm.configure(with: data)

      XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
        "If your project reaches its funding goal, the backer will be charged HK$ 10 on October 16, 2016."
      ])
    }
  }

  func testBackingStatus_Preauth_Creator() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: true,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.hk.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.successful,
      backingState: Backing.Status.preauth,
      paymentIncrements: nil,
      project: nil
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "We're processing this pledge—pull to refresh."
    ])
  }

  func testBackingStatus_AllOtherStatuses_Creator() {
    let statuses = Backing.Status.allCases
      .filter {
        ![.canceled, .collected, .dropped, .dummy, .errored, .authenticationRequired, .pledged, .preauth]
          .contains($0)
      }

    statuses.forEach { backingState in
      let data = PledgeStatusLabelViewData(
        currentUserIsCreatorOfProject: true,
        needsConversion: false,
        pledgeAmount: 10,
        currencyCode: Project.Country.hk.currencyCode,
        projectDeadline: 1_476_657_315,
        projectState: Project.State.successful,
        backingState: backingState,
        paymentIncrements: nil,
        project: nil
      )

      self.vm.configure(with: data)
    }

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [])
  }

  func testBackingStatus_Pledged_Backer_PledgeOverTime_LiveProject() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.us.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.live,
      backingState: Backing.Status.pledged,
      paymentIncrements: mockPaymentIncrements(),
      project: Project.template
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "You have selected Pledge Over Time. If the project reaches its funding goal, the first charge of $250.00 will be collected on March 28, 2019."
    ])
  }

  func testBackingStatus_Pledged_Backer_PledgeOverTime_NotLiveProject() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.us.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.successful,
      backingState: Backing.Status.pledged,
      paymentIncrements: mockPaymentIncrements(),
      project: Project.template
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "We collected your pledge for this project."
    ])
  }

  func testBackingStatus_Errored_Backer_PledgeOverTime() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.us.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.successful,
      backingState: Backing.Status.errored,
      paymentIncrements: mockPaymentIncrements(),
      project: Project.template
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "We can’t process your Pledge Over Time payment. Please view your pledge on a web browser and log in to fix your payment."
    ])
  }

  func testBackingStatus_AuthenticationRequired_Backer_PledgeOverTime() {
    let data = PledgeStatusLabelViewData(
      currentUserIsCreatorOfProject: false,
      needsConversion: false,
      pledgeAmount: 10,
      currencyCode: Project.Country.us.currencyCode,
      projectDeadline: 1_476_657_315,
      projectState: Project.State.successful,
      backingState: Backing.Status.authenticationRequired,
      paymentIncrements: mockPaymentIncrements(),
      project: Project.template
    )

    self.vm.configure(with: data)

    XCTAssertEqual(self.vm.labelText.map { [$0.string] } ?? [], [
      "We can’t process your Pledge Over Time payment. Please view your pledge on a web browser and log in to fix your payment."
    ])
  }
}
