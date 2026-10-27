@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import ReactiveExtensions
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@MainActor
final class FacebookConfirmationViewModelTests: TestCase {
  // Logic-only coverage; visual suites retain their reference-device requirement.
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let authenticationFeature = AuthenticationFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAuthenticationProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm: FacebookConfirmationViewModelType =
    FacebookConfirmationViewModel(authenticationFeature: self.authenticationFeature)
  let displayEmail = TestObserver<String, Never>()
  let sendNewsletters = TestObserver<Bool, Never>()
  let showLogin = TestObserver<(), Never>()
  let logIntoEnvironment = TestObserver<AccessTokenEnvelope, Never>()
  let postNotification = TestObserver<Notification.Name, Never>()
  let showSignupError = TestObserver<String, Never>()

  override func setUp() {
    super.setUp()
    MainActor.assumeIsolated { self.bindOutputs() }
  }

  override func tearDown() async throws {
    await self.authenticationFeature.waitForOperations()
    try await super.tearDown()
  }

  private func bindOutputs() {
    self.vm.outputs.displayEmail.observe(self.displayEmail.observer)
    self.vm.outputs.sendNewsletters.observe(self.sendNewsletters.observer)
    self.vm.outputs.showLogin.observe(self.showLogin.observer)
    self.vm.outputs.logIntoEnvironment.observe(self.logIntoEnvironment.observer)
    self.vm.outputs.postNotification.map { $0.name }.observe(self.postNotification.observer)
    self.vm.errors.showSignupError.observe(self.showSignupError.observer)
  }

  func testDisplayEmail_whenViewDidLoad() async {
    self.vm.inputs.email("kittens@example.com")

    self.displayEmail.assertDidNotEmitValue("Email does not display")

    self.vm.inputs.viewDidLoad()

    self.displayEmail.assertValues(["kittens@example.com"], "Display email")
  }

  func testNewsletterSwitch_whenViewDidLoad() async {
    self.sendNewsletters.assertDidNotEmitValue("Newsletter toggle does not emit")

    self.vm.inputs.viewDidLoad()

    self.sendNewsletters.assertValues([false], "Newsletter toggle emits false")

    XCTAssertEqual(
      [], self.segmentTrackingClient.events,
      "Newsletter toggle is not tracked on intital state"
    )
  }

  func testNewsletterSwitch_whenViewDidLoad_German() async {
    withEnvironment(countryCode: "DE") {
      self.sendNewsletters.assertDidNotEmitValue("Newsletter toggle does not emit")

      self.vm.inputs.viewDidLoad()

      self.sendNewsletters.assertValues([false], "Newsletter toggle emits false")
    }
  }

  func testNewsletterSwitch_whenViewDidLoad_UK() async {
    await withEnvironment(countryCode: "UK") {
      self.sendNewsletters.assertDidNotEmitValue("Newsletter toggle does not emit")

      self.vm.inputs.viewDidLoad()

      self.sendNewsletters.assertValues([false], "Newsletter toggle emits false")

      XCTAssertEqual(
        [], self.segmentTrackingClient.events,
        "Newsletter toggle is not tracked on intital state"
      )
    }
  }

  func testNewsletterToggle() async {
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.sendNewslettersToggled(false)

    self.sendNewsletters.assertValues([false, false], "Newsletter is toggled off")

    self.vm.inputs.sendNewslettersToggled(true)

    self.sendNewsletters.assertValues([false, false, true], "Newsletter is toggled on")
  }

  func testCreateNewAccount_withoutNewsletterToggle() async {
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.facebookToken("PuRrrrrrr3848")
    self.vm.inputs.createAccountButtonPressed()

    await self.authenticationFeature.waitForOperations()

    await self.scheduler.advance()

    self.logIntoEnvironment.assertValueCount(1, "Account successfully created")

    self.vm.inputs.environmentLoggedIn()

    self.postNotification.assertValues(
      [.ksr_sessionStarted],
      "Login notification posted."
    )
  }

  func testCreateNewAccount_withNewsletterToggle() async {
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.facebookToken("PuRrrrrrr3848")
    self.vm.inputs.sendNewslettersToggled(true)
    self.vm.inputs.createAccountButtonPressed()

    await self.authenticationFeature.waitForOperations()

    await self.scheduler.advance()

    self.logIntoEnvironment.assertValueCount(1, "Account successfully created")

    self.vm.inputs.environmentLoggedIn()

    self.postNotification.assertValues(
      [.ksr_sessionStarted],
      "Login notification posted."
    )
  }

  func testCreateNewAccount_withError() async {
    let error = ErrorEnvelope(
      errorMessages: ["Email address has an issue. If you are not sure why, please contact us."],
      ksrCode: nil,
      httpCode: 422,
      exception: nil
    )

    await withEnvironment(apiService: MockService(signupError: error)) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.facebookToken("Meowwwww4484848")
      self.vm.inputs.createAccountButtonPressed()

      await self.authenticationFeature.waitForOperations()

      await self.scheduler.advance()

      self.logIntoEnvironment.assertValueCount(0, "Did not emit log into environment")
      self.showSignupError.assertValues(
        ["Email address has an issue. If you are not sure why, please contact us."]
      )
    }
  }

  func testCreateNewAccount_withDefaultError() async {
    let error = ErrorEnvelope(
      errorMessages: [],
      ksrCode: nil,
      httpCode: 422,
      exception: nil
    )

    await withEnvironment(apiService: MockService(signupError: error)) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.facebookToken("Meowwwww4484848")
      self.vm.inputs.createAccountButtonPressed()

      await self.authenticationFeature.waitForOperations()

      await self.scheduler.advance()

      self.logIntoEnvironment.assertValueCount(0, "Did not emit log into environment")
      self.showSignupError.assertValues(
        ["Couldn't log in with Facebook."]
      )
    }
  }

  func testShowLogin() async {
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.loginButtonPressed()

    self.showLogin.assertValueCount(1, "Show login")
  }
}
