@testable import Kickstarter_iOS
@testable import KsApi
import Prelude
import XCTest

@MainActor
final class ChangeEmailScreenModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var model = ChangeEmailScreenModel(feature: self.feature, sleep: { _ in })

  override func setUp() async throws {
    try await super.setUp()
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture", user: .template))
  }

  func testLoadsEmailAndSavesChange() async throws {
    let envelope = try XCTUnwrap(UserEnvelope<GraphUser>.userEnvelope(from: GraphUserEnvelopeTemplates.fetchUser))
    let service = MockService(changeEmailResult: .success(EmptyResponseEnvelope()), fetchGraphUserResult: .success(envelope))
    await withEnvironment(apiService: service, currentUser: .template) {
      self.model.viewDidLoad()
      await self.model.waitForLoad()
      XCTAssertEqual(self.model.currentEmail, envelope.me.email ?? "")
      self.model.newEmail = "new@example.com"
      self.model.password = "password"
      XCTAssertTrue(self.model.saveEnabled)
      self.model.save()
      XCTAssertTrue(self.model.isLoading)
      await self.model.waitForSave()
      XCTAssertFalse(self.model.isLoading)
      XCTAssertEqual(self.model.currentEmail, "new@example.com")
      XCTAssertTrue(self.model.newEmail.isEmpty)
      XCTAssertTrue(self.model.password.isEmpty)
      XCTAssertEqual(self.model.banner?.bannerMessage, Strings.Got_it_your_changes_have_been_saved())
    }
  }

  func testVerificationStatesAndCreatorLabel() async {
    for (verified, deliverable) in [(true, true), (false, true), (true, false), (false, false)] {
      let user = GraphUser.template |> \.isEmailVerified .~ verified |> \.isDeliverable .~ deliverable
      let creator = User.template |> \.stats.createdProjectsCount .~ 1
      let service = MockService(fetchGraphUserResult: .success(UserEnvelope(me: user)))
      await withEnvironment(apiService: service, currentUser: creator) {
        self.model.viewDidLoad()
        await self.model.waitForLoad()
        XCTAssertEqual(self.model.hideVerifyView, verified && deliverable)
        XCTAssertEqual(self.model.hideMessageLabel, verified && deliverable)
        XCTAssertEqual(self.model.verifyEmailButtonTitle, Strings.Resend_verification_email())
        if !deliverable {
          XCTAssertEqual(self.model.warningMessageWithAlert.0, Strings.We_ve_been_unable_to_send_email())
          XCTAssertTrue(self.model.warningMessageWithAlert.1)
        } else if !verified {
          XCTAssertEqual(self.model.warningMessageWithAlert.0, Strings.Email_unverified())
          XCTAssertFalse(self.model.warningMessageWithAlert.1)
        }
      }
    }
  }

  func testResendVerificationSuccessAndFailure() async {
    let error = ErrorEnvelope.couldNotParseJSON
    for succeeds in [true, false] {
      let service = MockService(sendEmailVerificationResult: succeeds ? .success(EmptyResponseEnvelope()) : .failure(error))
      await withEnvironment(apiService: service, currentUser: .template) {
        self.model.resendVerificationEmail()
        await self.model.waitForVerification()
        XCTAssertEqual(self.model.banner?.bannerMessage, succeeds ? Strings.Verification_email_sent() : error.localizedDescription)
      }
    }
  }

  func testInvalidEmailAndFailedSave() async {
    let error = ErrorEnvelope(errorMessages: ["Failed"], ksrCode: nil, httpCode: 400, exception: nil)
    await withEnvironment(apiService: MockService(changeEmailResult: .failure(error)), currentUser: .template) {
      self.model.currentEmail = "old@example.com"
      self.model.newEmail = "invalid"
      self.model.password = "password"
      XCTAssertFalse(self.model.saveEnabled)
      self.model.newEmail = "new@example.com"
      XCTAssertTrue(self.model.saveEnabled)
      self.model.save()
      await self.model.waitForSave()
      XCTAssertEqual(self.model.currentEmail, "old@example.com")
      XCTAssertNotNil(self.model.banner)
      XCTAssertFalse(self.model.isLoading)
    }
  }
}
