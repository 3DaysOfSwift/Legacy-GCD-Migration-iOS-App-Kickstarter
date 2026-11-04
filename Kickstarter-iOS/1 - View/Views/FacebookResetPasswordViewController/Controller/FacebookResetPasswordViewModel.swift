import KsApi
import Observation

@MainActor
@Observable
public final class FacebookResetPasswordViewModel {
  public private(set) var isLoading = false
  public private(set) var isValid = false
  public var onFailure: ((String) -> Void)?
  public var onSuccess: ((String) -> Void)?
  private let authenticationFeature: AuthenticationFeature
  private var email = ""
  private var resetTask: Task<Void, Never>?
  private var revision = 0

  public init(authenticationFeature: AuthenticationFeature? = nil) {
    self.authenticationFeature = authenticationFeature ?? AppModel.shared.authenticationFeature
  }
  public func emailTextFieldFieldDidChange(_ text: String) {
    self.email = text
    self.isValid = isValidEmail(text)
  }
  public func emailTextFieldFieldDidReturn() { self.submit() }
  public func setPasswordButtonPressed() { self.submit() }
  private func submit() {
    guard self.isValid else { return }
    self.resetTask?.cancel()
    self.revision += 1
    let revision = self.revision
    let email = self.email
    self.isLoading = true
    self.resetTask = Task { [weak self, authenticationFeature] in
      do {
        try await authenticationFeature.resetPassword(email: email)
        try Task.checkCancellation()
        guard let self, self.revision == revision else { return }
        self.isLoading = false
        self.onSuccess?(Strings.forgot_password_we_sent_an_email_to_email_address_with_instructions_to_reset_your_password(email: email))
      } catch {
        guard let self, !Task.isCancelled, !(error is CancellationError), self.revision == revision else { return }
        self.isLoading = false
        self.onFailure?((error as? ErrorEnvelope)?.errorMessages.last ?? Strings.general_error_something_wrong())
      }
    }
  }
  internal func waitForReset() async { await self.resetTask?.value }
}
