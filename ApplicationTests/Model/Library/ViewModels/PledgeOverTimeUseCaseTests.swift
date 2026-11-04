@testable import Kickstarter_iOS
import GraphAPI
import Prelude
import XCTest

@testable import KsApi


@MainActor
final class PledgeOverTimeUseCaseTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
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

  private let buildPaymentPlanInputs = OverTimeRecorder<(String, String)>()
  private let pledgeOverTimeIsLoading = OverTimeRecorder<Bool>()
  private let showPledgeOverTimeUI = OverTimeRecorder<Bool>()
  private let selectedPlan = OverTimeRecorder<PledgePaymentPlansType?>()

  override func setUp() async throws {
    try await super.setUp()

    MainActor.assumeIsolated {
      self.useCase = PledgeOverTimeUseCase(feature: self.feature)
      self.useCase!.onRequest = { [weak self] slug, amount in self?.buildPaymentPlanInputs.record((slug, amount)) }
      self.useCase!.onLoading = { [weak self] in self?.pledgeOverTimeIsLoading.record($0) }
      self.useCase!.onShow = { [weak self] in self?.showPledgeOverTimeUI.record($0) }
      self.useCase!.onConfig = { [weak self] in self?.selectedPlan.record($0?.selectedPlan) }
    }
  }

  func testNewProjectDoesNotReusePreviouslyLoadedPaymentPlan() async throws {
    let query: GraphAPI.BuildPaymentPlanQuery.Data = try testGraphObject(
      jsonString: buildPaymentPlanQueryJson(eligible: true))
    await withEnvironment(apiService: MockService(buildPaymentPlanResult: .success(query))) {
      () async in
      var projects: [Int] = []
      self.useCase!.onConfig = { [weak self] data in
        self?.selectedPlan.record(data?.selectedPlan)
        if let data { projects.append(data.project.id) }
      }
      var project = Project.template
      project.isPledgeOverTimeAllowed = true
      project.id = 1
      project.slug = "first-project"
      self.useCase!.updateContext(.pledge)
      self.useCase!.updateProject(project)
      self.useCase!.updateTotal(100)
      await self.useCase?.waitForPlan()
      await self.feature.waitForOperations()
      XCTAssertEqual(projects, [1])
      project.id = 2
      project.slug = "second-project"
      self.useCase!.updateProject(project)
      XCTAssertEqual(projects, [1], "Do not pair the previous plan with the new project")
      await self.useCase?.waitForPlan()
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

      self.useCase!.updateContext(.pledge)
      self.useCase!.updateProject(project)
      self.useCase!.updateTotal(pledgeTotal)

      self.buildPaymentPlanInputs.assertValueCount(1)
      XCTAssertEqual(self.buildPaymentPlanInputs.lastValue?.0, "some-slug")
      XCTAssertEqual(self.buildPaymentPlanInputs.lastValue?.1, "928.66")
      await self.useCase?.waitForPlan()
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

      self.useCase!.updateContext(.pledge)
      self.useCase!.updateProject(project)
      self.useCase!.updateTotal(100.0)

      self.buildPaymentPlanInputs.assertValueCount(1)
      XCTAssertEqual(self.buildPaymentPlanInputs.lastValue?.0, "some-slug")
      XCTAssertEqual(self.buildPaymentPlanInputs.lastValue?.1, "100.00")

      self.useCase!.updateTotal(98.0)

      self.buildPaymentPlanInputs.assertValueCount(2)
      XCTAssertEqual(self.buildPaymentPlanInputs.lastValue?.0, "some-slug")
      XCTAssertEqual(self.buildPaymentPlanInputs.lastValue?.1, "98.00")

      self.useCase!.updateTotal(98.0)

      // Count remains the same as the previous one since the value ("98.00") did not change.
      self.buildPaymentPlanInputs.assertValueCount(2)

      self.useCase!.updateTotal(165.0)
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
      await self.useCase?.waitForPlan()
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

      self.useCase!.updateContext(.pledge)
      self.useCase!.updateProject(project)
      self.useCase!.updateTotal(100.0)
      await self.useCase?.waitForPlan()
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

      self.useCase!.updateContext(.pledge)
      self.useCase!.updateProject(project)
      self.useCase!.updateTotal(100.0)
      await self.useCase?.waitForPlan()
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

      self.useCase!.updateContext(.pledge)
      self.useCase!.updateProject(project)
      self.useCase!.updateTotal(100.0)
      await self.useCase?.waitForPlan()
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

      self.useCase!.updateContext(.pledge)
      self.useCase!.updateProject(project)
      self.useCase!.updateTotal(100.0)

      self.showPledgeOverTimeUI.assertValues([false])
      self.selectedPlan.assertValues([nil])
      await self.useCase?.waitForPlan()
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

      self.useCase!.updateContext(.pledge)
      self.useCase!.updateProject(project)
      self.useCase!.updateTotal(100.0)
      await self.useCase?.waitForPlan()
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

      self.useCase!.updateContext(.pledge)
      self.useCase!.updateProject(project)
      self.useCase!.updateTotal(pledgeTotal)
      await self.useCase?.waitForPlan()
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

      self.useCase!.updateContext(.pledge)
      self.useCase!.updateProject(project)
      self.useCase!.updateTotal(100.0)
      await self.useCase?.waitForPlan()
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

      self.useCase!.updateContext(.pledge)
      self.useCase!.updateProject(project)
      self.useCase!.updateTotal(100.0)
      await self.useCase?.waitForPlan()
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

      self.useCase!.updateProject(project)
      self.useCase!.updateTotal(100.0)

      let contextsToHideUI: [PledgeViewContext] = [
        .changePaymentMethod,
        .fixPaymentMethod,
        .latePledge,
        .update,
        .updateReward,
      ]

      for context in contextsToHideUI {
        self.useCase!.updateContext(context)
        self.showPledgeOverTimeUI.assertLastValue(false)
      }

      let contextsThatShowUI: [PledgeViewContext] = [.pledge, .editPledgeOverTime]
      for context in contextsThatShowUI {
        self.useCase!.updateContext(context)
        self.showPledgeOverTimeUI.assertLastValue(true)
      }
      await self.useCase?.waitForPlan()
      await self.feature.waitForOperations()
    }
  }
}

private final class OverTimeRecorder<Value> {
  private var values: [Value] = []
  var lastValue: Value? { self.values.last }
  func record(_ value: Value) { self.values.append(value) }
  func assertDidNotEmitValue(file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(self.values.isEmpty, file: file, line: line) }
  func assertDidEmitValue(file: StaticString = #filePath, line: UInt = #line) { XCTAssertFalse(self.values.isEmpty, file: file, line: line) }
  func assertValueCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(self.values.count, count, file: file, line: line) }
  func assertLastValue(_ expected: Value, file: StaticString = #filePath, line: UInt = #line) where Value: Equatable { XCTAssertEqual(self.values.last, expected, file: file, line: line) }
  func assertValues(_ expected: [Value], file: StaticString = #filePath, line: UInt = #line) where Value: Equatable { XCTAssertEqual(self.values, expected, file: file, line: line) }
}
