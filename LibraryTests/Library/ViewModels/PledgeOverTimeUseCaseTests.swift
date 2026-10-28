import GraphAPI
import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers

@MainActor
final class PledgeOverTimeUseCaseTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  let (projectSignal, projectObserver) = Signal<Project, Never>.pipe()
  let (pledgeTotalSignal, pledgeTotalObserver) = Signal<Double, Never>.pipe()
  let (pledgeViewContextSignal, pledgeViewContextObserver) = Signal<PledgeViewContext, Never>.pipe()

  private let feature = PledgeFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
    makeProvider: { AsyncPledgeProvider(service: AppEnvironment.current.apiService) })
  override func tearDown() async throws {
    self.useCase = nil
    self.feature.reset()
    await self.feature.waitForOperations()
    try await super.tearDown()
  }
  var useCase: PledgeOverTimeUseCase?

  let buildPaymentPlanInputs = TestObserver<(String, String), Never>()
  let pledgeOverTimeIsLoading = TestObserver<Bool, Never>()
  let showPledgeOverTimeUI = TestObserver<Bool, Never>()
  let selectedPlan = TestObserver<PledgePaymentPlansType?, Never>()

  override func setUp() {
    super.setUp()

    MainActor.assumeIsolated {
      self.useCase = PledgeOverTimeUseCase(
        project: self.projectSignal,
        pledgeTotal: self.pledgeTotalSignal,
        context: self.pledgeViewContextSignal,
        feature: self.feature
      )
      self.useCase!.outputs.buildPaymentPlanInputs.observe(self.buildPaymentPlanInputs.observer)
      self.useCase!.outputs.pledgeOverTimeIsLoading.observe(self.pledgeOverTimeIsLoading.observer)
      self.useCase!.outputs.showPledgeOverTimeUI.observe(self.showPledgeOverTimeUI.observer)
      self.useCase!.outputs.pledgeOverTimeConfigData.map { $0?.selectedPlan }
        .observe(self.selectedPlan.observer)
    }
  }

  func testNewProjectDoesNotReusePreviouslyLoadedPaymentPlan() async throws {
    let query: GraphAPI.BuildPaymentPlanQuery.Data = try testGraphObject(
      jsonString: buildPaymentPlanQueryJson(eligible: true))
    await withEnvironment(apiService: MockService(buildPaymentPlanResult: .success(query))) {
      () async in
      var projects: [Int] = []
      let observation = self.useCase!.outputs.pledgeOverTimeConfigData.observeValues {
        if let data = $0 { projects.append(data.project.id) }
      }
      defer { observation?.dispose() }
      var project = Project.template
      project.isPledgeOverTimeAllowed = true
      project.id = 1
      project.slug = "first-project"
      self.pledgeViewContextObserver.send(value: .pledge)
      self.projectObserver.send(value: project)
      self.pledgeTotalObserver.send(value: 100)
      await self.feature.waitForOperations()
      XCTAssertEqual(projects, [1])
      project.id = 2
      project.slug = "second-project"
      self.projectObserver.send(value: project)
      XCTAssertEqual(projects, [1], "Do not pair the previous plan with the new project")
      await self.feature.waitForOperations()
      XCTAssertEqual(projects, [1, 2])
    }
  }

  func testUseCase_callsBuildPaymentPlanQuery_withCorrectSlugAndPledgeTotal() async {
    await withEnvironment { () async in
      self.buildPaymentPlanInputs.assertDidNotEmitValue()

      let project =
        Project.template
        |> Project.lens.slug .~ "some-slug"
        |> Project.lens.isPledgeOverTimeAllowed .~ true
      let pledgeTotal = 928.66

      self.pledgeViewContextObserver.send(value: .pledge)
      self.projectObserver.send(value: project)
      self.pledgeTotalObserver.send(value: pledgeTotal)

      self.buildPaymentPlanInputs.assertValueCount(1)
      XCTAssertEqual(self.buildPaymentPlanInputs.lastValue?.0, "some-slug")
      XCTAssertEqual(self.buildPaymentPlanInputs.lastValue?.1, "928.66")
      await self.feature.waitForOperations()
    }
  }

  func testUseCase_callsBuildPaymentPlanQuery_SkipsRepeats() async {
    await withEnvironment { () async in
      self.buildPaymentPlanInputs.assertDidNotEmitValue()

      let project =
        Project.template
        |> Project.lens.slug .~ "some-slug"
        |> Project.lens.isPledgeOverTimeAllowed .~ true

      self.pledgeViewContextObserver.send(value: .pledge)
      self.projectObserver.send(value: project)
      self.pledgeTotalObserver.send(value: 100.0)

      self.buildPaymentPlanInputs.assertValueCount(1)
      XCTAssertEqual(self.buildPaymentPlanInputs.lastValue?.0, "some-slug")
      XCTAssertEqual(self.buildPaymentPlanInputs.lastValue?.1, "100.00")

      self.pledgeTotalObserver.send(value: 98.0)

      self.buildPaymentPlanInputs.assertValueCount(2)
      XCTAssertEqual(self.buildPaymentPlanInputs.lastValue?.0, "some-slug")
      XCTAssertEqual(self.buildPaymentPlanInputs.lastValue?.1, "98.00")

      self.pledgeTotalObserver.send(value: 98.0)

      // Count remains the same as the previous one since the value ("98.00") did not change.
      self.buildPaymentPlanInputs.assertValueCount(2)

      self.pledgeTotalObserver.send(value: 165.0)
      self.buildPaymentPlanInputs.assertValueCount(3)
      XCTAssertEqual(self.buildPaymentPlanInputs.lastValue?.0, "some-slug")
      XCTAssertEqual(self.buildPaymentPlanInputs.lastValue?.1, "165.00")

      self.useCase!.paymentPlanSelected(.pledgeInFull)
      self.useCase!.paymentPlanSelected(.pledgeOverTime)
      self.useCase!.paymentPlanSelected(.pledgeInFull)

      // Only emits unique values skipping repeats
      // pledgeTotalObserver stream:
      // 1. 100.00
      // 2. 98.00
      // 3. 98.00
      // 4. 165.00
      // Expected emitted values
      // 1. 100.00
      // 2. 98.00
      // 3. 165.00

      // Updates from paymentPlanSelected should not trigger additional emissions to buildPaymentPlanInputs.
      self.buildPaymentPlanInputs.assertValueCount(3)
      await self.feature.waitForOperations()
    }
  }

  func testUseCase_sendsLoadingEvent_whenPledgeOverTimeIsEnabled() async {
    let queryData:
      GraphAPI.BuildPaymentPlanQuery
        .Data = try! testGraphObject(
          jsonString: buildPaymentPlanQueryJson(eligible: true)
        )
    let mockApiService = MockService(buildPaymentPlanResult: .success(queryData))

    await withEnvironment(apiService: mockApiService) { () async in
      let project =
        Project.template
        |> Project.lens.slug .~ "some-slug"
        |> Project.lens.isPledgeOverTimeAllowed .~ true

      self.pledgeViewContextObserver.send(value: .pledge)
      self.projectObserver.send(value: project)
      self.pledgeTotalObserver.send(value: 100.0)
      await self.feature.waitForOperations()

      self.showPledgeOverTimeUI.assertValues([true])
      self.pledgeOverTimeIsLoading.assertValues([true, false])
    }
  }

  func testUseCase_doesntLoad_whenPledgeOverTimeIsDisabled() async {
    let queryData:
      GraphAPI.BuildPaymentPlanQuery
        .Data = try! testGraphObject(
          jsonString: buildPaymentPlanQueryJson(eligible: true)
        )
    let mockApiService = MockService(buildPaymentPlanResult: .success(queryData))

    await withEnvironment(apiService: mockApiService) { () async in
      let project =
        Project.template
        |> Project.lens.slug .~ "some-slug"
        |> Project.lens.isPledgeOverTimeAllowed .~ false

      self.pledgeViewContextObserver.send(value: .pledge)
      self.projectObserver.send(value: project)
      self.pledgeTotalObserver.send(value: 100.0)
      await self.feature.waitForOperations()

      self.pledgeOverTimeIsLoading.assertValues([false])
      self.showPledgeOverTimeUI.assertValues([false])
    }
  }

  func testUseCase_hidesUIAndStopsLoading_whenBuildPaymentPlanQueryFails() async {
    let mockApiService = MockService(buildPaymentPlanResult: .failure(.couldNotParseJSON))

    await withEnvironment(apiService: mockApiService) { () async in
      let project =
        Project.template
        |> Project.lens.slug .~ "some-slug"
        |> Project.lens.isPledgeOverTimeAllowed .~ true

      self.pledgeViewContextObserver.send(value: .pledge)
      self.projectObserver.send(value: project)
      self.pledgeTotalObserver.send(value: 100.0)
      await self.feature.waitForOperations()

      self.pledgeOverTimeIsLoading.assertValues([true, false])
      self.buildPaymentPlanInputs.assertDidEmitValue()
      self.showPledgeOverTimeUI.assertValues([true, false])
    }
  }

  func testUseCase_emitsNilPaymentPlan_andHidesUI_ifPledgeOverTimeIsDisabled() async {
    await withEnvironment { () async in
      self.buildPaymentPlanInputs.assertDidNotEmitValue()

      let project =
        Project.template
        |> Project.lens.slug .~ "some-slug"
        |> Project.lens.isPledgeOverTimeAllowed .~ false

      self.pledgeViewContextObserver.send(value: .pledge)
      self.projectObserver.send(value: project)
      self.pledgeTotalObserver.send(value: 100.0)

      self.showPledgeOverTimeUI.assertValues([false])
      self.selectedPlan.assertValues([nil])
      await self.feature.waitForOperations()
    }
  }

  func testUseCase_emitsNilPaymentPlan_andHidesUI_ifPledgeOverQueryReturnsAnError() async {
    let mockService = MockService(buildPaymentPlanResult: .failure(.couldNotParseJSON))

    await withEnvironment(apiService: mockService) { () async in
      self.buildPaymentPlanInputs.assertDidNotEmitValue()

      let project =
        Project.template
        |> Project.lens.slug .~ "some-slug"
        |> Project.lens.isPledgeOverTimeAllowed .~ true

      self.pledgeViewContextObserver.send(value: .pledge)
      self.projectObserver.send(value: project)
      self.pledgeTotalObserver.send(value: 100.0)
      await self.feature.waitForOperations()

      self.buildPaymentPlanInputs.assertDidEmitValue()
      self.showPledgeOverTimeUI.assertValues([true, false])
      self.selectedPlan.assertValues([nil])
    }
  }

  func testUseCase_paymentPlanSelected_changesSelectedPaymentPlan() async {
    let result:
      GraphAPI.BuildPaymentPlanQuery
        .Data = try! testGraphObject(
          jsonString: buildPaymentPlanQueryJson(eligible: true)
        )
    let mockService = MockService(buildPaymentPlanResult: .success(result))

    await withEnvironment(apiService: mockService) { () async in
      self.buildPaymentPlanInputs.assertDidNotEmitValue()

      let project =
        Project.template
        |> Project.lens.slug .~ "some-slug"
        |> Project.lens.isPledgeOverTimeAllowed .~ true
      let pledgeTotal = 928.66

      self.pledgeViewContextObserver.send(value: .pledge)
      self.projectObserver.send(value: project)
      self.pledgeTotalObserver.send(value: pledgeTotal)
      await self.feature.waitForOperations()

      // Defaults to pledgeInFull
      self.selectedPlan.assertValues([.pledgeInFull])

      self.useCase!.paymentPlanSelected(.pledgeOverTime)
      self.selectedPlan.assertValues([.pledgeInFull, .pledgeOverTime])

      self.useCase!.paymentPlanSelected(.pledgeInFull)
      self.selectedPlan.assertValues([.pledgeInFull, .pledgeOverTime, .pledgeInFull])
    }
  }

  func testUseCase_EditPlotPledged_PledgeOverTime_Preselected_whenIsElegible() async {
    let queryData:
      GraphAPI.BuildPaymentPlanQuery
        .Data = try! testGraphObject(
          jsonString: buildPaymentPlanQueryJson(eligible: true)
        )
    let mockApiService = MockService(buildPaymentPlanResult: .success(queryData))

    await withEnvironment(apiService: mockApiService) { () async in
      let project =
        Project.template
        |> Project.lens.slug .~ "some-slug"
        |> Project.lens.isPledgeOverTimeAllowed .~ true
        |> Project.lens.personalization.backing .~ Backing.templatePlot

      self.pledgeViewContextObserver.send(value: .pledge)
      self.projectObserver.send(value: project)
      self.pledgeTotalObserver.send(value: 100.0)
      await self.feature.waitForOperations()

      self.showPledgeOverTimeUI.assertValues([true])
      self.pledgeOverTimeIsLoading.assertValues([true, false])
      self.selectedPlan.assertLastValue(.pledgeOverTime)
    }
  }

  func testUseCase_EditPlotPledged_PledgeInFull_Preselected_whenIsNotElegible() async {
    let queryData:
      GraphAPI.BuildPaymentPlanQuery
        .Data = try! testGraphObject(
          jsonString: buildPaymentPlanQueryJson(eligible: false)
        )
    let mockApiService = MockService(buildPaymentPlanResult: .success(queryData))

    await withEnvironment(apiService: mockApiService) { () async in
      let project =
        Project.template
        |> Project.lens.slug .~ "some-slug"
        |> Project.lens.isPledgeOverTimeAllowed .~ true
        |> Project.lens.personalization.backing .~ Backing.templatePlot

      self.pledgeViewContextObserver.send(value: .pledge)
      self.projectObserver.send(value: project)
      self.pledgeTotalObserver.send(value: 100.0)
      await self.feature.waitForOperations()

      self.showPledgeOverTimeUI.assertValues([true])
      self.pledgeOverTimeIsLoading.assertValues([true, false])
      self.selectedPlan.assertLastValue(.pledgeInFull)
    }
  }

  func testUseCase_showsOrHidesUI_basedOnPledgeViewContext() async {
    await withEnvironment { () async in
      self.buildPaymentPlanInputs.assertDidNotEmitValue()

      let project =
        Project.template
        |> Project.lens.slug .~ "some-slug"
        |> Project.lens.isPledgeOverTimeAllowed .~ true

      self.projectObserver.send(value: project)
      self.pledgeTotalObserver.send(value: 100.0)

      let contextsToHideUI: [PledgeViewContext] = [
        .changePaymentMethod,
        .fixPaymentMethod,
        .latePledge,
        .update,
        .updateReward,
      ]

      for context in contextsToHideUI {
        self.pledgeViewContextObserver.send(value: context)
        self.showPledgeOverTimeUI.assertLastValue(false)
      }

      let contextsThatShowUI: [PledgeViewContext] = [.pledge, .editPledgeOverTime]
      for context in contextsThatShowUI {
        self.pledgeViewContextObserver.send(value: context)
        self.showPledgeOverTimeUI.assertLastValue(true)
      }
      await self.feature.waitForOperations()
    }
  }
}
