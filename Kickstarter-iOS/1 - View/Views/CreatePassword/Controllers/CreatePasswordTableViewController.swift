
import Observation
import Prelude
import UIKit

enum CreatePasswordRow: CaseIterable {
  case newPassword
  case confirmNewPassword
}

extension CreatePasswordRow {
  var placeholder: String {
    return Strings.signup_input_fields_password()
  }

  var returnKeyType: UIReturnKeyType {
    switch self {
    case .newPassword: return .next
    case .confirmNewPassword: return .done
    }
  }

  var title: String {
    switch self {
    case .newPassword: return Strings.New_password()
    case .confirmNewPassword: return Strings.Confirm_password()
    }
  }
}

@MainActor
@objc protocol CreatePasswordTableViewControllerType {
  @objc optional func newPasswordTextFieldChanged(_ sender: UITextField)
  @objc optional func newPasswordTextFieldDidReturn(_ sender: UITextField)
  @objc optional func newPasswordConfirmationTextFieldChanged(_ sender: UITextField)
  @objc optional func newPasswordConfirmationTextFieldDidReturn(_ sender: UITextField)
}

@MainActor
protocol CreatePasswordTableViewControllerDelegate: AnyObject {
  func createPasswordTableViewController(
    _ viewController: CreatePasswordTableViewController,
    setSaveButtonIsEnabled isEnabled: Bool
  )
  func createPasswordTableViewControllerStartAnimatingSaveButton(
    _ viewController: CreatePasswordTableViewController
  )
  func createPasswordTableViewControllerStopAnimatingSaveButton(
    _ viewController: CreatePasswordTableViewController
  )
  func createPasswordTableViewController(
    _ viewController: CreatePasswordTableViewController,
    showErrorMessage message: String
  )
}

final class CreatePasswordTableViewController: UITableViewController {
  // MARK: - Properties

  private let viewModel = CreatePasswordViewModel()
  weak var delegate: CreatePasswordTableViewControllerDelegate?
  private weak var newPasswordTextField: UITextField?
  private weak var newPasswordConfirmationTextField: UITextField?
  private weak var groupedFooterView: SettingsGroupedFooterView?

  // MARK: - Lifecycle

  static func instantiate() -> CreatePasswordTableViewController {
    return CreatePasswordTableViewController(style: .grouped)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.tableView.registerHeaderFooterClass(SettingsGroupedHeaderView.self)
    self.tableView.registerHeaderFooterClass(SettingsGroupedFooterView.self)
    self.tableView.registerCellClass(SettingsTextInputCell.self)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    self.viewModel.viewDidAppear()
  }

  // MARK: - Styles

  override func bindStyles() {
    super.bindStyles()

    _ = self.tableView
      |> settingsGroupedTableViewStyle
      |> \.allowsSelection .~ true
  }

  // MARK: - View model

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onAccessibilityFocus = { [weak self] in
      UIAccessibility.post(notification: .layoutChanged, argument: self?.groupedFooterView?.label)
    }
    self.viewModel.onFocusCell = { [weak self] indexPath in
      (self?.tableView.cellForRow(at: indexPath) as? SettingsTextInputCell)?.textField.becomeFirstResponder()
    }
    self.viewModel.onFailure = { [weak self] message in
      guard let self else { return }
      self.delegate?.createPasswordTableViewController(self, showErrorMessage: message)
    }
    self.viewModel.onSuccess = { [weak self] in
      guard let self else { return }
      logoutAndDismiss(viewController: self)
    }
    self.viewModel.onDismissKeyboard = { [weak self] in self?.tableView.endEditing(true) }
    self.viewModel.onFocusPassword = { [weak self] in self?.newPasswordTextField?.becomeFirstResponder() }
    self.viewModel.onFocusConfirmation = { [weak self] in self?.newPasswordConfirmationTextField?.becomeFirstResponder() }
    self.viewModel.onResignConfirmation = { [weak self] in self?.newPasswordConfirmationTextField?.resignFirstResponder() }
    self.observeState()
  }

  private func observeState() {
    withObservationTracking {
      let loading = self.viewModel.isLoading
      let enabled = self.viewModel.saveButtonIsEnabled
      let validation = self.viewModel.validationLabelText
      if loading { self.delegate?.createPasswordTableViewControllerStartAnimatingSaveButton(self) }
      else { self.delegate?.createPasswordTableViewControllerStopAnimatingSaveButton(self) }
      self.delegate?.createPasswordTableViewController(self, setSaveButtonIsEnabled: enabled)
      self.groupedFooterView?.isHidden = validation == nil
      UIView.performWithoutAnimation {
        self.tableView.beginUpdates()
        self.groupedFooterView?.label.text = validation
        self.tableView.endUpdates()
      }
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeState() }
    }
  }

  // MARK: - Actions

  @objc func saveButtonTapped(_: Any) {
    self.viewModel.saveButtonTapped()
  }

  // MARK: - UITableViewDataSource

  override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
    return CreatePasswordRow.allCases.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withClass: SettingsTextInputCell.self, for: indexPath)

    guard let textInputCell = cell as? SettingsTextInputCell else { return cell }

    let row = CreatePasswordRow.allCases[indexPath.row]

    textInputCell.configure(with: row.placeholder, returnKeyType: row.returnKeyType, title: row.title)
    textInputCell.configure(with: textFieldTargetActions(for: self, row: row))

    return textInputCell
  }

  // MARK: - UITableViewDelegate

  override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
    self.viewModel.cellAtIndexPathShouldBecomeFirstResponder(indexPath)
  }

  override func tableView(_ tableView: UITableView, viewForHeaderInSection _: Int) -> UIView? {
    let className = SettingsGroupedHeaderView.self

    guard let headerView = tableView.dequeueReusableHeaderFooterView(withClass: className)
      as? SettingsGroupedHeaderView else { return nil }

    let text = Strings.Well_ask_you_to_sign_back_into_the_Kickstarter_app_once_youve_changed_your_password()

    _ = headerView.label
      |> \.text .~ text

    return headerView
  }

  override func tableView(_ tableView: UITableView, viewForFooterInSection _: Int) -> UIView? {
    let className = SettingsGroupedFooterView.self
    guard let footerView = tableView.dequeueReusableHeaderFooterView(withClass: className)
      as? SettingsGroupedFooterView else { return nil }

    _ = footerView.label
      |> \.text .~ self.viewModel.validationLabelText

    return footerView
  }

  override func tableView(_: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    guard let textInputCell = cell as? SettingsTextInputCell else { return }

    let row = CreatePasswordRow.allCases[indexPath.row]
    switch row {
    case .newPassword:
      self.newPasswordTextField = textInputCell.textField
    case .confirmNewPassword:
      self.newPasswordConfirmationTextField = textInputCell.textField
    }
  }

  override func tableView(_: UITableView, willDisplayFooterView view: UIView, forSection _: Int) {
    guard let groupedFooterView = view as? SettingsGroupedFooterView else { return }

    self.groupedFooterView = groupedFooterView
  }
}

extension CreatePasswordTableViewController: CreatePasswordTableViewControllerType {
  @objc func newPasswordTextFieldChanged(_ sender: UITextField) {
    self.viewModel.newPasswordTextFieldChanged(text: sender.text)
  }

  @objc func newPasswordTextFieldDidReturn(_: UITextField) {
    self.viewModel.newPasswordTextFieldDidReturn()
  }

  @objc func newPasswordConfirmationTextFieldChanged(_ sender: UITextField) {
    self.viewModel.newPasswordConfirmationTextFieldChanged(text: sender.text)
  }

  @objc func newPasswordConfirmationTextFieldDidReturn(_: UITextField) {
    self.viewModel.newPasswordConfirmationTextFieldDidReturn()
  }
}

func textFieldTargetActions(
  for controller: CreatePasswordTableViewControllerType,
  row: CreatePasswordRow
) -> [TextFieldTargetAction] {
  let changedSelector: Selector
  let didReturnSelector: Selector

  switch row {
  case .newPassword:
    changedSelector = #selector(controller.newPasswordTextFieldChanged(_:))
    didReturnSelector = #selector(controller.newPasswordTextFieldDidReturn(_:))
  case .confirmNewPassword:
    changedSelector = #selector(controller.newPasswordConfirmationTextFieldChanged(_:))
    didReturnSelector = #selector(controller.newPasswordConfirmationTextFieldDidReturn(_:))
  }

  return [
    (controller.self, changedSelector, .editingChanged),
    (controller.self, didReturnSelector, .editingDidEndOnExit)
  ]
}
