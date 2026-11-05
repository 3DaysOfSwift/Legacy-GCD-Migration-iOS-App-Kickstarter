@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class PledgeCTAContainerViewViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  let vm = PledgeCTAContainerViewViewModel(sleep: { try Task.checkCancellation() })

  let activityIndicatorIsHidden = PledgeCTARecorder<Bool>()
  let buttonStyleType = PledgeCTARecorder<ButtonStyleType>()
  let buttonTitleText = PledgeCTARecorder<String>()
  let notifyDelegateCTATapped = PledgeCTARecorder<PledgeStateCTAType>()
  let pledgeCTAButtonIsHidden = PledgeCTARecorder<Bool>()
  let pledgeRetryButtonIsHidden = PledgeCTARecorder<Bool>()
  let prelaunchCTASaved = PledgeCTARecorder<PledgeCTAPrelaunchState>()
  let spacerIsHidden = PledgeCTARecorder<Bool>()
  let stackViewIsHidden = PledgeCTARecorder<Bool>()
  let subtitleText = PledgeCTARecorder<String>()
  let titleText = PledgeCTARecorder<String>()
  let watchesLabelHidden = PledgeCTARecorder<Bool>()
  let watchesCountText = PledgeCTARecorder<String>()

  internal override func setUp() async throws {
    try await super.setUp()

    self.vm.outputs.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .activityHidden(value): self.activityIndicatorIsHidden.record(value)
      case let .buttonStyle(value): self.buttonStyleType.record(value)
      case let .buttonTitle(value): self.buttonTitleText.record(value)
      case let .tapped(value): self.notifyDelegateCTATapped.record(value)
      case let .buttonHidden(value): self.pledgeCTAButtonIsHidden.record(value)
      case let .watchesHidden(value): self.watchesLabelHidden.record(value)
      case let .prelaunch(value): self.prelaunchCTASaved.record(value)
      case let .retryHidden(value): self.pledgeRetryButtonIsHidden.record(value)
      case let .contentHidden(value):
        self.spacerIsHidden.record(value)
        self.stackViewIsHidden.record(value)
      case let .subtitle(value): self.subtitleText.record(value)
      case let .title(value): self.titleText.record(value)
      case let .watchesCount(value): self.watchesCountText.record(value)
      }
    }
  }

  func testPledgeCTA_Backer_LiveProject_US_ProjectCurrency() {
    let reward = .template
      |> Reward.lens.title .~ "Magic Lamp"
    let backing = .template
      |> Backing.lens.reward .~ reward
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.personalization.backing .~ backing
      |> Project.lens.stats.userCurrency .~ "USD"
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.blue])
    self.buttonTitleText.assertValues([Strings.Manage()])
    self.titleText.assertValues([Strings.Youre_a_backer()])
    self.subtitleText.assertValues(["$10 • Magic Lamp"])
    self.spacerIsHidden.assertValues([false])
    self.stackViewIsHidden.assertValues([false])
  }

  func testPledgeCTA_Backer_LiveProject_NonUS_ProjectCurrency() {
    let reward = .template
      |> Reward.lens.title .~ "Magic Lamp"
    let backing = .template
      |> Backing.lens.reward .~ reward
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.personalization.backing .~ backing
      |> Project.lens.stats.userCurrency .~ "USD"
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.mx.currencyCode

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.blue])
    self.buttonTitleText.assertValues([Strings.Manage()])
    self.titleText.assertValues([Strings.Youre_a_backer()])
    self.subtitleText.assertValues([" MX$ 10 • Magic Lamp"])
    self.spacerIsHidden.assertValues([false])
    self.stackViewIsHidden.assertValues([false])
  }

  func testPledgeCTA_BackerWithDecimalAmount_LiveProject() {
    let reward = .template
      |> Reward.lens.title .~ "Magic Lamp"
    let backing = .template
      |> Backing.lens.reward .~ reward
      |> Backing.lens.amount .~ 10.50
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.personalization.backing .~ backing
      |> Project.lens.stats.userCurrency .~ "USD"
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.blue])
    self.buttonTitleText.assertValues([Strings.Manage()])
    self.titleText.assertValues([Strings.Youre_a_backer()])
    self.subtitleText.assertValues(["$10.50 • Magic Lamp"])
    self.spacerIsHidden.assertValues([false])
    self.stackViewIsHidden.assertValues([false])
  }

  func testPledgeCTA_Backer_NonLiveProject() {
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.personalization.backing .~ Backing.template
      |> Project.lens.state .~ .successful

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.black])
    self.buttonTitleText.assertValues([Strings.View_your_pledge()])
    self.spacerIsHidden.assertValues([true])
    self.stackViewIsHidden.assertValues([true])
  }

  func testPledgeCTA_NetNewBackerGoToPM() {
    let project = Project.netNewBacker

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.black])
    self.buttonTitleText.assertValues([Strings.Go_to_pledge_manager()])
    self.spacerIsHidden.assertValues([true])
    self.stackViewIsHidden.assertValues([true])
  }

  func testPledgeCTA_ExistingBackerGoToPM() {
    let project = Project.netNewBacker
      |> Project.lens.personalization.backing .~ Backing.template
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.pledgeManager .~ nil

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.black])
    self.buttonTitleText.assertValues([Strings.Go_to_pledge_manager()])
    self.spacerIsHidden.assertValues([true])
    self.stackViewIsHidden.assertValues([true])
  }

  func testPledgeCTA_dummyPledgeGoToPM() {
    let backing = Backing.template
      |> Backing.lens.status .~ .dummy
    let project = Project.template
      |> Project.lens.personalization.backing .~ backing
      |> Project.lens.personalization.isBacking .~ true

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.black])
    self.buttonTitleText.assertValues([Strings.Go_to_pledge_manager()])
    self.spacerIsHidden.assertValues([true])
    self.stackViewIsHidden.assertValues([true])
  }

  func testPledgeCTA_NonBacker_LiveProject_loggedOut() {
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ nil
      |> Project.lens.state .~ .live

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.green])
    self.buttonTitleText.assertValues([Strings.Back_this_project()])
    self.spacerIsHidden.assertValues([true])
    self.stackViewIsHidden.assertValues([true])
  }

  func testPledgeCTA_NonBacker_NonLiveProject_loggedOut() {
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ nil
      |> Project.lens.state .~ .successful

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.black])
    self.buttonTitleText.assertValues([Strings.View_rewards()])
    self.spacerIsHidden.assertValues([true])
    self.stackViewIsHidden.assertValues([true])
  }

  func testPledgeCTA_Backer_LiveProject_Error() {
    let backing = Backing.template
      |> Backing.lens.status .~ .errored
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.state .~ .live
      |> Project.lens.personalization.backing .~ backing
      |> Project.lens.stats.userCurrency .~ "USD"
      |> Project.lens.country .~ .us
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.blue])
    self.buttonTitleText.assertValues([Strings.Manage()])
    self.titleText.assertValues([Strings.Youre_a_backer()])
    self.subtitleText.assertValues(["$10 • My Reward"])
    self.spacerIsHidden.assertValues([false])
    self.stackViewIsHidden.assertValues([false])
  }

  func testPledgeCTA_Backer_NonLiveProject_Error() {
    let backing = Backing.template
      |> Backing.lens.status .~ .errored
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.state .~ .successful
      |> Project.lens.personalization.backing .~ backing

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.red])
    self.buttonTitleText.assertValues([Strings.Manage()])
    self.titleText.assertValues(["Payment failure"])
    self.subtitleText.assertValues(["We can't process your pledge."])
    self.spacerIsHidden.assertValues([false])
    self.stackViewIsHidden.assertValues([false])
  }

  func testPledgeCTA_NonBacker_LiveProject_loggedIn() {
    let project = Project.template
      |> Project.lens.personalization.backing .~ nil
      |> Project.lens.personalization.isBacking .~ false

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.green])
    self.buttonTitleText.assertValues([Strings.Back_this_project()])
    self.spacerIsHidden.assertValues([true])
    self.stackViewIsHidden.assertValues([true])
  }

  func testPledgeCTA_NonBacker_NonLiveProject_loggedIn() {
    let project = Project.template
      |> Project.lens.state .~ .successful
      |> Project.lens.personalization.isBacking .~ false

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.black])
    self.buttonTitleText.assertValues([Strings.View_rewards()])
    self.spacerIsHidden.assertValues([true])
    self.stackViewIsHidden.assertValues([true])
  }

  func testPledgeCTA_LiveProject_UserIsCreator() {
    let user = User.template |> User.lens.id .~ 5
    let project = Project.template
      |> Project.lens.creator.id .~ 5
      |> Project.lens.state .~ .live

    withEnvironment(currentUser: user) {
      let value = PledgeCTAContainerViewData.project(project)
      self.vm.inputs.configureWith(value: value)
      self.buttonStyleType.assertValues([ButtonStyleType.black])
      self.buttonTitleText.assertValues(["View your rewards"])
      self.spacerIsHidden.assertValues([true])
      self.stackViewIsHidden.assertValues([true])
    }
  }

  func testPledgeCTA_NonLiveProject_UserIsCreator() {
    let user = User.template |> User.lens.id .~ 5
    let project = Project.template
      |> Project.lens.creator.id .~ 5
      |> Project.lens.state .~ .successful

    withEnvironment(currentUser: user) {
      let value = PledgeCTAContainerViewData.project(project)
      self.vm.inputs.configureWith(value: value)
      self.buttonStyleType.assertValues([ButtonStyleType.black])
      self.buttonTitleText.assertValues(["View your rewards"])
      self.spacerIsHidden.assertValues([true])
      self.stackViewIsHidden.assertValues([true])
    }
  }

  func testPledgeCTA_activityIndicator() {
    let project = Project.template
      |> Project.lens.state .~ .live

    let value = PledgeCTAContainerViewData.loading
    self.vm.inputs.configureWith(value: value)
    self.activityIndicatorIsHidden.assertValues([false])
    self.pledgeCTAButtonIsHidden.assertValues([true])
    self.pledgeRetryButtonIsHidden.assertValues([true])

    self.buttonTitleText.assertDidNotEmitValue()
    self.buttonStyleType.assertValues([])
    self.spacerIsHidden.assertValues([true])
    self.stackViewIsHidden.assertValues([true])

    let value2 = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value2)
    self.activityIndicatorIsHidden.assertValues([false, true])
    self.pledgeCTAButtonIsHidden.assertValues([true, false])
    self.pledgeRetryButtonIsHidden.assertValues([true])

    self.buttonTitleText.assertDidEmitValue()
    self.buttonStyleType.assertValues([ButtonStyleType.green])
    self.spacerIsHidden.assertValues([true, true])
    self.stackViewIsHidden.assertValues([true, true])
  }

  func testPledgeCTA_pledgeRetryButtonIsVisible_AfterFailure() {
    let project = Project.template
      |> Project.lens.state .~ .live

    self.pledgeRetryButtonIsHidden.assertDidNotEmitValue()

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.pledgeRetryButtonIsHidden.assertValues([true])
    self.spacerIsHidden.assertValues([true])
    self.stackViewIsHidden.assertValues([true])

    let value2 = PledgeCTAContainerViewData.error(.couldNotParseJSON)
    self.vm.inputs.configureWith(value: value2)
    self.pledgeRetryButtonIsHidden.assertValues([true, false])
    self.spacerIsHidden.assertValues([true, true])
    self.stackViewIsHidden.assertValues([true, true])
  }

  func testNotifyDelegateCTATapped() {
    let project = Project.template
      |> Project.lens.personalization.backing .~ nil
      |> Project.lens.personalization.isBacking .~ false

    self.notifyDelegateCTATapped.assertDidNotEmitValue()

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.green])
    self.buttonTitleText.assertValues([Strings.Back_this_project()])

    self.vm.inputs.pledgeCTAButtonTapped()
    self.notifyDelegateCTATapped.assertValueCount(1)
  }

  func testTrackingEvents_ViewRewards() {
    let project = Project.template
      |> Project.lens.state .~ .successful
      |> Project.lens.personalization.isBacking .~ false

    self.notifyDelegateCTATapped.assertDidNotEmitValue()

    let value = PledgeCTAContainerViewData.project(project)
    self.vm.inputs.configureWith(value: value)
    self.buttonStyleType.assertValues([ButtonStyleType.black])
    self.buttonTitleText.assertValues([Strings.View_rewards()])

    self.vm.inputs.pledgeCTAButtonTapped()
    self.notifyDelegateCTATapped.assertValueCount(1)
  }

  func testTrackingEvents_Pledge() {
    let value = PledgeCTAContainerViewData.project(Project.template)
    self.vm.inputs.configureWith(value: value)

    self.notifyDelegateCTATapped.assertDidNotEmitValue()

    self.vm.inputs.pledgeCTAButtonTapped()

    self.notifyDelegateCTATapped.assertValueCount(1)

    XCTAssertEqual(["CTA Clicked"], self.segmentTrackingClient.events)

    let segmentTrackingClientProperties = self.segmentTrackingClient.properties.last

    XCTAssertEqual("pledge_initiate", segmentTrackingClientProperties?["context_cta"] as? String)
  }

  func testPledgeCTA_PrelaunchGoesFromUnsavedToSavedViaNotification_Success() async {
    let unsavedProject = Project.template
      |> \.displayPrelaunch .~ true
      |> \.watchesCount .~ 99
      |> \.personalization.isStarred .~ false

    let prelaunchCTAUnsaved = PledgeCTAPrelaunchState(prelaunch: true, saved: false, watchesCount: 99)
    let prelaunchCTASaved = PledgeCTAPrelaunchState(prelaunch: true, saved: true, watchesCount: 100)

    let value = PledgeCTAContainerViewData.project(unsavedProject)
    self.vm.inputs.configureWith(value: value)

    self.buttonStyleType.assertValues([.black])
    self.buttonTitleText.assertValues(["Notify me on launch"])
    self.watchesCountText.assertValues(["99 followers"])
    self.watchesLabelHidden.assertValues([false])
    XCTAssertEqual(self.prelaunchCTASaved.values.count, 1)
    XCTAssertEqual(self.prelaunchCTASaved.values.first!.prelaunch, prelaunchCTAUnsaved.prelaunch)
    XCTAssertEqual(self.prelaunchCTASaved.values.first!.saved, prelaunchCTAUnsaved.saved)
    self.notifyDelegateCTATapped.assertDidNotEmitValue()

    let savedProject = Project.template
      |> \.displayPrelaunch .~ true
      |> \.watchesCount .~ 100
      |> \.personalization.isStarred .~ true

    self.vm.inputs.savedProjectFromNotification(project: savedProject)
    await self.vm.waitForSavedProject()

    self.buttonStyleType.assertValues([.black, .none])
    self.buttonTitleText.assertValues(["Notify me on launch", "Saved"])
    self.watchesCountText.assertValues(["99 followers", "100 followers"])
    self.watchesLabelHidden.assertValues([false, false])
    XCTAssertEqual(self.prelaunchCTASaved.values.count, 2)
    XCTAssertEqual(self.prelaunchCTASaved.values.last!.prelaunch, prelaunchCTASaved.prelaunch)
    XCTAssertEqual(self.prelaunchCTASaved.values.last!.saved, prelaunchCTASaved.saved)
    self.notifyDelegateCTATapped.assertDidNotEmitValue()
  }

  func testNewSavedProjectNotificationSupersedesPendingUpdate() async {
    let initial = Project.template |> \.displayPrelaunch .~ true |> \.watchesCount .~ 10
    let first = initial |> \.personalization.isStarred .~ true |> \.watchesCount .~ 11
    let latest = initial |> \.personalization.isStarred .~ true |> \.watchesCount .~ 12
    self.vm.inputs.configureWith(value: .project(initial))
    self.vm.inputs.savedProjectFromNotification(project: first)
    self.vm.inputs.savedProjectFromNotification(project: latest)
    await self.vm.waitForSavedProject()
    self.watchesCountText.assertValues(["10 followers", "12 followers"])
  }

  func testPledgeCTA_PrelaunchNotifiesWithStateViaButtonClick_Success() {
    let savedProject = Project.template
      |> \.displayPrelaunch .~ true
      |> \.watchesCount .~ 102
      |> \.personalization.isStarred .~ true

    let value = PledgeCTAContainerViewData.project(savedProject)
    self.vm.inputs.configureWith(value: value)

    self.notifyDelegateCTATapped.assertDidNotEmitValue()

    self.vm.inputs.pledgeCTAButtonTapped()

    XCTAssertEqual(self.notifyDelegateCTATapped.values.count, 1)
    XCTAssertEqual(self.notifyDelegateCTATapped.values.last!, .prelaunch(saved: true, watchCount: 102))
  }
}

@MainActor
final class PledgeCTARecorder<Value> {
  private(set) var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, file: file, line: line)
  }
  func assertDidNotEmitValue(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, file: file, line: line)
  }
  func assertDidEmitValue(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(self.values.isEmpty, file: file, line: line)
  }
}

private extension PledgeCTARecorder where Value: Equatable {
  func assertValues(_ values: [Value], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, values, file: file, line: line)
  }
}
