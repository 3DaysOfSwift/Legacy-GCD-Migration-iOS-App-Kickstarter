import Foundation
import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers

@MainActor
internal final class ManagePledgeViewModelTests: TestCase {
  private func advancePledges(by interval: DispatchTimeInterval = .seconds(0)) async {
    await self.pledgeFeature.waitForOperations()
    await self.scheduler.advance(by: interval)
    await self.pledgeFeature.waitForOperations()
    await self.scheduler.advance()
  }
  private func runPledges() async {
    await self.pledgeFeature.waitForOperations()
    await self.scheduler.run()
    await self.pledgeFeature.waitForOperations()
    await self.scheduler.run()
  }
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let pledgeFeature = PledgeFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
    makeProvider: {
      precondition(AppEnvironment.current.apiService is MockService, "Tests require MockService")
      return AsyncPledgeProvider(service: AppEnvironment.current.apiService)
    })
  private var vm: ManagePledgeViewModelType!

  private let configurePaymentMethodView = TestObserver<ManagePledgePaymentMethodViewData, Never>()
  private let configurePledgeSummaryView = TestObserver<ManagePledgeSummaryViewData, Never>()
  private let configurePlotPaymentScheduleView = TestObserver<[PledgePaymentIncrement], Never>()
  private let endRefreshing = TestObserver<Void, Never>()
  private let goToCancelPledge = TestObserver<CancelPledgeViewData, Never>()
  private let goToChangePaymentMethod = TestObserver<PledgeViewData, Never>()
  private let goToContactCreatorSubject = TestObserver<MessageSubject, Never>()
  private let goToContactCreatorContext = TestObserver<KSRAnalytics.MessageDialogContext, Never>()
  private let goToFixPaymentMethod = TestObserver<PledgeViewData, Never>()
  private let goToRewards = TestObserver<Project, Never>()
  private let loadProjectAndRewardsIntoDataSourceProject = TestObserver<Project, Never>()
  private let loadProjectAndRewardsIntoDataSourceReward = TestObserver<[Reward], Never>()
  private let loadPullToRefreshHeaderView = TestObserver<(), Never>()
  private let notifyDelegateManagePledgeViewControllerFinishedWithMessage = TestObserver<
    String?, Never
  >()
  private let paymentMethodViewHidden = TestObserver<Bool, Never>()
  private let pledgeDetailsSectionLabelText = TestObserver<String, Never>()
  private let plotPaymentScheduleViewHidden = TestObserver<Bool, Never>()
  private let rightBarButtonItemHidden = TestObserver<Bool, Never>()
  private let showActionSheetMenuWithOptions = TestObserver<[ManagePledgeAlertAction], Never>()
  private let showErrorBannerWithMessage = TestObserver<String, Never>()
  private let showSuccessBannerWithMessage = TestObserver<String, Never>()
  private let startRefreshing = TestObserver<(), Never>()
  private let title = TestObserver<String, Never>()

  override func setUp() {
    super.setUp()
    MainActor.assumeIsolated {

      self.vm = ManagePledgeViewModel(feature: self.pledgeFeature)

      self.vm.outputs.title.observe(self.title.observer)
      self.vm.outputs.configurePaymentMethodView
        .observe(self.configurePaymentMethodView.observer)
      self.vm.outputs.configurePledgeSummaryView
        .observe(self.configurePledgeSummaryView.observer)
      self.vm.outputs.loadProjectAndRewardsIntoDataSource.map(first)
        .observe(self.loadProjectAndRewardsIntoDataSourceProject.observer)
      self.vm.outputs.loadProjectAndRewardsIntoDataSource.map(second)
        .observe(self.loadProjectAndRewardsIntoDataSourceReward.observer)
      self.vm.outputs.loadPullToRefreshHeaderView.observe(self.loadPullToRefreshHeaderView.observer)
      self.vm.outputs.endRefreshing.observe(self.endRefreshing.observer)
      self.vm.outputs.goToCancelPledge.observe(self.goToCancelPledge.observer)
      self.vm.outputs.goToChangePaymentMethod.observe(self.goToChangePaymentMethod.observer)
      self.vm.outputs.goToContactCreator.map(first).observe(self.goToContactCreatorSubject.observer)
      self.vm.outputs.goToContactCreator.map(second).observe(
        self.goToContactCreatorContext.observer)
      self.vm.outputs.goToFixPaymentMethod.observe(self.goToFixPaymentMethod.observer)
      self.vm.outputs.goToRewards.observe(self.goToRewards.observer)
      self.vm.outputs.notifyDelegateManagePledgeViewControllerFinishedWithMessage
        .observe(self.notifyDelegateManagePledgeViewControllerFinishedWithMessage.observer)
      self.vm.outputs.paymentMethodViewHidden.observe(self.paymentMethodViewHidden.observer)
      self.vm.outputs.pledgeDetailsSectionLabelText.observe(
        self.pledgeDetailsSectionLabelText.observer)
      self.vm.outputs.rightBarButtonItemHidden.observe(self.rightBarButtonItemHidden.observer)
      self.vm.outputs.showActionSheetMenuWithOptions.observe(
        self.showActionSheetMenuWithOptions.observer)
      self.vm.outputs.showErrorBannerWithMessage.observe(self.showErrorBannerWithMessage.observer)
      self.vm.outputs.showSuccessBannerWithMessage.observe(
        self.showSuccessBannerWithMessage.observer)
      self.vm.outputs.startRefreshing.observe(self.startRefreshing.observer)

      self.vm.outputs.configurePlotPaymentScheduleView.observe(
        self.configurePlotPaymentScheduleView.observer)
      self.vm.outputs.plotPaymentScheduleViewHidden.observe(
        self.plotPaymentScheduleViewHidden.observer)
    }
  }

  func testNavigationBarTitle_LiveProject() async {
    self.title.assertDidNotEmitValue()

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(.template),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        self.rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.title.assertDidNotEmitValue()

      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.title.assertValues(["Manage your pledge"])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testNavigationBarTitle_FinishedProject() async {
    self.title.assertDidNotEmitValue()

    let finishedProject =
      Project.template
      |> \.state .~ .successful

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(Backing.template),
      fetchProjectResult: .success(finishedProject),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        self.rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.title.assertValue("Your pledge")
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testConfigurePaymentMethodViewController() async {
    self.configurePaymentMethodView.assertDidNotEmitValue()

    let project = Project.template

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(Backing.template),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        self.rewardsAndPledgeOverTimeEnvelope())
    )

    let pledgePaymentMethodViewData = ManagePledgePaymentMethodViewData(
      showFixPaymentButton: false,
      expirationDate: "2019-09-30",
      lastFour: "1111",
      creditCardType: .visa,
      paymentType: .creditCard
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))

      self.vm.inputs.viewDidLoad()

      self.configurePaymentMethodView.assertDidNotEmitValue()

      await self.advancePledges()

      self.configurePaymentMethodView.assertLastValue(pledgePaymentMethodViewData)
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testConfigurePaymentMethodViewController_showFixPayment() async {
    self.configurePaymentMethodView.assertDidNotEmitValue()

    let project = Project.template
    let backing =
      Backing.template
      |> Backing.lens.status .~ .errored

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    let pledgePaymentMethodViewData = ManagePledgePaymentMethodViewData(
      showFixPaymentButton: true,
      expirationDate: "2019-09-30",
      lastFour: "1111",
      creditCardType: .visa,
      paymentType: .creditCard
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))

      self.vm.inputs.viewDidLoad()

      self.configurePaymentMethodView.assertDidNotEmitValue()

      await self.advancePledges()

      self.configurePaymentMethodView.assertLastValue(pledgePaymentMethodViewData)
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testConfigurePaymentMethodViewController_showFixPayment_noPaymentMethod() async {
    self.configurePaymentMethodView.assertDidNotEmitValue()

    let project = Project.template
    let backing =
      Backing.template
      |> Backing.lens.paymentSource .~ nil
      |> Backing.lens.status .~ .errored

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    let pledgePaymentMethodViewData = ManagePledgePaymentMethodViewData(
      showFixPaymentButton: true,
      expirationDate: nil,
      lastFour: nil,
      creditCardType: nil,
      paymentType: nil
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))

      self.vm.inputs.viewDidLoad()

      self.configurePaymentMethodView.assertDidNotEmitValue()
      self.paymentMethodViewHidden.assertDidNotEmitValue()

      await self.advancePledges()

      self.configurePaymentMethodView.assertLastValue(pledgePaymentMethodViewData)
      self.paymentMethodViewHidden.assertLastValue(false)
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testConfigurePaymentMethodViewController_PlotError() async {
    self.configurePaymentMethodView.assertDidNotEmitValue()

    let project = Project.template
    let backing =
      Backing.templateManagePledgeWithPlot
      |> Backing.lens.status .~ .errored

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        rewardsAndPledgeOverTimeEnvelope(isPledgeOverTimeAllowed: true)
      )
    )

    let pledgePaymentMethodViewData = ManagePledgePaymentMethodViewData(
      // Don't show fix payment button for PLOT payments. PLOT errors are handled separately.
      showFixPaymentButton: false,
      expirationDate: "2019-09-30",
      lastFour: "1111",
      creditCardType: .visa,
      paymentType: .creditCard
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))

      self.vm.inputs.viewDidLoad()

      self.configurePaymentMethodView.assertDidNotEmitValue()

      await self.advancePledges()

      self.configurePaymentMethodView.assertLastValue(pledgePaymentMethodViewData)
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testConfigurePaymentMethodViewController_plotAuthenticationRequired() async {
    self.configurePaymentMethodView.assertDidNotEmitValue()

    let project = Project.template
    let backing =
      Backing.templateManagePledgeWithPlot
      |> Backing.lens.status .~ .authenticationRequired

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        rewardsAndPledgeOverTimeEnvelope(isPledgeOverTimeAllowed: true)
      )
    )

    let pledgePaymentMethodViewData = ManagePledgePaymentMethodViewData(
      // Don't show fix payment button for PLOT payments. PLOT issues are handled separately.
      showFixPaymentButton: false,
      expirationDate: "2019-09-30",
      lastFour: "1111",
      creditCardType: .visa,
      paymentType: .creditCard
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))

      self.vm.inputs.viewDidLoad()

      self.configurePaymentMethodView.assertDidNotEmitValue()

      await self.advancePledges()

      self.configurePaymentMethodView.assertLastValue(pledgePaymentMethodViewData)
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testConfigurePledgeSummaryViewController() async {
    self.configurePledgeSummaryView.assertDidNotEmitValue()

    let project =
      Project.template
      |> Project.lens.personalization.backing
      .~ (.template
        |> Backing.lens.reward .~ Reward.noReward
        |> Backing.lens.rewardId .~ Reward.noReward.id)
      |> Project.lens.stats.projectCurrency .~ Project.Country.mx.currencyCode
      |> Project.lens.country .~ Project.Country.us

    let backing =
      Backing.template
      |> Backing.lens.addOns .~ nil

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    let pledgeViewSummaryData = ManagePledgeSummaryViewData(
      backerId: backing.backer?.id ?? 0,
      backerName: backing.backer?.name ?? "",
      backerSequence: backing.sequence,
      backingState: Backing.Status.pledged,
      bonusAmount: 0.0,
      currentUserIsCreatorOfProject: false,
      isNoReward: false,
      locationName: "United States",
      needsConversion: true,
      omitUSCurrencyCode: true,
      pledgeAmount: backing.amount,
      pledgedOn: backing.pledgedAt,
      currencyCode: Project.Country.mx.currencyCode,
      projectDeadline: 1_476_657_315.0,
      projectState: Project.State.live,
      rewardMinimum: 10.0,
      rewardReceivedViewControllerViewIsHidden: false,
      rewardReceivedWithData: .init(
        project: .template,
        backerCompleted: true,
        estimatedDeliveryOn: 1_506_897_315.0,
        backingState: .pledged,
        estimatedShipping: nil,
        pledgeDisclaimerViewHidden: false
      ),
      shippingAmount: backing.shippingAmount.flatMap(Double.init),
      shippingAmountHidden: true,
      rewardIsLocalPickup: false,
      paymentIncrements: [],
      project: project
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))

      self.vm.inputs.viewDidLoad()

      self.configurePledgeSummaryView.assertDidNotEmitValue()

      await self.advancePledges()

      self.configurePledgeSummaryView.assertValues([pledgeViewSummaryData])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testloadProjectAndRewardsIntoDataSource() async {
    self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
    self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()

    let project = Project.template

    let backing =
      Backing.template
      |> Backing.lens.addOns .~ nil

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))

      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.loadProjectAndRewardsIntoDataSourceProject.assertValue(project)
      self.loadProjectAndRewardsIntoDataSourceReward.assertValue([Reward.template])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testMenuButtonTapped_WhenProject_IsLive() async {
    let project =
      Project.template
      |> Project.lens.state .~ .live

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.showActionSheetMenuWithOptions.assertDidNotEmitValue()

      self.vm.inputs.menuButtonTapped()

      self.showActionSheetMenuWithOptions.assertValues([
        [
          ManagePledgeAlertAction.changePaymentMethod,
          ManagePledgeAlertAction.chooseAnotherReward,
          ManagePledgeAlertAction.contactCreator,
          ManagePledgeAlertAction.cancelPledge,
        ]
      ])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testMenuButtonTapped_WhenProject_IsLive_doesNotInclude_updatePledge() async {
    let project =
      Project.template
      |> Project.lens.state .~ .live

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.showActionSheetMenuWithOptions.assertDidNotEmitValue()

      self.vm.inputs.menuButtonTapped()

      self.showActionSheetMenuWithOptions.assertValues([
        [
          ManagePledgeAlertAction.changePaymentMethod,
          ManagePledgeAlertAction.chooseAnotherReward,
          ManagePledgeAlertAction.contactCreator,
          ManagePledgeAlertAction.cancelPledge,
        ]
      ])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testMenuButtonTapped_WhenProject_IsSuccessful_CreatorContext() async {
    let user = User.projectCreator
    let project =
      Project.template
      |> Project.lens.state .~ .successful
      |> Project.lens.creator .~ user

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.showActionSheetMenuWithOptions.assertDidNotEmitValue()

      self.vm.inputs.menuButtonTapped()

      self.showActionSheetMenuWithOptions.assertValues([[.viewRewards]])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testMenuButtonTapped_WhenProject_IsNotLive() async {
    let project =
      Project.template
      |> Project.lens.state .~ .successful

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.showActionSheetMenuWithOptions.assertDidNotEmitValue()

      self.vm.inputs.menuButtonTapped()

      self.showActionSheetMenuWithOptions.assertValues([[.viewRewards, .contactCreator]])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testMenuButtonTapped_WhenProject_IsLive_BackingStatus_IsPreAuth() async {
    let project =
      Project.template
      |> Project.lens.state .~ .live

    let backing = Backing.template |> Backing.lens.status .~ .preauth

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.showActionSheetMenuWithOptions.assertDidNotEmitValue()

      self.vm.inputs.menuButtonTapped()

      self.showActionSheetMenuWithOptions.assertValues([[.contactCreator]])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testMenuButtonTapped_WhenProject_IsLive_BackingStatus_IsPreAuth_CreatorContext() async {
    let user = User.projectCreator
    let project =
      Project.template
      |> Project.lens.creator .~ user
      |> Project.lens.state .~ .live

    let backing = Backing.template |> Backing.lens.status .~ .preauth

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.showActionSheetMenuWithOptions.assertDidNotEmitValue()

      self.vm.inputs.menuButtonTapped()

      self.showActionSheetMenuWithOptions.assertValues([[.viewRewards]])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func
    testMenuButtonTapped_WhenProject_IsEditPledgeOverTime_doesNotInclude_chooseAnotherReward_includes_EditPledge()
    async
  {
    let project =
      Project.template
      |> Project.lens.state .~ .live
      |> Project.lens.isPledgeOverTimeAllowed .~ true

    let backing = Backing.templateManagePledgeWithPlot

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        RewardsAndPledgeOverTimeEnvelope.template
      )
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.showActionSheetMenuWithOptions.assertDidNotEmitValue()

      self.vm.inputs.menuButtonTapped()

      self.showActionSheetMenuWithOptions.assertValues([
        [
          ManagePledgeAlertAction.changePaymentMethod,
          ManagePledgeAlertAction.editPledgeOverTimePledge,
          ManagePledgeAlertAction.contactCreator,
          ManagePledgeAlertAction.cancelPledge,
        ]
      ])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func
    testMenuButtonTapped_WhenProject_IsPledgeOverTime_Includes_editPledge_WhenProjectIsPLOTAllowed_IsTrue()
    async
  {
    let project =
      Project.template
      |> Project.lens.state .~ .live
      |> Project.lens.isPledgeOverTimeAllowed .~ true

    let backing = Backing.templateManagePledgeWithPlot

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        RewardsAndPledgeOverTimeEnvelope.template
      )
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.showActionSheetMenuWithOptions.assertDidNotEmitValue()

      self.vm.inputs.menuButtonTapped()

      self.showActionSheetMenuWithOptions.assertValues([
        [
          ManagePledgeAlertAction.changePaymentMethod,
          ManagePledgeAlertAction.editPledgeOverTimePledge,
          ManagePledgeAlertAction.contactCreator,
          ManagePledgeAlertAction.cancelPledge,
        ]
      ])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testGoToCancelPledge() async {
    let project = Project.template

    let backing = Backing.template

    let expectedId = backing.graphID
    let expectedAmount = backing.amount

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.goToCancelPledge.assertDidNotEmitValue()

      self.vm.inputs.menuButtonTapped()
      self.vm.inputs.menuOptionSelected(with: .cancelPledge)

      XCTAssertEqual(self.goToCancelPledge.values.map { $0.project }, [project])
      XCTAssertEqual(self.goToCancelPledge.values.map { $0.backingId }, [expectedId])
      XCTAssertEqual(self.goToCancelPledge.values.map { $0.pledgeAmount }, [expectedAmount])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testBackingNotCancelable() async {
    let backing =
      Backing.template
      |> Backing.lens.cancelable .~ false

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(.template),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    let errorBannerMessage =
      Strings
      .We_dont_allow_cancelations_that_will_cause_a_project_to_fall_short_of_its_goal_within_the_last_24_hours()

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.goToCancelPledge.assertDidNotEmitValue()

      self.vm.inputs.menuButtonTapped()
      self.vm.inputs.menuOptionSelected(with: .cancelPledge)

      self.goToCancelPledge.assertDidNotEmitValue()
      self.showErrorBannerWithMessage.assertValues([errorBannerMessage])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testGoToChangePaymentMethod() async {
    let reward = Reward.template

    let project = Project.template

    let backing =
      Backing.template
      |> Backing.lens.locationId .~ nil
      |> Backing.lens.addOns .~ nil

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        rewardsAndPledgeOverTimeEnvelope(rewards: [reward])
      )
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.goToChangePaymentMethod.assertDidNotEmitValue()

      self.vm.inputs.menuButtonTapped()
      self.vm.inputs.menuOptionSelected(with: .changePaymentMethod)

      let data = PledgeViewData(
        project: project,
        rewards: [reward],
        bonusSupport: nil,
        selectedShippingRule: nil,
        selectedQuantities: [reward.id: 1],
        selectedLocationId: nil,
        refTag: nil,
        context: .changePaymentMethod
      )

      self.goToChangePaymentMethod.assertValues([data])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testGoToContactCreator() async {
    let project = Project.template

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.goToContactCreatorSubject.assertDidNotEmitValue()
      self.goToContactCreatorContext.assertDidNotEmitValue()

      self.vm.inputs.menuButtonTapped()
      self.vm.inputs.menuOptionSelected(with: .contactCreator)

      self.goToContactCreatorSubject.assertValues([.project(id: project.id, name: project.name)])
      self.goToContactCreatorContext.assertValues([.backerModal])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testGoToRewards() async {
    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(.template),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.goToRewards.assertDidNotEmitValue()

      self.vm.inputs.menuButtonTapped()
      self.vm.inputs.menuOptionSelected(with: .chooseAnotherReward)

      self.goToRewards.assertValues([Project.template])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testGoToRewards_WithRewardDataIncludingLocalPickup_Success() async {
    let project = Project.template
    let reward =
      Reward.template
      |> Reward.lens.localPickup .~ .canada
      |> Reward.lens.shipping.preference .~ .local

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        rewardsAndPledgeOverTimeEnvelope(rewards: [reward])
      )
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.goToRewards.assertDidNotEmitValue()

      self.vm.inputs.menuButtonTapped()
      self.vm.inputs.menuOptionSelected(with: .chooseAnotherReward)

      self.goToRewards.assertValues([Project.template])
      XCTAssertNotNil(self.goToRewards.lastValue?.rewards.first?.localPickup)
      XCTAssertEqual(
        self.goToRewards.lastValue?.rewards.first?.localPickup,
        .canada
      )
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testNotifyDelegateManagePledgeViewControllerFinishedWithMessage_CancellingPledge() async {
    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(.template),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.notifyDelegateManagePledgeViewControllerFinishedWithMessage.assertDidNotEmitValue()

      self.vm.inputs.cancelPledgeDidFinish(with: "You cancelled your pledge.")

      self.notifyDelegateManagePledgeViewControllerFinishedWithMessage
        .assertValues(["You cancelled your pledge."])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testNotifyDelegateManagePledgeViewControllerFinishedWithMessage_UpdatingPledge() async {
    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(.template),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.notifyDelegateManagePledgeViewControllerFinishedWithMessage.assertDidNotEmitValue()

      self.vm.inputs.pledgeViewControllerDidUpdatePledgeWithMessage("Pledge updated.")

      self.notifyDelegateManagePledgeViewControllerFinishedWithMessage
        .assertValues([], "The delegate doesn't send message when updating a pledge.")
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testPledgeViewControllerDidUpdatePledge() async {
    let project =
      Project.cosmicSurgery
      |> Project.lens.personalization.backing
      .~ (.template
        |> Backing.lens.reward .~ Reward.noReward
        |> Backing.lens.rewardId .~ Reward.noReward.id)
      |> Project.lens.stats.projectCurrency .~ Project.Country.mx.currencyCode
      |> Project.lens.country .~ Project.Country.us

    let backing =
      Backing.template
      |> Backing.lens.locationId .~ nil
      |> Backing.lens.addOns .~ nil
      |> Backing.lens.reward .~ .noReward

    let envelope =
      ProjectAndBackingEnvelope.template
      |> \.backing .~ backing

    // Pledge amount 25
    let initialPledgeViewSummaryData = ManagePledgeSummaryViewData(
      backerId: envelope.backing.backer?.id ?? 0,
      backerName: envelope.backing.backer?.name ?? "",
      backerSequence: envelope.backing.sequence,
      backingState: Backing.Status.pledged,
      bonusAmount: 0.0,
      currentUserIsCreatorOfProject: false,
      isNoReward: true,
      locationName: "United States",
      needsConversion: true,
      omitUSCurrencyCode: true,
      pledgeAmount: 25,
      pledgedOn: envelope.backing.pledgedAt,
      currencyCode: Project.Country.mx.currencyCode,
      projectDeadline: 1_476_657_315.0,
      projectState: Project.State.live,
      rewardMinimum: 0,
      rewardReceivedViewControllerViewIsHidden: true,
      rewardReceivedWithData: .init(
        project: project,
        backerCompleted: true,
        estimatedDeliveryOn: 0.0,
        backingState: .pledged,
        estimatedShipping: nil,
        pledgeDisclaimerViewHidden: true
      ),
      shippingAmount: envelope.backing.shippingAmount.flatMap(Double.init),
      shippingAmountHidden: true,
      rewardIsLocalPickup: false,
      paymentIncrements: [],
      project: project
    )

    // Pledge amount 50
    let updatedPledgeViewSummaryData = ManagePledgeSummaryViewData(
      backerId: envelope.backing.backer?.id ?? 0,
      backerName: envelope.backing.backer?.name ?? "",
      backerSequence: envelope.backing.sequence,
      backingState: Backing.Status.pledged,
      bonusAmount: 0.0,
      currentUserIsCreatorOfProject: false,
      isNoReward: true,
      locationName: "United States",
      needsConversion: true,
      omitUSCurrencyCode: true,
      pledgeAmount: 50,
      pledgedOn: envelope.backing.pledgedAt,
      currencyCode: Project.Country.mx.currencyCode,
      projectDeadline: 1_476_657_315.0,
      projectState: Project.State.live,
      rewardMinimum: 0,
      rewardReceivedViewControllerViewIsHidden: false,
      rewardReceivedWithData: .init(
        project: project,
        backerCompleted: true,
        estimatedDeliveryOn: 1_506_897_315.0,
        backingState: .pledged,
        estimatedShipping: nil,
        pledgeDisclaimerViewHidden: true
      ),
      shippingAmount: envelope.backing.shippingAmount.flatMap(Double.init),
      shippingAmountHidden: true,
      rewardIsLocalPickup: false,
      paymentIncrements: [],
      project: project
    )

    let pledgePaymentMethodViewData = ManagePledgePaymentMethodViewData(
      showFixPaymentButton: false,
      expirationDate: "2019-09-30",
      lastFour: "1111",
      creditCardType: .visa,
      paymentType: .creditCard
    )

    let initialBacking =
      backing
      |> Backing.lens.amount .~ 25
    let updatedBackingEnvelope =
      backing
      |> Backing.lens.amount .~ 50

    let mockService1 = MockService(
      fetchManagePledgeViewBackingResult: .success(initialBacking),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        self.rewardsAndPledgeOverTimeEnvelope())
    )

    let expectedRewardReceivedData = ManageViewPledgeRewardReceivedViewData(
      project: project,
      backerCompleted: true,
      estimatedDeliveryOn: 0,
      backingState: .pledged,
      estimatedShipping: nil,
      pledgeDisclaimerViewHidden: true
    )

    await withEnvironment(apiService: mockService1) {
      self.showSuccessBannerWithMessage.assertDidNotEmitValue()
      self.configurePaymentMethodView.assertDidNotEmitValue()
      self.configurePledgeSummaryView.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()
      self.title.assertDidNotEmitValue()

      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.configurePaymentMethodView.assertValues([pledgePaymentMethodViewData])
      self.configurePledgeSummaryView.assertValues([initialPledgeViewSummaryData])

      self.loadProjectAndRewardsIntoDataSourceProject.assertValues([project])
      self.loadProjectAndRewardsIntoDataSourceReward.assertValues([[.noReward]])
      self.title.assertValues(["Manage your pledge"])
      await self.pledgeFeature.waitForOperations()
    }

    let mockService2 = MockService(
      fetchManagePledgeViewBackingResult: .success(updatedBackingEnvelope),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        self.rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService2) {
      self.vm.inputs.pledgeViewControllerDidUpdatePledgeWithMessage(
        "Got it! Your changes have been saved.")

      await self.runPledges()

      self.showSuccessBannerWithMessage.assertValues(["Got it! Your changes have been saved."])

      self.configurePaymentMethodView.assertValues([
        pledgePaymentMethodViewData,
        pledgePaymentMethodViewData,
      ])

      self.loadProjectAndRewardsIntoDataSourceProject.assertValues([
        project, project, project, project,
      ])
      self.loadProjectAndRewardsIntoDataSourceReward.assertValues([
        [.noReward], [.noReward], [.noReward], [.noReward],
      ])

      let rewardReceivedWithData = self.configurePledgeSummaryView.values.map {
        $0.rewardReceivedWithData
      }

      XCTAssertEqual([rewardReceivedWithData.last], [expectedRewardReceivedData])

      self.title.assertValues(["Manage your pledge", "Manage your pledge", "Manage your pledge"])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testFixPaymentTrackingEvents() async {
    let project = Project.template

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      XCTAssertEqual(["Page Viewed"], self.segmentTrackingClient.events)

      self.vm.inputs.fixButtonTapped()

      XCTAssertEqual(["Page Viewed"], self.segmentTrackingClient.events)
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testRefreshing_ProjectAndBackingErrorsThenSuccess() async {
    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .failure(.couldNotParseJSON),
      fetchProjectResult: .failure(.couldNotParseJSON),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.startRefreshing.assertDidNotEmitValue()
      self.endRefreshing.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()
      self.rightBarButtonItemHidden.assertDidNotEmitValue()
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      self.startRefreshing.assertValueCount(1)
      self.endRefreshing.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()
      self.rightBarButtonItemHidden.assertValues([true])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      // Network request completes
      await self.advancePledges()

      self.startRefreshing.assertValueCount(1)
      self.endRefreshing.assertValueCount(1, "Refreshing ends after project fails")
      self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()
      self.rightBarButtonItemHidden.assertValues([true])
      self.showErrorBannerWithMessage.assertValues([
        "Something went wrong, please try again.", "Something went wrong, please try again.",
      ])
      self.loadPullToRefreshHeaderView.assertValueCount(2)

      let reward = Reward.template
      let project =
        Project.template
        |> \.rewardData.rewards .~ [reward]

      let backing =
        Backing.template
        |> Backing.lens.addOns .~ nil

      let successMockService = MockService(
        fetchManagePledgeViewBackingResult: .success(backing),
        fetchProjectResult: .success(project),
        fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
          rewardsAndPledgeOverTimeEnvelope(rewards: [reward])
        )
      )

      await withEnvironment(apiService: successMockService) {
        // User pulls to refresh
        self.vm.inputs.beginRefresh()

        self.startRefreshing.assertValueCount(2)
        self.endRefreshing.assertValueCount(1)
        self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
        self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()
        self.rightBarButtonItemHidden.assertValues([true])
        self.showErrorBannerWithMessage.assertValues([
          "Something went wrong, please try again.", "Something went wrong, please try again.",
        ])
        self.loadPullToRefreshHeaderView.assertValueCount(2)

        // Network request completes
        await self.advancePledges()

        self.startRefreshing.assertValueCount(2)
        self.endRefreshing.assertValueCount(1, "Does not end refreshing, fetching backing")
        self.loadProjectAndRewardsIntoDataSourceProject.assertValues([project])
        self.loadProjectAndRewardsIntoDataSourceReward.assertValues([[reward]])
        self.rightBarButtonItemHidden.assertValues([true, false])
        self.showErrorBannerWithMessage.assertValues([
          "Something went wrong, please try again.", "Something went wrong, please try again.",
        ])
        self.loadPullToRefreshHeaderView.assertValueCount(2)

        // endRefreshing is delayed by 300ms for animation duration
        await self.advancePledges(by: .milliseconds(300))

        self.startRefreshing.assertValueCount(2)
        self.endRefreshing.assertValueCount(3, "Ends refreshing for project and backing")
        self.loadProjectAndRewardsIntoDataSourceProject.assertValues([project])
        self.loadProjectAndRewardsIntoDataSourceReward.assertValues([[reward]])
        self.rightBarButtonItemHidden.assertValues([true, false])
        self.showErrorBannerWithMessage.assertValues([
          "Something went wrong, please try again.", "Something went wrong, please try again.",
        ])
        self.loadPullToRefreshHeaderView.assertValueCount(2)
        await self.pledgeFeature.waitForOperations()
      }
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testRefreshing_BackingErrorThenSuccess() async {
    let reward = Reward.template
    let project = Project.template

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .failure(.couldNotParseJSON),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        rewardsAndPledgeOverTimeEnvelope(rewards: [reward])
      )
    )

    await withEnvironment(apiService: mockService) {
      self.startRefreshing.assertDidNotEmitValue()
      self.endRefreshing.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()
      self.rightBarButtonItemHidden.assertDidNotEmitValue()
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      self.startRefreshing.assertValueCount(1)
      self.endRefreshing.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()
      self.rightBarButtonItemHidden.assertValues([true])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      // Network request completes
      await self.advancePledges()

      self.startRefreshing.assertValueCount(1)
      self.endRefreshing.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()
      self.rightBarButtonItemHidden.assertValues([true])
      self.showErrorBannerWithMessage.assertValues(["Something went wrong, please try again."])
      self.loadPullToRefreshHeaderView.assertValueCount(1)

      // endRefreshing is delayed by 300ms for animation duration
      await self.advancePledges(by: .milliseconds(300))

      self.startRefreshing.assertValueCount(1)
      self.endRefreshing.assertValueCount(1)
      self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()
      self.rightBarButtonItemHidden.assertValues([true])
      self.showErrorBannerWithMessage.assertValues(["Something went wrong, please try again."])
      self.loadPullToRefreshHeaderView.assertValueCount(1)

      let backing =
        Backing.template
        |> Backing.lens.addOns .~ nil

      let successMockService = MockService(
        fetchManagePledgeViewBackingResult: .success(backing),
        fetchProjectResult: .success(project),
        fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
          rewardsAndPledgeOverTimeEnvelope(rewards: [reward])
        )
      )

      await withEnvironment(apiService: successMockService) {
        // User pulls to refresh
        self.vm.inputs.beginRefresh()

        self.startRefreshing.assertValueCount(2)
        self.endRefreshing.assertValueCount(1)
        self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
        self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()
        self.rightBarButtonItemHidden.assertValues([true])
        self.showErrorBannerWithMessage.assertValues(["Something went wrong, please try again."])
        self.loadPullToRefreshHeaderView.assertValueCount(1)

        // Network request completes
        await self.advancePledges()

        self.startRefreshing.assertValueCount(2)
        self.endRefreshing.assertValueCount(1)
        self.loadProjectAndRewardsIntoDataSourceProject.assertValues([project])
        self.loadProjectAndRewardsIntoDataSourceReward.assertValues([[reward]])
        self.rightBarButtonItemHidden.assertValues([true, false])
        self.showErrorBannerWithMessage.assertValues(["Something went wrong, please try again."])
        self.loadPullToRefreshHeaderView.assertValueCount(1)

        // endRefreshing is delayed by 300ms for animation duration
        await self.advancePledges(by: .milliseconds(300))

        self.startRefreshing.assertValueCount(2)
        self.endRefreshing.assertValueCount(2)
        self.loadProjectAndRewardsIntoDataSourceProject.assertValues([project])
        self.loadProjectAndRewardsIntoDataSourceReward.assertValues([[reward]])
        self.rightBarButtonItemHidden.assertValues([true, false])
        self.showErrorBannerWithMessage.assertValues(["Something went wrong, please try again."])
        self.loadPullToRefreshHeaderView.assertValueCount(1)
        await self.pledgeFeature.waitForOperations()
      }
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testRefreshing_BackingSuccessThenError() async {
    let reward = Reward.template
    let project = Project.template

    let backing =
      Backing.template
      |> Backing.lens.addOns .~ nil

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        rewardsAndPledgeOverTimeEnvelope(rewards: [reward])
      )
    )

    await withEnvironment(apiService: mockService) {
      self.startRefreshing.assertDidNotEmitValue()
      self.endRefreshing.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()
      self.rightBarButtonItemHidden.assertDidNotEmitValue()
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      self.startRefreshing.assertValueCount(1)
      self.endRefreshing.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()
      self.rightBarButtonItemHidden.assertValues([true])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      // Network request completes
      await self.advancePledges()

      self.startRefreshing.assertValueCount(1)
      self.endRefreshing.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceProject.assertValues([project])
      self.loadProjectAndRewardsIntoDataSourceReward.assertValues([[reward]])
      self.rightBarButtonItemHidden.assertValues([true, false])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      // endRefreshing is delayed by 300ms for animation duration
      await self.advancePledges(by: .milliseconds(300))

      self.startRefreshing.assertValueCount(1)
      self.endRefreshing.assertValueCount(1)
      self.loadProjectAndRewardsIntoDataSourceProject.assertValues([project])
      self.loadProjectAndRewardsIntoDataSourceReward.assertValues([[reward]])
      self.rightBarButtonItemHidden.assertValues([true, false])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      // Pledge view completed a change
      self.vm.inputs.pledgeViewControllerDidUpdatePledgeWithMessage("Updated")

      self.startRefreshing.assertValueCount(2)
      self.endRefreshing.assertValueCount(1)
      self.loadProjectAndRewardsIntoDataSourceProject.assertValues([project])
      self.loadProjectAndRewardsIntoDataSourceReward.assertValues([[reward]])
      self.rightBarButtonItemHidden.assertValues([true, false])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      // Network request completes
      await self.advancePledges()

      self.startRefreshing.assertValueCount(2)
      self.endRefreshing.assertValueCount(1)
      self.loadProjectAndRewardsIntoDataSourceProject.assertValues([
        project, project, project, project,
      ])
      self.loadProjectAndRewardsIntoDataSourceReward.assertValues([
        [reward], [reward], [reward], [reward],
      ])
      self.rightBarButtonItemHidden.assertValues([true, false])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      // endRefreshing is delayed by 300ms for animation duration
      await self.advancePledges(by: .milliseconds(300))

      self.startRefreshing.assertValueCount(2)
      self.endRefreshing.assertValueCount(2)
      self.loadProjectAndRewardsIntoDataSourceProject.assertValues([
        project, project, project, project,
      ])
      self.loadProjectAndRewardsIntoDataSourceReward.assertValues([
        [reward], [reward], [reward], [reward],
      ])
      self.rightBarButtonItemHidden.assertValues([true, false])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      // User pulls to refresh
      self.vm.inputs.beginRefresh()

      // Network request completes
      await self.advancePledges()

      self.startRefreshing.assertValueCount(3)
      self.endRefreshing.assertValueCount(2)
      self.loadProjectAndRewardsIntoDataSourceProject.assertValues(
        [project, project, project, project, project, project, project]
      )
      self.loadProjectAndRewardsIntoDataSourceReward.assertValues([
        [reward], [reward], [reward], [reward], [reward], [reward], [reward],
      ])
      self.rightBarButtonItemHidden.assertValues([true, false])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      // endRefreshing is delayed by 300ms for animation duration
      await self.advancePledges(by: .milliseconds(300))

      self.startRefreshing.assertValueCount(3)
      self.endRefreshing.assertValueCount(3)
      self.loadProjectAndRewardsIntoDataSourceProject.assertValues(
        [project, project, project, project, project, project, project]
      )
      self.loadProjectAndRewardsIntoDataSourceReward.assertValues([
        [reward], [reward], [reward], [reward], [reward], [reward], [reward],
      ])
      self.rightBarButtonItemHidden.assertValues([true, false])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      let failureMockService = MockService(
        fetchManagePledgeViewBackingResult: .failure(.couldNotParseJSON),
        fetchProjectResult: .success(project),
        fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
          rewardsAndPledgeOverTimeEnvelope(rewards: [reward])
        )
      )

      await withEnvironment(apiService: failureMockService) {
        // User pulls to refresh
        self.vm.inputs.beginRefresh()

        self.startRefreshing.assertValueCount(4)
        self.endRefreshing.assertValueCount(3)
        self.loadProjectAndRewardsIntoDataSourceProject.assertValues(
          [project, project, project, project, project, project, project]
        )
        self.loadProjectAndRewardsIntoDataSourceReward.assertValues([
          [reward], [reward], [reward], [reward], [reward], [reward], [reward],
        ])
        self.rightBarButtonItemHidden.assertValues([true, false])
        self.showErrorBannerWithMessage.assertDidNotEmitValue()
        self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

        // Network request completes
        await self.advancePledges()

        self.startRefreshing.assertValueCount(4)
        self.endRefreshing.assertValueCount(3)
        self.loadProjectAndRewardsIntoDataSourceProject.assertValues(
          [project, project, project, project, project, project, project]
        )
        self.loadProjectAndRewardsIntoDataSourceReward.assertValues([
          [reward], [reward], [reward], [reward], [reward], [reward], [reward],
        ])
        self.rightBarButtonItemHidden.assertValues([true, false])
        self.showErrorBannerWithMessage.assertValues(["Something went wrong, please try again."])
        self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

        // endRefreshing is delayed by 300ms for animation duration
        await self.advancePledges(by: .milliseconds(300))

        self.startRefreshing.assertValueCount(4)
        self.endRefreshing.assertValueCount(4, "End refresh on errors")
        self.loadProjectAndRewardsIntoDataSourceProject.assertValues(
          [project, project, project, project, project, project, project]
        )
        self.loadProjectAndRewardsIntoDataSourceReward.assertValues([
          [reward], [reward], [reward], [reward], [reward], [reward], [reward],
        ])
        self.rightBarButtonItemHidden.assertValues([true, false])
        self.showErrorBannerWithMessage.assertValues(["Something went wrong, please try again."])
        self.loadPullToRefreshHeaderView.assertDidNotEmitValue()
        await self.pledgeFeature.waitForOperations()
      }
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testRefreshing_ProjectId_NilBackingId() async {
    let reward = Reward.template
    let project =
      Project.template
      |> Project.lens.personalization.backing .~ .template

    let backing =
      Backing.template
      |> Backing.lens.addOns .~ nil

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        rewardsAndPledgeOverTimeEnvelope(rewards: [reward])
      )
    )

    await withEnvironment(apiService: mockService) {
      self.startRefreshing.assertDidNotEmitValue()
      self.endRefreshing.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()
      self.rightBarButtonItemHidden.assertDidNotEmitValue()
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      self.vm.inputs.configureWith((Param.slug("project-slug"), nil))
      self.vm.inputs.viewDidLoad()

      self.startRefreshing.assertValueCount(1)
      self.endRefreshing.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceProject.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceReward.assertDidNotEmitValue()
      self.rightBarButtonItemHidden.assertValues([true])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      // Project request completes
      await self.advancePledges()

      self.startRefreshing.assertValueCount(1)
      self.endRefreshing.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceProject.assertValues([project])
      self.loadProjectAndRewardsIntoDataSourceReward.assertValues([[reward]])
      self.rightBarButtonItemHidden.assertValues([true, false])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      // Backing request completes
      await self.advancePledges()

      self.startRefreshing.assertValueCount(1)
      self.endRefreshing.assertDidNotEmitValue()
      self.loadProjectAndRewardsIntoDataSourceProject.assertValues([project])
      self.loadProjectAndRewardsIntoDataSourceReward.assertValues([[reward]])
      self.rightBarButtonItemHidden.assertValues([true, false])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()

      // endRefreshing is delayed by 300ms for animation duration
      await self.advancePledges(by: .milliseconds(300))

      self.startRefreshing.assertValueCount(1)
      self.endRefreshing.assertValueCount(1)
      self.loadProjectAndRewardsIntoDataSourceProject.assertValues([project])
      self.loadProjectAndRewardsIntoDataSourceReward.assertValues([[reward]])
      self.rightBarButtonItemHidden.assertValues([true, false])
      self.showErrorBannerWithMessage.assertDidNotEmitValue()
      self.loadPullToRefreshHeaderView.assertDidNotEmitValue()
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testFixButtonTapped() async {
    self.goToFixPaymentMethod.assertDidNotEmitValue()

    let reward = Project.cosmicSurgery.rewards.filter { $0.id == Backing.template.rewardId }.first!

    let project = Project.cosmicSurgery

    let backing =
      Backing.template
      |> Backing.lens.locationId .~ nil
      |> Backing.lens.addOns .~ nil

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        rewardsAndPledgeOverTimeEnvelope(rewards: [reward])
      )
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.vm.inputs.fixButtonTapped()

      let data = PledgeViewData(
        project: project,
        rewards: [reward],
        bonusSupport: nil,
        selectedShippingRule: nil,
        selectedQuantities: [reward.id: 1],
        selectedLocationId: nil,
        refTag: nil,
        context: .fixPaymentMethod
      )

      self.goToFixPaymentMethod.assertValues([data])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testPaymentMethodViewHidden_UserIsCreatorOfProject() async {
    self.paymentMethodViewHidden.assertDidNotEmitValue()

    let user = User.projectCreator

    let project =
      Project.cosmicSurgery
      |> Project.lens.creator .~ user

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      self.paymentMethodViewHidden.assertDidNotEmitValue()

      await self.advancePledges()

      self.paymentMethodViewHidden.assertLastValue(true)
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testPaymentMethodViewHidden_UserIsNotCreatorOfProject() async {
    self.paymentMethodViewHidden.assertDidNotEmitValue()

    let user = User.projectCreator

    let project =
      Project.cosmicSurgery
      |> Project.lens.creator .~ (user |> User.lens.id .~ 999)

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      self.paymentMethodViewHidden.assertDidNotEmitValue()

      await self.advancePledges()

      self.paymentMethodViewHidden.assertLastValue(false)
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testPaymentMethodViewHidden_NoPaymentMethod() async {
    self.paymentMethodViewHidden.assertDidNotEmitValue()

    let project = Project.cosmicSurgery
    let backing =
      Backing.template
      |> Backing.lens.paymentSource .~ nil

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.paymentMethodViewHidden.assertLastValue(true)
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testPledgeDetailsSectionLabelText_UserIsNotCreatorOfProject() async {
    self.pledgeDetailsSectionLabelText.assertDidNotEmitValue()

    let user = User.projectCreator

    let project =
      Project.cosmicSurgery
      |> Project.lens.creator .~ (user |> User.lens.id .~ 999)

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      self.pledgeDetailsSectionLabelText.assertDidNotEmitValue()

      await self.advancePledges()

      self.pledgeDetailsSectionLabelText.assertValues(["Your pledge details"])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testPledgeDetailsSectionLabelText_UserIsCreatorOfProject() async {
    self.pledgeDetailsSectionLabelText.assertDidNotEmitValue()

    let user = User.projectCreator

    let project =
      Project.cosmicSurgery
      |> Project.lens.creator .~ user

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      self.pledgeDetailsSectionLabelText.assertDidNotEmitValue()

      await self.advancePledges()

      self.pledgeDetailsSectionLabelText.assertValues(["Pledge details"])
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testPlotPaymentScheduleView_IsHiddenWhenThereIsNoPaymentIncrements() async {
    self.pledgeDetailsSectionLabelText.assertDidNotEmitValue()

    let project =
      Project.template
      |> Project.lens.state .~ .live

    let backing = Backing.template

    let user = User.projectCreator

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project)
    )

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.plotPaymentScheduleViewHidden.assertValue(true)
      self.configurePlotPaymentScheduleView.assertDidNotEmitValue()
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testPledgeDisclaimerViewHidden_Shipping_UserIsCreatorOfProject() async {
    let user = User.projectCreator

    let project =
      Project.cosmicSurgery
      |> Project.lens.creator .~ user

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      guard
        let pledgeDisclaimerViewHidden = self.configurePledgeSummaryView.lastValue?
          .rewardReceivedWithData
          .pledgeDisclaimerViewHidden
      else {
        XCTAssertNil("configurePledgeSummaryView should not be nil.")
        return
      }

      XCTAssertTrue(pledgeDisclaimerViewHidden)
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testPledgeDisclaimerViewHidden_NoShipping_UserIsNotCreatorOfProject() async {
    let user = User.projectCreator

    let project =
      Project.cosmicSurgery
      |> Project.lens.creator .~ (user |> User.lens.id .~ 999)
      |> Project.lens.personalization.backing
      .~ (.template
        |> Backing.lens.reward .~ Reward.noReward
        |> Backing.lens.rewardId .~ Reward.noReward.id)
      |> Project.lens.stats.projectCurrency .~ Project.Country.mx.currencyCode
      |> Project.lens.country .~ Project.Country.us

    let addOn =
      Reward.template
      |> Reward.lens.estimatedDeliveryOn .~ nil

    let reward =
      Reward.template
      |> Reward.lens.estimatedDeliveryOn .~ nil

    let backing =
      Backing.template
      |> Backing.lens.reward .~ reward
      |> Backing.lens.addOns .~ [addOn]

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        rewardsAndPledgeOverTimeEnvelope(rewards: [
          .template |> Reward.lens.estimatedDeliveryOn .~ nil
        ])
      )
    )

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()
      await self.advancePledges(by: .milliseconds(300))

      guard
        let pledgeDisclaimerViewHidden = self.configurePledgeSummaryView.lastValue?
          .rewardReceivedWithData
          .pledgeDisclaimerViewHidden
      else {
        XCTAssertNil("configurePledgeSummaryView should not be nil.")
        return
      }

      XCTAssertTrue(pledgeDisclaimerViewHidden)
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testPledgeDisclaimerViewHidden_Shipping_UserIsNotCreatorOfProject() async {
    let user = User.projectCreator

    let project =
      Project.cosmicSurgery
      |> Project.lens.creator .~ (user |> User.lens.id .~ 999)

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(.template),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(rewardsAndPledgeOverTimeEnvelope())
    )

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      guard
        let pledgeDisclaimerViewHidden = self.configurePledgeSummaryView.lastValue?
          .rewardReceivedWithData
          .pledgeDisclaimerViewHidden
      else {
        XCTAssertNil("configurePledgeSummaryView should not be nil.")
        return
      }

      XCTAssertFalse(pledgeDisclaimerViewHidden)
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  func testPlotPaymentScheduleView_IsVisible() async {
    let user = User.projectCreator

    let project =
      Project.cosmicSurgery
      |> Project.lens.creator .~ user

    let backing = Backing.templateManagePledgeWithPlot

    let mockService = MockService(
      fetchManagePledgeViewBackingResult: .success(backing),
      fetchProjectResult: .success(project),
      fetchProjectRewardsAndPledgeOverTimeDataResult: .success(
        rewardsAndPledgeOverTimeEnvelope(isPledgeOverTimeAllowed: true)
      )
    )

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.inputs.configureWith((Param.slug("project-slug"), Param.id(1)))
      self.vm.inputs.viewDidLoad()

      await self.advancePledges()

      self.plotPaymentScheduleViewHidden.assertValue(false)
      self.configurePlotPaymentScheduleView.assertDidEmitValue()
      await self.pledgeFeature.waitForOperations()
    }
    await self.pledgeFeature.waitForOperations()
  }

  // MARK: - Helpers

  private func rewardsAndPledgeOverTimeEnvelope(
    rewards: [Reward] = [.template],
    isPledgeOverTimeAllowed: Bool = false
  )
    -> RewardsAndPledgeOverTimeEnvelope
  {
    RewardsAndPledgeOverTimeEnvelope(
      rewards: rewards,
      isPledgeOverTimeAllowed: isPledgeOverTimeAllowed,
      pledgeOverTimeCollectionPlanChargeExplanation: nil,
      pledgeOverTimeCollectionPlanChargedAsNPayments: nil,
      pledgeOverTimeCollectionPlanShortPitch: nil,
      pledgeOverTimeMinimumExplanation: nil
    )
  }
}
