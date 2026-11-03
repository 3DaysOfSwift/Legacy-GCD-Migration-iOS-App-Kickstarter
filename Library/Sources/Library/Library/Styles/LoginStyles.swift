import KDS
import Prelude
import Prelude_UIKit
import UIKit

@MainActor
public let createNewAccountButtonStyle: ButtonStyle = { button in
  button.applyStyleConfiguration(KSRButtonStyle.green)
  button.setTitle(Strings.Sign_up(), for: .normal)
  return button
}

@MainActor
public let disclaimerButtonStyle = UIButton.lens.titleColor(for: .normal) .~ LegacyColors.ksr_support_400
  .uiColor()
  <> UIButton.lens.titleColor(for: .highlighted) %~ { _ in
    LegacyColors.ksr_support_400.uiColor(opacity: 0.5)
  }

  <> UIButton.lens.titleLabel.font %~~ { _, label in
    label.traitCollection.isRegularRegular ? .ksr_footnote(size: 14.0) : .ksr_footnote(size: 11.0)
  }

  <> UIButton.lens.titleLabel.textAlignment .~ .center
  <> UIButton.lens.title(for: .normal) %~ { _ in
    Strings.By_signing_up_you_agree_to_our_Terms_of_Use_Privacy_Policy_and_Cookie_Policy()
  }

  <> UIButton.lens.accessibilityValue %~ { _ in Strings.general_navigation_buttons_help() }
  <> UIButton.lens.accessibilityLabel %~ { _ in
    Strings.By_signing_up_you_agree_to_our_Terms_of_Use_Privacy_Policy_and_Cookie_Policy()
  }

  <> UIButton.lens.accessibilityHint %~ { _ in Strings.Opens_help_sheet() }

@MainActor
public let showHidePasswordButtonStyle = UIButton.lens.title(for: .normal) .~ ""
  <> UIButton.lens.tintColor .~ LegacyColors.ksr_support_300.uiColor()
  <> UIButton.lens.accessibilityLabel %~ { _ in
    Strings.Password_visibility()
  }

@MainActor
public let emailFieldStyle: TextFieldStyle = { field in
  let field = formFieldStyle(field)
  field.placeholder = Strings.login_placeholder_email()
  field.keyboardType = .emailAddress
  return field
}

@MainActor
public func emailFieldAutoFillStyle(_ textField: UITextField) -> UITextField {
  return textField
    |> emailFieldStyle
    |> \.textContentType .~ .username
}

@MainActor
public let fbLoginButtonStyle: ButtonStyle = { button in
  let button = facebookButtonStyle(button)
  button.setTitle(Strings.login_tout_buttons_log_in_with_facebook(), for: .normal)
  return button
}

@MainActor
public let fbConfirmationMessageLabelStyle = UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
  <> UILabel.lens.font .~ .ksr_body()
  <> UILabel.lens
  .text %~ { _ in Strings.By_signing_up_youll_log_in_to_Kickstarter_using_your_Facebook_account() }

@MainActor
public let fbConfirmEmailLabelStyle = UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
  <> UILabel.lens.font .~ .ksr_headline()
  <> UILabel.lens.textAlignment .~ .left
  <> UILabel.lens.adjustsFontSizeToFitWidth .~ true

@MainActor
public let fbWrongAccountLabelStyle = UILabel.lens.font .~ .ksr_caption1()
  <> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
  <> UILabel.lens.text %~ { _ in Strings.facebook_confirmation_wrong_account_title() }

@MainActor
public let forgotPasswordButtonStyle =
  UIButton.lens.titleLabel.font .~ .ksr_subhead()
    <> UIButton.lens.titleColor(for: .normal) .~ LegacyColors.ksr_support_400.uiColor()
    <> UIButton.lens.titleColor(for: .highlighted) .~ LegacyColors.ksr_support_700.uiColor()
    <> UIButton.lens.title(for: .normal) %~ { _ in Strings.login_buttons_forgot_password() }

@MainActor
public let loginControllerStyle = UIViewController.lens.title %~ { _ in Strings.login_navbar_title() }

@MainActor
public let loginWithEmailButtonStyle: ButtonStyle = { button in
  button.applyStyleConfiguration(KSRButtonLegacyStyle.grey)
  button.setTitle(Strings.login_buttons_log_in(), for: .normal)
  return button
}

@MainActor
public let newsletterSwitchStyle = UISwitch.lens.onTintColor .~ LegacyColors.ksr_create_700.uiColor()

@MainActor
public let passwordFieldStyle: TextFieldStyle = { field in
  let field = formFieldStyle(field)
  field.placeholder = Strings.login_placeholder_password()
  field.isSecureTextEntry = true
  return field
}

@MainActor
public func passwordFieldAutoFillStyle(_ textField: UITextField) -> UITextField {
  return textField
    |> passwordFieldStyle
    |> \.textContentType .~ .password
}

@MainActor
public func newPasswordFieldAutoFillStyle(_ textField: UITextField) -> UITextField {
  let style = passwordFieldAutoFillStyle(textField)

  return style
    |> \.textContentType .~ .newPassword
}

@MainActor
public let resetPasswordButtonStyle: ButtonStyle = { button in
  button.applyStyleConfiguration(KSRButtonStyle.green)
  button.setTitle(Strings.forgot_password_buttons_reset_my_password(), for: .normal)
  return button
}

@MainActor
public let resetPasswordControllerStyle = UIViewController.lens.title %~ { _ in
  Strings.forgot_password_title()
}

@MainActor
public func applyLoginRootStackViewStyle(_ stackView: UIStackView, useLargerMargins: Bool) {
  stackView.isLayoutMarginsRelativeArrangement = true
  stackView.layoutMargins = useLargerMargins ?
    .init(topBottom: Styles.grid(5), leftRight: Styles.grid(20)) :
    .init(topBottom: Styles.grid(2), leftRight: Styles.grid(4))
}

@MainActor
public let signupButtonStyle: ButtonStyle = { button in
  button.applyStyleConfiguration(KSRButtonStyle.green)
  button.setTitle(Strings.login_tout_default_intent_traditional_signup_button(), for: .normal)
  return button
}

@MainActor
public let newsletterButtonStyle = UIButton.lens.titleColor(for: .normal) .~ LegacyColors.ksr_support_400
  .uiColor()
  <> UIButton.lens.titleColor(for: .highlighted) %~ { _ in
    LegacyColors.ksr_support_400.uiColor(opacity: 0.5)
  }

  <> UIButton.lens.titleLabel.font .~ .ksr_footnote()
  <> UIButton.lens.titleLabel.textAlignment .~ .left
  <> UIButton.lens.title(for: .normal) %~ { _ in
    Strings.Receive_a_weekly_mix_of_handpicked_projects_plus_occasional_Kickstarter_news()
  }

  <> UIButton.lens.accessibilityValue %~ { _ in Strings.general_navigation_buttons_help() }
  <> UIButton.lens.accessibilityLabel %~ { _ in
    Strings.Receive_a_weekly_mix_of_handpicked_projects_plus_occasional_Kickstarter_news()
  }

  <> UIButton.lens.accessibilityHint %~ { _ in Strings.Opens_help_sheet() }

@MainActor
public let signupWithEmailButtonStyle: ButtonStyle = { button in
  button.applyStyleConfiguration(KSRButtonStyle.green)
  button.setTitle(Strings.Sign_up(), for: .normal)
  return button
}

@MainActor
public let newsletterLabelStyle = UILabel.lens.font .~ .ksr_footnote()
  <> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
  <> UILabel.lens.lineBreakMode .~ .byWordWrapping
  <> UILabel.lens.numberOfLines .~ 0
  <> UILabel.lens.text %~ { _ in
    Strings.Receive_a_weekly_mix_of_handpicked_projects_plus_occasional_Kickstarter_news()
  }

@MainActor
public func disclaimerAttributedString(
  with string: String,
  useLargerText: Bool
) -> NSAttributedString? {
  guard let attributedString = try? NSMutableAttributedString(
    data: Data(string.utf8),
    options: [
      .documentType: NSAttributedString.DocumentType.html,
      .characterEncoding: String.Encoding.utf8.rawValue
    ],
    documentAttributes: nil
  ) else { return nil }

  let attributes: String.Attributes = [
    .font: useLargerText ? UIFont.ksr_footnote(size: 14.0) : .ksr_footnote(size: 11.0),
    .foregroundColor: LegacyColors.ksr_support_400.uiColor(),
    .underlineStyle: 0
  ]

  let fullRange = (attributedString.string as NSString).range(of: attributedString.string)

  attributedString.addAttributes(attributes, range: fullRange)

  return attributedString
}

@MainActor
public let tfaCodeFieldStyle: TextFieldStyle = {
  let font = UIFont.ksr_title1()
  return { field in
    let field = formFieldStyle(field)
    field.textAlignment = .center
    field.font = font
    field.keyboardType = .numberPad
    field.placeholder = Strings.two_factor_code_placeholder()
    return field
  }
}()

@MainActor
public func tfaCodeFieldAutoFillStyle(_ textField: UITextField) -> UITextField {
  let style = textField
    |> tfaCodeFieldStyle

  return style
    |> \.textContentType .~ .oneTimeCode
}

@MainActor
public let twoFactorControllerStyle = UIViewController.lens.title %~ { _ in Strings.two_factor_title() }

@MainActor
public func applyDisclaimerTextViewStyle(_ textView: UITextView, useLargerText: Bool) {
  _ = textView
    |> tappableLinksViewStyle
  textView.attributedText =
    attributedDisclaimerText(
      baseURL: AppEnvironment.current.apiService.serverConfig.webBaseUrl, useLargerText: useLargerText
    )
  textView.accessibilityTraits = [.staticText]
  textView.textAlignment = .center
}

@MainActor
public func attributedDisclaimerText(baseURL: URL, useLargerText: Bool) -> NSAttributedString? {

  guard let termsOfUseLink = HelpType.terms.url(withBaseUrl: baseURL)?.absoluteString,
        let privacyPolicyLink = HelpType.privacy.url(withBaseUrl: baseURL)?.absoluteString else { return nil }

  let string = Strings
    .By_creating_an_account_you_agree_to_Kickstarters_Terms_of_Use_and_Privacy_Policy(
      terms_of_use_link: termsOfUseLink,
      privacy_policy_link: privacyPolicyLink
    )
  return disclaimerAttributedString(with: string, useLargerText: useLargerText)
}
