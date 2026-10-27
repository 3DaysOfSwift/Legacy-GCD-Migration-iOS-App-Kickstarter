import Foundation
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@MainActor
internal final class SettingsNewsletterCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = SettingsNewsletterCellViewModel(feature: self.feature)

  let showOptInPrompt = TestObserver<String, Never>()
  let subscribeToAllSwitchIsOn = TestObserver<Bool?, Never>()
  let switchIsOn = TestObserver<Bool?, Never>()
  let unableToSaveError = TestObserver<String, Never>()
  let updateCurrentUser = TestObserver<User, Never>()

  internal override func setUp() {
    super.setUp()
    MainActor.assumeIsolated {
      // Settings is a signed-in flow; the original fixtures omitted authentication.
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
      self.vm.outputs.showOptInPrompt.observe(self.showOptInPrompt.observer)
      self.vm.outputs.subscribeToAllSwitchIsOn.observe(self.subscribeToAllSwitchIsOn.observer)
      self.vm.outputs.switchIsOn.observe(self.switchIsOn.observer)
      self.vm.outputs.unableToSaveError.observe(self.unableToSaveError.observer)
      self.vm.outputs.updateCurrentUser.observe(self.updateCurrentUser.observer)
    }
  }

  override func tearDown() async throws {
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  func test_SubscribeToAll_Toggled() async {
    let user = User.template
      |> \.newsletters .~ User.NewsletterSubscriptions.all(on: true)

    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: user))

    self.vm.inputs.configureWith(value: user)
    self.subscribeToAllSwitchIsOn.assertValue(true)
  }

  func test_SubscribeToAll_Untoggled_IfAtLeastOneNewsletterIsUntoggled() async {
    let user = User.template
      |> \.newsletters.arts .~ nil

    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: user))

    self.vm.inputs.configureWith(value: user)
    self.subscribeToAllSwitchIsOn.assertValue(false)
  }

  func test_ArtsNewsletters_Toggled() async {
    self.assertValue(for: .arts)
  }

  func test_ProjectsWeLoveNewsletters_Toggled() async {
    self.assertValue(for: .weekly)
  }

  func test_NewsAndEventsNewsletters_Toggled() async {
    self.assertValue(for: .promo)
  }

  func test_GamesNewsletters_Toggled() async {
    self.assertValue(for: .games)
  }

  func test_HappeningNewsletters_Toggled() async {
    self.assertValue(for: .happening)
  }

  func test_InventNewsletters_Toggled() async {
    self.assertValue(for: .invent)
  }

  func test_FilmsNewsletters_Toggled() async {
    self.assertValue(for: .films)
  }

  func test_PublishingNewsletters_Toggled() async {
    self.assertValue(for: .publishing)
  }

  func test_AlumniNewsletters_Toggled() async {
    self.assertValue(for: .alumni)
  }

  private func assertValue(for newsletter: Newsletter) {
    let user = User.template
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: user))

    self.vm.inputs.configureWith(value: (newsletter, user))
    self.switchIsOn.assertValues([false])

    self.vm.inputs.newslettersSwitchTapped(on: true)
    let user1 = User.template |> UserAttribute.newsletter(newsletter).keyPath .~ true

    self.vm.inputs.configureWith(value: user1)

    self.switchIsOn.assertValues([false, true])

    self.vm.inputs.newslettersSwitchTapped(on: false)
    let user2 = User.template |> UserAttribute.newsletter(newsletter).keyPath .~ false

    self.vm.inputs.configureWith(value: user2)
    self.switchIsOn.assertValues([false, true, false])
  }

  func testOptInPromptNotShown() async {
    await withEnvironment(countryCode: "US") {
      let user = User.template
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: user))

      self.vm.inputs.newslettersSwitchTapped(on: true)
      self.showOptInPrompt.assertDidNotEmitValue("Non-German locale does not require double opt-in.")
    }
  }

  func testShowOptInPrompt() async {
    await withEnvironment(config: Config.deConfig) {
      let user = User.template
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: user))

      self.vm.inputs.configureWith(value: (.arts, user))

      self.vm.inputs.newslettersSwitchTapped(on: true)
      self.showOptInPrompt.assertValueCount(1, "German locale requires double opt-in.")

      self.vm.inputs.newslettersSwitchTapped(on: false)
      self.showOptInPrompt.assertValueCount(1, "Prompt not shown again when newsletter toggled off.")
    }
  }

  func testUpdateError() async {
    let error = ErrorEnvelope(
      errorMessages: ["Unable to save."],
      ksrCode: .UnknownCode,
      httpCode: 400,
      exception: nil
    )

    await withEnvironment(apiService: MockService(updateUserSelfError: error)) {
      let user = User.template
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: user))

      self.vm.inputs.configureWith(value: (.arts, user))

      self.switchIsOn.assertValues([false], "Newsletter notifications turned off as default.")

      self.vm.inputs.newslettersSwitchTapped(on: true)
      let user1 = User.template
        |> \.newsletters.arts .~ true

      self.vm.inputs.configureWith(value: user1)
      self.switchIsOn.assertValues([false, true], "Newsletter immediately turned on on tap.")

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.vm.inputs.allNewslettersSwitchTapped(on: false)
      self.unableToSaveError.assertValueCount(1, "Updating user errored.")

      self.switchIsOn.assertValues([false, true], "Did not successfully save preference.")
    }
  }

  func testUpdateUser() async {
    let user = User.template
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: user))

    self.vm.inputs.configureWith(value: (.games, user))

    self.updateCurrentUser.assertValueCount(0, "Begin with environment's current user.")

    self.vm.inputs.newslettersSwitchTapped(on: true)

    await self.feature.waitForOperations()

    await self.scheduler.advance()

    self.updateCurrentUser.assertValueCount(1, "User should be updated.")

    self.vm.inputs.newslettersSwitchTapped(on: false)

    await self.feature.waitForOperations()

    await self.scheduler.advance()

    self.updateCurrentUser.assertValueCount(2, "User should be updated.")
  }
}
