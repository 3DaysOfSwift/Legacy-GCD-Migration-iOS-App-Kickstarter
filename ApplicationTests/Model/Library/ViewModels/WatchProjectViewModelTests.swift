@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class WatchProjectViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  internal var vm: WatchProjectViewModel!
  private var feature: ProjectMediaFeature!
  private var clock: WatchTestClock!

  private let generateImpactFeedback = WatchRecording<()>()
  private let generateSelectionFeedback = WatchRecording<()>()
  private let generateNotificationSuccessFeedback = WatchRecording<()>()
  private let goToLoginTout = WatchRecording<()>()
  private let postNotificationWithProject = WatchRecording<Project>()
  private let saveButtonAccessibilityValue = WatchRecording<String>()
  private let saveButtonSelected = WatchRecording<Bool>()
  private let showNotificationDialog = WatchRecording<Notification.Name>()
  private let showProjectSavedAlert = WatchRecording<Void>()

  internal override func setUp() async throws {
    try await super.setUp()
    self.feature = ProjectMediaFeature(makeProvider: { AsyncProjectMediaProvider(service: AppEnvironment.current.apiService) })
    self.clock = WatchTestClock()
    let clock = self.clock!
    self.vm = WatchProjectViewModel(feature: self.feature, sleep: { try await clock.sleep($0) })

    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case .impact: self.generateImpactFeedback.append(())
      case .selection: self.generateSelectionFeedback.append(())
      case .success: self.generateNotificationSuccessFeedback.append(())
      case .login: self.goToLoginTout.append(())
      case let .project(project): self.postNotificationWithProject.append(project)
      case let .selected(value):
        self.saveButtonSelected.append(value)
        self.saveButtonAccessibilityValue.append(value ? Strings.Saved() : Strings.Unsaved())
      case let .notification(notification): self.showNotificationDialog.append(notification.name)
      case .savedAlert: self.showProjectSavedAlert.append(())
      }
    }
  }

  private func advance(by interval: DispatchTimeInterval = .seconds(0)) async {
    let seconds: Double
    switch interval {
    case let .seconds(value): seconds = Double(value)
    case let .milliseconds(value): seconds = Double(value) / 1_000
    case let .microseconds(value): seconds = Double(value) / 1_000_000
    case let .nanoseconds(value): seconds = Double(value) / 1_000_000_000
    case .never: seconds = 0
    @unknown default: seconds = 0
    }
    await Task.yield()
    await self.clock.advance(by: seconds)
    await self.feature.waitForOperations()
    if seconds >= 0.5 { await self.vm.waitForOperation() }
    await Task.yield()
  }

  func testSaveAlertNotification() async {
    await withEnvironment(currentUser: .template) {
      self.vm.configure(with: (.template, .project, nil))
      self.vm.viewDidLoad()
      self.vm.saveButtonTapped(selected: true)
      await self.advance(by: .seconds(1))
      self.showProjectSavedAlert.assertValueCount(1)
    }
  }

  func testGenerateImpactFeedback() async {
    await withEnvironment(currentUser: .template) {
      self.vm.configure(with: (.template, .project, nil))
      self.vm.viewDidLoad()

      self.vm.saveButtonTouched()
      self.generateImpactFeedback.assertValueCount(1)
    }
  }

  func testGenerateSelectionFeedback() async {
    await withEnvironment(currentUser: .template) {
      self.vm.configure(with: (.template, .project, nil))
      self.vm.viewDidLoad()

      self.vm.saveButtonTapped(selected: true)
      await self.advance()
      self.generateSelectionFeedback.assertValueCount(1)
      self.generateNotificationSuccessFeedback.assertValueCount(0)
    }
  }

  func testGenerateNotificationSuccessFeedback() async {
    await withEnvironment(currentUser: .template) {
      self.vm.configure(with: (.template, .project, nil))
      self.vm.viewDidLoad()

      self.vm.saveButtonTapped(selected: false)
      await self.advance()
      self.generateSelectionFeedback.assertValueCount(0)
      self.generateNotificationSuccessFeedback.assertValueCount(1)
    }
  }

  func testWatchProject_WithError() async {
    let project = Project.template

    await withEnvironment(
      apiService: MockService(watchProjectMutationResult: .failure(.couldNotParseJSON)),
      currentUser: .template
    ) {
      self.vm.configure(with: (project, .project, nil))
      self.vm.viewDidLoad()

      self.saveButtonSelected.assertValues([false], "Save button is not selected at first.")

      self.vm.saveButtonTapped(selected: false)

      self.saveButtonSelected.assertValues(
        [false, true],
        "Emits true because it's toggled immmediately."
      )

      await self.advance(by: .milliseconds(500))

      self.saveButtonSelected.assertValues(
        [false, true, false],
        "Returns to false on error."
      )
    }
  }

  func testUnwatchProject_LoggedIn_User() async {
    let project = Project.template
      |> Project.lens.personalization.isStarred .~ true
      |> Project.lens.watchesCount .~ 1

    await withEnvironment(
      apiService: MockService(unwatchProjectMutationResult: .success(.unwatchTemplate)),
      currentUser: .template
    ) {
      self.vm.configure(with: (project, .project, nil))
      self.vm.viewDidLoad()

      XCTAssertEqual(self.postNotificationWithProject.lastValue!.watchesCount, 1)
      self.saveButtonSelected.assertValues([true], "Save button is selected at first.")

      self.vm.saveButtonTapped(selected: true)

      self.saveButtonSelected.assertValues([true, false], "Emits false immediately.")

      await self.advance(by: .milliseconds(500))

      self.saveButtonSelected.assertValues(
        [true, false],
        "Save button remains deselected after request."
      )
      XCTAssertEqual(self.postNotificationWithProject.lastValue!.watchesCount, 9)
    }
  }

  func testUnwatchProject_LoggedIn_User_Debouncing() async {
    let project = Project.template
      |> Project.lens.personalization.isStarred .~ true

    await withEnvironment(
      apiService: MockService(unwatchProjectMutationResult: .success(.unwatchTemplate)),
      currentUser: .template
    ) {
      self.vm.configure(with: (project, .project, nil))
      self.vm.viewDidLoad()

      self.saveButtonSelected.assertValues([true], "Save button is selected at first.")

      self.vm.saveButtonTapped(selected: true)

      self.saveButtonSelected.assertValues([true, false], "Emits false immediately.")

      self.vm.saveButtonTapped(selected: false)
      await self.advance(by: .milliseconds(250))

      self.vm.saveButtonTapped(selected: true)
      await self.advance(by: .milliseconds(250))

      self.vm.saveButtonTapped(selected: false)
      await self.advance(by: .milliseconds(250))

      self.saveButtonSelected.assertValues(
        [true, false, true, false, true], "State flips back and forth as button is tapped."
      )

      self.vm.saveButtonTapped(selected: true)
      await self.advance(by: .milliseconds(500))

      self.saveButtonSelected.assertValues(
        [true, false, true, false, true, false],
        "Network call is made after 0.5 seconds of no taps, value from response is always used"
      )
    }
  }

  func testWatchProject_LoggedOut_User() async {
    let project = Project.template
      |> Project.lens.personalization.isStarred .~ false

    await withEnvironment(apiService: MockService(watchProjectMutationResult: .success(.watchTemplate))) {
      self.vm.configure(with: (project, .project, nil))
      self.vm.viewDidLoad()

      self.saveButtonSelected.assertValues([false], "Save button is not selected for logged out user.")

      self.vm.saveButtonTapped(selected: false)

      self.saveButtonSelected.assertValues(
        [false],
        "Nothing is emitted when save button tapped while logged out."
      )

      self.goToLoginTout.assertValueCount(
        1,
        "Prompt to login when save button tapped while logged out."
      )

      AppEnvironment.login(.init(accessToken: "deadbeef", user: .template))
      self.vm.userSessionStarted()

      self.saveButtonSelected.assertValues(
        [false, true],
        "Once logged in, the save button is selected immediately."
      )

      await self.advance(by: .milliseconds(500))

      self.saveButtonSelected.assertValues(
        [false, true],
        "Save button stays selected after API request."
      )

      await withEnvironment(apiService: MockService(unwatchProjectMutationResult: .success(.unwatchTemplate))) {
        self.vm.saveButtonTapped(selected: true)

        self.saveButtonSelected.assertValues(
          [false, true, false],
          "Save button is deselected."
        )

        await self.advance(by: .milliseconds(500))

        self.saveButtonSelected.assertValues(
          [false, true, false],
          "The save button remains unselected."
        )
      }
    }
  }

  func testWatchProjectFromPamphlet() async {
    let project = Project.template
      |> Project.lens.personalization.isStarred .~ false
    let projectUpdated = project
      |> Project.lens.personalization.isStarred .~ true

    self.vm.configure(with: (project, .project, nil))
    self.vm.viewDidLoad()

    self.saveButtonSelected.assertValues([false])

    self.vm.projectFromNotification(project: projectUpdated)

    self.saveButtonSelected.assertValues([false, true])
  }

  func testShowNotificationDialogEmits_IfStarredProjectsCountIsZero() async {
    let user = User.template |> \.stats.starredProjectsCount .~ 0

    await withEnvironment(currentUser: user) {
      self.vm.configure(with: (.template, .project, nil))
      self.vm.viewDidLoad()

      self.vm.saveButtonTapped(selected: false)
      await self.advance(by: .milliseconds(500))

      self.showNotificationDialog.assertDidEmitValue()
    }
  }

  func testShowNotificationDialogDoesNotEmit_IfStarredProjectsCountIsNotZero() async {
    let project = Project.template
    let user = User.template |> \.stats.starredProjectsCount .~ 3

    await withEnvironment(currentUser: user) {
      self.vm.configure(with: (project, .project, nil))
      self.vm.viewDidLoad()

      self.vm.saveButtonTapped(selected: true)
      await self.advance(by: .milliseconds(500))

      self.showNotificationDialog.assertDidNotEmitValue()
    }
  }

  func testLoggedInUser_WatchesAndUnwatchesProject_SegmentEvents_Success() async {
    AppEnvironment.login(.init(accessToken: "deadbeef", user: .template))

    let project = Project.template
      |> Project.lens.personalization.isStarred .~ false

    await withEnvironment(apiService: MockService(watchProjectMutationResult: .success(.watchTemplate))) {
      self.vm.configure(with: (project, .project, nil))
      self.vm.viewDidLoad()

      self.saveButtonSelected.assertValues([false], "Save button is not selected at first")
      self.saveButtonAccessibilityValue.assertValues(["Unsaved"])

      self.vm.saveButtonTapped(selected: false)

      XCTAssertEqual(
        ["CTA Clicked"],
        self.segmentTrackingClient.events
      )
      XCTAssertEqual(["project"], self.segmentTrackingClient.properties(forKey: "context_page"))
      XCTAssertEqual(["watch_project"], self.segmentTrackingClient.properties(forKey: "context_cta"))
      XCTAssertEqual(["watch"], self.segmentTrackingClient.properties(forKey: "context_type"))

      self.saveButtonSelected.assertValues([false, true], "Save button selects immediately.")
      self.saveButtonAccessibilityValue.assertValues(["Unsaved", "Saved"])

      await self.advance(by: .milliseconds(500))

      self.saveButtonSelected.assertValues(
        [false, true],
        "Save button remains selected."
      )

      self.showProjectSavedAlert.assertValueCount(1, "The save project prompt shows.")

      await withEnvironment(apiService: MockService(unwatchProjectMutationResult: .success(.unwatchTemplate))) {
        self.vm.saveButtonTapped(selected: true)

        XCTAssertEqual(
          ["CTA Clicked", "CTA Clicked"],
          self.segmentTrackingClient.events
        )
        XCTAssertEqual(
          ["project", "project"],
          self.segmentTrackingClient.properties(forKey: "context_page")
        )
        XCTAssertEqual(
          ["watch_project", "watch_project"],
          self.segmentTrackingClient.properties(forKey: "context_cta")
        )
        XCTAssertEqual(
          ["watch", "unwatch"],
          self.segmentTrackingClient.properties(forKey: "context_type")
        )

        self.saveButtonSelected.assertValues(
          [false, true, false],
          "Save button deselects immediately."
        )
        self.saveButtonAccessibilityValue.assertValues(["Unsaved", "Saved", "Unsaved"])

        await self.advance(by: .milliseconds(500))

        self.saveButtonSelected.assertValues(
          [false, true, false],
          "The save button remains unselected."
        )
        self.saveButtonAccessibilityValue.assertValues(["Unsaved", "Saved", "Unsaved"])

        self.showProjectSavedAlert.assertValueCount(1, "The save project prompt only showed for starring.")
      }
    }
  }

  func testLoggedInUser_WatchEndingSoonProject() async {
    AppEnvironment.login(.init(accessToken: "deadbeef", user: .template))

    let project = .template
      |> Project.lens.personalization.isStarred .~ false
      |> Project.lens.dates.deadline .~ (MockDate().date.timeIntervalSince1970 + 60.0 * 60.0 * 24.0)

    await withEnvironment(apiService: MockService(watchProjectMutationResult: .success(.watchTemplate))) {
      self.vm.configure(with: (project, .project, nil))
      self.vm.viewDidLoad()

      self.vm.saveButtonTapped(selected: false)

      XCTAssertEqual(
        ["CTA Clicked"],
        self.segmentTrackingClient.events
      )
      XCTAssertEqual(["project"], self.segmentTrackingClient.properties(forKey: "context_page"))
      XCTAssertEqual(["watch_project"], self.segmentTrackingClient.properties(forKey: "context_cta"))
      XCTAssertEqual(["watch"], self.segmentTrackingClient.properties(forKey: "context_type"))

      await self.advance(by: .milliseconds(500))

      self.showProjectSavedAlert.assertValueCount(
        0, "The save project prompt doesn't show cause it's less than 48hrs."
      )
    }
  }

  func testPostNotificationEmits_WhenProjectIsSavedSuccessfully() async {
    AppEnvironment.login(.init(accessToken: "deadbeef", user: .template))

    let project = Project.template
      |> Project.lens.personalization.isStarred .~ false
      |> Project.lens.watchesCount .~ 8

    await withEnvironment(apiService: MockService(watchProjectMutationResult: .success(.watchTemplate))) {
      self.vm.configure(with: (project, .project, nil))
      self.vm.viewDidLoad()

      self.postNotificationWithProject.assertValueCount(1)
      XCTAssertEqual(self.postNotificationWithProject.lastValue!.watchesCount, 8)

      self.vm.saveButtonTapped(selected: false)
      await self.advance(by: .milliseconds(500))

      self.postNotificationWithProject.assertValueCount(3)
      XCTAssertEqual(self.postNotificationWithProject.lastValue!.watchesCount, 10)
    }
  }

  func testWatchProjectTracking_DiscoverContext() async {
    await withEnvironment {
      self.vm.configure(with: (.template, .discovery, DiscoveryParams.recommendedDefaults))
      self.vm.viewDidLoad()

      self.vm.saveButtonTapped(selected: false)

      XCTAssertEqual(
        ["CTA Clicked"],
        self.segmentTrackingClient.events
      )
      XCTAssertEqual(["discover"], self.segmentTrackingClient.properties(forKey: "context_page"))
      XCTAssertEqual(["watch_project"], self.segmentTrackingClient.properties(forKey: "context_cta"))
      XCTAssertEqual(["watch"], self.segmentTrackingClient.properties(forKey: "context_type"))
    }
  }
}

@MainActor
private final class WatchTestClock {
  private var now: TimeInterval = 0
  private var sleepers: [UUID: (deadline: TimeInterval, continuation: CheckedContinuation<Void, Error>)] = [:]

  func sleep(_ seconds: TimeInterval) async throws {
    try Task.checkCancellation()
    guard seconds > 0 else { return }
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          self.sleepers[id] = (self.now + seconds, continuation)
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.sleepers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
      }
    }
    try Task.checkCancellation()
  }

  func advance(by seconds: TimeInterval) async {
    await Task.yield()
    self.now += seconds
    let due = self.sleepers.filter { $0.value.deadline <= self.now }.map(\.key)
    for id in due { self.sleepers.removeValue(forKey: id)?.continuation.resume() }
    await Task.yield()
  }
}

private final class WatchRecording<Value> {
  private(set) var values: [Value] = []
  var lastValue: Value? { self.values.last }
  func append(_ value: Value) { self.values.append(value) }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, message, file: file, line: line)
  }
  func assertDidEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(self.values.isEmpty, message, file: file, line: line)
  }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
}
private extension WatchRecording where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
