import KsApi
import Observation

@MainActor
@Observable
public final class ResetPasswordViewModel {
  public private(set) var email: String?
  public private(set) var formIsValid = false
  public var onResetSuccess: ((String) -> Void)?
  public var onError: ((String) -> Void)?
  public var onReturnToLogin: (() -> Void)?

  private let authenticationFeature: AuthenticationFeature
  private var resetTask: Task<Void, Never>?
  private var revision = 0

  public init(authenticationFeature: AuthenticationFeature? = nil) {
    self.authenticationFeature = authenticationFeature ?? AppModel.shared.authenticationFeature
  }
  public func viewDidLoad() { self.formIsValid = isValidEmail(self.email ?? "") }
  public func emailChanged(_ email: String?) {
    self.email = email
    self.formIsValid = isValidEmail(email ?? "")
  }
  public func confirmResetButtonPressed() { self.onReturnToLogin?() }
  public func resetButtonPressed() {
    guard let email = self.email else { return }
    self.resetTask?.cancel()
    self.revision += 1
    let revision = self.revision
    self.resetTask = Task { [weak self, authenticationFeature] in
      do {
        try await authenticationFeature.resetPassword(email: email)
        try Task.checkCancellation()
        guard self?.revision == revision else { return }
        self?.onResetSuccess?(
          Strings.forgot_password_we_sent_an_email_to_email_address_with_instructions_to_reset_your_password(email: email)
        )
      } catch {
        guard let self, !Task.isCancelled, !(error is CancellationError), self.revision == revision else { return }
        let message = (error as? ErrorEnvelope)?.httpCode == 404
          ? Strings.forgot_password_error() : Strings.general_error_something_wrong()
        self.onError?(message)
      }
    }
  }
  internal func waitForReset() async { await self.resetTask?.value }
}
