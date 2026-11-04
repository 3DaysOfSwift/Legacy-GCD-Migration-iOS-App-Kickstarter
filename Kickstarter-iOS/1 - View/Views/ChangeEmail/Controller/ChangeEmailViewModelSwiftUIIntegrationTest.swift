import Foundation
import KsApi
import Observation

@MainActor
@Observable
final class ChangeEmailScreenModel {
  var currentEmail = ""
  var newEmail = ""
  var password = ""
  var hideVerifyView = true
  var verifyEmailButtonTitle = ""
  var hideMessageLabel = true
  var warningMessageWithAlert = ("", false)
  var isLoading = false
  var banner: MessageBannerViewViewModel?
  private(set) var bannerRevision = 0

  var saveEnabled: Bool {
    isValidEmail(self.newEmail) && self.newEmail != self.currentEmail &&
      !self.newEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !self.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private let feature: SettingsFeature
  private let sleep: (TimeInterval) async throws -> Void
  private var loadTask: Task<Void, Never>?
  private var saveTask: Task<Void, Never>?
  private var verifyTask: Task<Void, Never>?
  private var loadRevision = 0
  private var saveRevision = 0
  private var verifyRevision = 0

  init(feature: SettingsFeature? = nil, sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
    if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
  }) {
    self.feature = feature ?? AppModel.shared.settingsFeature
    self.sleep = sleep
  }

  func viewDidLoad() {
    self.verifyEmailButtonTitle = AppEnvironment.current.currentUser.map {
      $0.isCreator ? Strings.Resend_verification_email() : Strings.Send_verfication_email()
    } ?? ""
    self.hideVerifyView = true
    self.loadTask?.cancel()
    self.loadRevision += 1
    let revision = self.loadRevision
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.loadTask = Task { [weak self, feature, sleep] in
      do {
        let user = try await feature.emailUser()
        try await sleep(delay)
        try Task.checkCancellation()
        guard let self, self.loadRevision == revision else { return }
        self.currentEmail = user.email ?? ""
        if let verified = user.isEmailVerified, let deliverable = user.isDeliverable {
          self.hideVerifyView = verified && deliverable
          self.hideMessageLabel = verified && deliverable
          if !deliverable { self.warningMessageWithAlert = (Strings.We_ve_been_unable_to_send_email(), true) }
          else if !verified { self.warningMessageWithAlert = (Strings.Email_unverified(), false) }
        }
      } catch { }
    }
  }

  func save() {
    guard self.saveEnabled else { return }
    let input = ChangeEmailInput(email: self.newEmail, currentPassword: self.password)
    self.saveTask?.cancel()
    self.saveRevision += 1
    let revision = self.saveRevision
    self.isLoading = true
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.saveTask = Task { [weak self, feature, sleep] in
      do {
        _ = try await feature.updateAccount(.email(input))
        try await sleep(delay)
        try Task.checkCancellation()
        guard let self, self.saveRevision == revision else { return }
        self.currentEmail = input.email
        self.newEmail = ""
        self.password = ""
        self.isLoading = false
        self.banner = MessageBannerViewViewModel((type: .success, message: Strings.Got_it_your_changes_have_been_saved()))
        self.bannerRevision += 1
      } catch {
        guard let self, !Task.isCancelled, !(error is CancellationError), self.saveRevision == revision else { return }
        do { try await sleep(delay); try Task.checkCancellation() } catch { return }
        guard self.saveRevision == revision else { return }
        self.newEmail = ""
        self.password = ""
        self.isLoading = false
        self.banner = MessageBannerViewViewModel((type: .error, message: (error as? ErrorEnvelope)?.localizedDescription ?? error.localizedDescription))
        self.bannerRevision += 1
      }
    }
  }

  func resendVerificationEmail() {
    self.verifyTask?.cancel()
    self.verifyRevision += 1
    let revision = self.verifyRevision
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.verifyTask = Task { [weak self, feature, sleep] in
      do {
        _ = try await feature.updateAccount(.sendVerification)
        try await sleep(delay)
        try Task.checkCancellation()
        guard let self, self.verifyRevision == revision else { return }
        self.banner = MessageBannerViewViewModel((type: .success, message: Strings.Verification_email_sent()))
        self.bannerRevision += 1
      } catch {
        guard let self, !Task.isCancelled, !(error is CancellationError), self.verifyRevision == revision else { return }
        do { try await sleep(delay); try Task.checkCancellation() } catch { return }
        guard self.verifyRevision == revision else { return }
        self.banner = MessageBannerViewViewModel((type: .error, message: (error as? ErrorEnvelope)?.localizedDescription ?? error.localizedDescription))
        self.bannerRevision += 1
      }
    }
  }
  func waitForLoad() async { await self.loadTask?.value }
  func waitForSave() async { await self.saveTask?.value }
  func waitForVerification() async { await self.verifyTask?.value }
}
