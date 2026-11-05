@testable import Kickstarter_iOS
import Foundation
import KDS
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class CancelPledgeViewModelTests: TestCase {

  private func advancePledges() async { await self.vm.waitForOperation() }
  private func runPledges() async { await self.vm.waitForOperation() }

  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = PledgeFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
    makeProvider: {
      precondition(AppEnvironment.current.apiService is MockService)
      return AsyncPledgeProvider(service: AppEnvironment.current.apiService)
    }
  )
  private lazy var vm: CancelPledgeViewModel = CancelPledgeViewModel(feature: self.feature)

  private let cancellationDetailsAttributedTextString = Recording<String>()
  private let cancellationDetailsAttributedTextAttributedString = Recording<NSAttributedString>()
  private let cancelPledgeButtonEnabled = Recording<Bool>()
  private let cancelPledgeError = Recording<String>()
  private let isLoading = Recording<Bool>()
  private let notifyDelegateCancelPledgeSuccess = Recording<String>()

  override func setUp() async throws {
    try await super.setUp()
    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .details(value):
        self.cancellationDetailsAttributedTextAttributedString.append(value)
        self.cancellationDetailsAttributedTextString.append(value.string)
      case let .buttonEnabled(value): self.cancelPledgeButtonEnabled.append(value)
      case let .error(value): self.cancelPledgeError.append(value)
      case let .loading(value): self.isLoading.append(value)
      case let .success(value): self.notifyDelegateCancelPledgeSuccess.append(value)
      }
    }
  }

  func testConfigureCancelPledgeView() async {
    let project = Project.cosmicSurgery
      |> Project.lens.stats.projectCurrency .~ Project.Country.us.currencyCode

    let data = CancelPledgeViewData(
      project: project,
      projectName: project.name,
      omitUSCurrencyCode: project.stats.omitUSCurrencyCode,
      backingId: "backing-id",
      pledgeAmount: 5
    )

    self.vm.configure(with: data)
    self.vm.viewDidLoad()

    let cancellationString = "Are you sure you wish to cancel your $5 pledge to Cosmic Surgery?"
    var pledgeAmountRange: NSRange = (cancellationString as NSString).range(of: "$5")
    var projectNameRange: NSRange = (cancellationString as NSString).range(of: "Cosmic Surgery")

    let boldFontAttribute = UIFont.ksr_callout().bolded

    self.cancellationDetailsAttributedTextString
      .assertValues([cancellationString])

    XCTAssertEqual(
      self.cancellationDetailsAttributedTextAttributedString.values
        .compactMap { $0.attribute(
          .font,
          at: pledgeAmountRange.location,
          effectiveRange: &pledgeAmountRange
        ) } as? [UIFont],
      [boldFontAttribute]
    )
    XCTAssertEqual(
      self.cancellationDetailsAttributedTextAttributedString.values
        .compactMap { $0.attribute(
          .font,
          at: projectNameRange.location,
          effectiveRange: &projectNameRange
        ) } as? [UIFont],
      [boldFontAttribute]
    )

    self.vm.traitCollectionDidChange()

    self.cancellationDetailsAttributedTextString
      .assertValues([
        cancellationString,
        cancellationString
      ])
    XCTAssertEqual(
      self.cancellationDetailsAttributedTextAttributedString.values
        .compactMap { $0.attribute(
          .font,
          at: pledgeAmountRange.location,
          effectiveRange: &pledgeAmountRange
        ) } as? [UIFont],
      [boldFontAttribute, boldFontAttribute]
    )
    XCTAssertEqual(
      self.cancellationDetailsAttributedTextAttributedString.values
        .compactMap { $0.attribute(
          .font,
          at: projectNameRange.location,
          effectiveRange: &projectNameRange
        ) } as? [UIFont],
      [boldFontAttribute, boldFontAttribute]
    )
    await self.vm.waitForOperation()
  }

  func testCancelPledgeButtonEnabled() async {
    let envelope = EmptyResponseEnvelope()
    let mockService = MockService(cancelBackingResult: .success(envelope))

    await withEnvironment(apiService: mockService) {
      let project = Project.template

      let data = CancelPledgeViewData(
        project: project,
        projectName: project.name,
        omitUSCurrencyCode: project.stats.omitUSCurrencyCode,
        backingId: String(project.personalization.backing?.id ?? 0),
        pledgeAmount: project.personalization.backing?.amount ?? 0
      )

      self.vm.configure(with: data)

      self.vm.viewDidLoad()

      self.cancelPledgeButtonEnabled.assertValues([true])

      self.vm.textFieldDidEndEditing(with: "cancel reason")

      self.cancelPledgeButtonEnabled.assertValues([true])

      self.vm.cancelPledgeButtonTapped()

      self.cancelPledgeButtonEnabled.assertValues(
        [true, false],
        "Cancel button disabled when request in flight"
      )

      await self.runPledges()

      self.cancelPledgeButtonEnabled.assertValues(
        [true, false, true],
        "Cancel button enabled when request completes"
      )
      await self.vm.waitForOperation()
    }
    await self.vm.waitForOperation()
  }

  func testCancelPledge_Success() async {
    let envelope = EmptyResponseEnvelope()
    let mockService = MockService(cancelBackingResult: .success(envelope))

    await withEnvironment(apiService: mockService) {
      let project = Project.template

      let data = CancelPledgeViewData(
        project: project,
        projectName: project.name,
        omitUSCurrencyCode: project.stats.omitUSCurrencyCode,
        backingId: String(project.personalization.backing?.id ?? 0),
        pledgeAmount: project.personalization.backing?.amount ?? 0
      )

      self.vm.configure(with: data)

      self.vm.viewDidLoad()

      self.notifyDelegateCancelPledgeSuccess.assertDidNotEmitValue()
      self.cancelPledgeError.assertDidNotEmitValue()

      self.vm.cancelPledgeButtonTapped()

      self.notifyDelegateCancelPledgeSuccess.assertDidNotEmitValue()
      self.cancelPledgeError.assertDidNotEmitValue()

      await self.runPledges()

      self.notifyDelegateCancelPledgeSuccess.assertValues(["You\'ve canceled your pledge."])
      self.cancelPledgeError.assertDidNotEmitValue()

      self.vm.textFieldDidEndEditing(with: "No money")

      self.vm.cancelPledgeButtonTapped()

      self.notifyDelegateCancelPledgeSuccess.assertValueCount(1)
      self.cancelPledgeError.assertDidNotEmitValue()

      await self.runPledges()

      self.notifyDelegateCancelPledgeSuccess.assertValues([
        "You\'ve canceled your pledge.",
        "You\'ve canceled your pledge."
      ])
      self.cancelPledgeError.assertDidNotEmitValue()
      await self.vm.waitForOperation()
    }
    await self.vm.waitForOperation()
  }

  func testCancelPledge_Error() async {
    let mockService = MockService(
      cancelBackingResult:
      .failure(.couldNotParseJSON)
    )

    await withEnvironment(apiService: mockService) {
      let project = Project.template

      let data = CancelPledgeViewData(
        project: project,
        projectName: project.name,
        omitUSCurrencyCode: project.stats.omitUSCurrencyCode,
        backingId: String(project.personalization.backing?.id ?? 0),
        pledgeAmount: project.personalization.backing?.amount ?? 0
      )

      self.vm.configure(with: data)

      self.vm.viewDidLoad()

      self.notifyDelegateCancelPledgeSuccess.assertDidNotEmitValue()
      self.cancelPledgeError.assertDidNotEmitValue()

      self.vm.cancelPledgeButtonTapped()

      self.notifyDelegateCancelPledgeSuccess.assertDidNotEmitValue()
      self.cancelPledgeError.assertDidNotEmitValue()

      await self.runPledges()

      self.notifyDelegateCancelPledgeSuccess.assertDidNotEmitValue()
      self.cancelPledgeError.assertValues(["Something went wrong."])
      await self.vm.waitForOperation()
    }
    await self.vm.waitForOperation()
  }

  func testTrackingEvents() async {
    let envelope = EmptyResponseEnvelope()
    let mockService = MockService(cancelBackingResult: .success(envelope))

    await withEnvironment(apiService: mockService) {
      let project = Project.template

      let data = CancelPledgeViewData(
        project: project,
        projectName: project.name,
        omitUSCurrencyCode: project.stats.omitUSCurrencyCode,
        backingId: String(project.personalization.backing?.id ?? 0),
        pledgeAmount: project.personalization.backing?.amount ?? 0
      )

      self.vm.configure(with: data)

      self.vm.viewDidLoad()

      XCTAssertEqual([], self.segmentTrackingClient.events)

      self.vm.cancelPledgeButtonTapped()

      XCTAssertEqual([], self.segmentTrackingClient.events)
      await self.vm.waitForOperation()
    }
    await self.vm.waitForOperation()
  }

  func testIsLoading() async {
    self.isLoading.assertDidNotEmitValue()

    let project = Project.template

    let data = CancelPledgeViewData(
      project: project,
      projectName: project.name,
      omitUSCurrencyCode: project.stats.omitUSCurrencyCode,
      backingId: String(project.personalization.backing?.id ?? 0),
      pledgeAmount: project.personalization.backing?.amount ?? 0
    )

    let envelope = EmptyResponseEnvelope()
    let mockService = MockService(cancelBackingResult: .success(envelope))

    await withEnvironment(apiService: mockService) {
      self.vm.configure(with: data)

      self.vm.viewDidLoad()

      self.isLoading.assertDidNotEmitValue()

      self.vm.cancelPledgeButtonTapped()

      self.isLoading.assertValues([true])

      await self.advancePledges()

      self.isLoading.assertValues([true, false])
      await self.vm.waitForOperation()
    }
    await self.vm.waitForOperation()
  }
}

private final class Recording<Value> {
  private(set) var values: [Value] = []
  func append(_ value: Value) { self.values.append(value) }
  func assertDidNotEmitValue(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, file: file, line: line)
  }
  func assertValueCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, file: file, line: line)
  }
}
private extension Recording where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
