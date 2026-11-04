import MessageUI

public enum HelpContext {
  case loginTout
  case facebookConfirmation
  case settings
  case signup

  public var trackingString: String {
    switch self {
    case .loginTout:
      return "Login Tout"
    case .facebookConfirmation:
      return "Facebook Confirmation"
    case .settings:
      return "Settings"
    case .signup:
      return "Signup"
    }
  }
}

@MainActor
public final class HelpViewModel {
  public var onNoEmailError: ((UIAlertController) -> Void)?
  public var onHelpSheet: (([HelpType]) -> Void)?
  public var onMailCompose: (() -> Void)?
  public var onWebHelp: ((HelpType) -> Void)?
  private var mailAvailable: Bool?

  public init() {}
  public func canSendEmail(_ canSend: Bool) { self.mailAvailable = canSend }
  public func configureWith(helpContext _: HelpContext) {}
  public func mailComposeCompletion(result _: MFMailComposeResult) {}
  public func showHelpSheetButtonTapped() {
    self.onHelpSheet?([.howItWorks, .contact, .terms, .privacy, .cookie])
  }
  public func helpTypeButtonTapped(_ helpType: HelpType) {
    guard helpType == .contact else { self.onWebHelp?(helpType); return }
    guard let available = self.mailAvailable else { return }
    if available { self.onMailCompose?() }
    else { self.onNoEmailError?(noEmailError()) }
  }
}

@MainActor
private func noEmailError() -> UIAlertController {
  let alertController = UIAlertController(
    title: Strings.support_email_noemail_title(),
    message: Strings.support_email_noemail_message(),
    preferredStyle: .alert
  )
  alertController.addAction(
    UIAlertAction(
      title: Strings.general_alert_buttons_ok(),
      style: .cancel,
      handler: nil
    )
  )

  return alertController
}
