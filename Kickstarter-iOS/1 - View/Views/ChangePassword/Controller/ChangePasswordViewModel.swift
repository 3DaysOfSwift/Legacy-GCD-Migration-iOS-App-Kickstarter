import Foundation
import KsApi
import Observation

@MainActor
@Observable
public final class ChangePasswordViewModel {
  public private(set) var isLoading = false
  public private(set) var saveButtonIsEnabled = false
  public private(set) var validationMessage = ""
  public var onAccessibilityFocus: (() -> Void)?
  public var onFocusCurrent: (() -> Void)?
  public var onFocusNew: (() -> Void)?
  public var onFocusConfirmation: (() -> Void)?
  public var onDismissKeyboard: (() -> Void)?
  public var onSuccess: (() -> Void)?
  public var onFailure: ((String) -> Void)?

  private let settingsFeature: SettingsFeature
  private let sleep: (TimeInterval) async throws -> Void
  private var currentPassword = ""
  private var newPassword = ""
  private var confirmation = ""
  private var hasConfirmation = false
  private var saveTasks: [UUID: Task<Void, Never>] = [:]

  public init(settingsFeature: SettingsFeature? = nil, sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
    if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
  }) {
    self.settingsFeature = settingsFeature ?? AppModel.shared.settingsFeature
    self.sleep = sleep
  }
  public func viewDidAppear() { self.validationMessage = ""; self.onFocusCurrent?() }
  public func currentPasswordFieldTextChanged(text: String) { self.currentPassword = text; self.updateValidation(showMessage: false) }
  public func currentPasswordFieldDidReturn(currentPassword: String) {
    self.currentPasswordFieldTextChanged(text: currentPassword)
    self.onFocusNew?()
  }
  public func newPasswordFieldTextChanged(text: String) { self.newPassword = text; self.updateValidation(showMessage: true) }
  public func newPasswordFieldDidReturn(newPassword: String) {
    self.newPasswordFieldTextChanged(text: newPassword)
    self.onFocusConfirmation?()
  }
  public func newPasswordConfirmationFieldTextChanged(text: String) { self.confirmation = text; self.hasConfirmation = true; self.updateValidation(showMessage: true) }
  public func newPasswordConfirmationFieldDidReturn(newPasswordConfirmed: String) {
    self.newPasswordConfirmationFieldTextChanged(text: newPasswordConfirmed)
    self.onDismissKeyboard?()
    if self.saveButtonIsEnabled { self.submit() }
  }
  public func saveButtonTapped() { self.onDismissKeyboard?(); self.submit() }
  private func updateValidation(showMessage: Bool) {
    let length = passwordLengthValid(self.newPassword)
    let match = self.newPassword == self.confirmation
    self.saveButtonIsEnabled = passwordFormValid((
      notEmpty: !self.currentPassword.isEmpty && !self.newPassword.isEmpty && !self.confirmation.isEmpty,
      match: match, length: length
    ))
    if showMessage {
      self.validationMessage = (self.hasConfirmation
        ? passwordValidationText((length: length, match: match))
        : passwordValidationText(length)) ?? ""
      if !self.validationMessage.isEmpty && AppEnvironment.current.isVoiceOverRunning() { self.onAccessibilityFocus?() }
    }
  }
  private func submit() {
    let input = ChangePasswordInput(currentPassword: self.currentPassword, newPassword: self.newPassword,
                                    newPasswordConfirmation: self.confirmation)
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let id = UUID()
    self.isLoading = true
    self.saveTasks[id] = Task { [weak self, settingsFeature, sleep] in
      do {
        _ = try await settingsFeature.updateAccount(.password(input))
        try await sleep(delay)
        try Task.checkCancellation()
        guard let self else { return }
        self.saveTasks[id] = nil
        self.isLoading = !self.saveTasks.isEmpty
        self.onSuccess?()
      } catch {
        guard let self else { return }
        self.saveTasks[id] = nil
        self.isLoading = !self.saveTasks.isEmpty
        guard !Task.isCancelled, !(error is CancellationError) else { return }
        self.onFailure?((error as? ErrorEnvelope)?.localizedDescription ?? error.localizedDescription)
      }
    }
  }
  internal func waitForSaves() async {
    while let task = self.saveTasks.values.first { await task.value }
  }
}
