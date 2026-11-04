import Foundation
import KsApi
import Observation

@MainActor
@Observable
public final class CreatePasswordViewModel {
  public private(set) var isLoading = false
  public private(set) var saveButtonIsEnabled = false
  public private(set) var validationLabelText: String?
  public var onAccessibilityFocus: (() -> Void)?
  public var onFocusCell: ((IndexPath) -> Void)?
  public var onFocusPassword: (() -> Void)?
  public var onFocusConfirmation: (() -> Void)?
  public var onResignConfirmation: (() -> Void)?
  public var onDismissKeyboard: (() -> Void)?
  public var onSuccess: (() -> Void)?
  public var onFailure: ((String) -> Void)?

  private let settingsFeature: SettingsFeature
  private let sleep: (TimeInterval) async throws -> Void
  private var password: String?
  private var confirmation: String?
  private var appeared = false
  private var focusedIndex: IndexPath?
  private var saveTask: Task<Void, Never>?
  private var revision = 0

  public init(settingsFeature: SettingsFeature? = nil, sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
    if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
  }) {
    self.settingsFeature = settingsFeature ?? AppModel.shared.settingsFeature
    self.sleep = sleep
  }
  public func viewDidAppear() {
    self.appeared = true
    self.validationLabelText = nil
    self.onFocusPassword?()
    if let focusedIndex = self.focusedIndex { self.onFocusCell?(focusedIndex) }
  }
  public func cellAtIndexPathShouldBecomeFirstResponder(_ indexPath: IndexPath?) {
    self.focusedIndex = indexPath
    if self.appeared, let indexPath { self.onFocusCell?(indexPath) }
  }
  public func newPasswordTextFieldChanged(text: String?) {
    self.password = text
    self.updateValidation()
  }
  public func newPasswordConfirmationTextFieldChanged(text: String?) {
    self.confirmation = text
    self.updateValidation()
  }
  private func updateValidation() {
    guard let password = self.password else { return }
    let validLength = passwordLengthValid(password)
    if let confirmation = self.confirmation {
      self.validationLabelText = passwordValidationText((length: validLength, match: password == confirmation))
      self.saveButtonIsEnabled = passwordFormValid((notEmpty: !password.isEmpty && !confirmation.isEmpty,
                                                     match: password == confirmation, length: validLength))
    } else {
      self.validationLabelText = passwordValidationText(validLength)
      self.saveButtonIsEnabled = false
    }
    if self.validationLabelText != nil && AppEnvironment.current.isVoiceOverRunning() { self.onAccessibilityFocus?() }
  }
  public func newPasswordTextFieldDidReturn() { self.onFocusConfirmation?() }
  public func newPasswordConfirmationTextFieldDidReturn() {
    self.onResignConfirmation?()
    self.submit()
  }
  public func saveButtonTapped() { self.submit() }
  private func submit() {
    self.onDismissKeyboard?()
    guard self.saveButtonIsEnabled, let password = self.password, let confirmation = self.confirmation else { return }
    self.saveTask?.cancel()
    self.revision += 1
    let revision = self.revision
    let input = CreatePasswordInput(password: password, passwordConfirmation: confirmation)
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.isLoading = true
    self.saveTask = Task { [weak self, settingsFeature, sleep] in
      do {
        _ = try await settingsFeature.updateAccount(.initialPassword(input))
        try await sleep(delay)
        try Task.checkCancellation()
        guard let self, self.revision == revision else { return }
        self.isLoading = false
        self.onSuccess?()
      } catch {
        guard let self, !Task.isCancelled, !(error is CancellationError), self.revision == revision else { return }
        self.isLoading = false
        self.onFailure?((error as? ErrorEnvelope)?.localizedDescription ?? error.localizedDescription)
      }
    }
  }
  internal func waitForSave() async { await self.saveTask?.value }
}
