import KDS
import Prelude
import Prelude_UIKit
import UIKit

@MainActor
public let baseBarButtonItemStyle =
  UIBarButtonItem.lens.tintColor .~ LegacyColors.ksr_support_400.uiColor()

@MainActor
public let plainBarButtonItemStyle = baseBarButtonItemStyle
  <> UIBarButtonItem.lens.style .~ .plain
  <> UIBarButtonItem.lens.titleTextAttributes(for: .normal) .~ [
    NSAttributedString.Key.font: UIFont.ksr_subhead(size: 15)
  ]

@MainActor
public let doneBarButtonItemStyle = baseBarButtonItemStyle
  <> UIBarButtonItem.lens.style .~ .done
  <> UIBarButtonItem.lens.title %~ { _ in Strings.Done() }
  <> UIBarButtonItem.lens.titleTextAttributes(for: .normal) .~ [
    NSAttributedString.Key.font: UIFont.ksr_headline(size: 15)
  ]

@MainActor
public let iconBarButtonItemStyle = baseBarButtonItemStyle
  <> UIBarButtonItem.lens.title .~ nil

@MainActor
public let closeBarButtonItemStyle = iconBarButtonItemStyle
  <> UIBarButtonItem.lens.image .~ image(named: "icon--cross")

@MainActor
public let shareBarButtonItemStyle = iconBarButtonItemStyle
  <> UIBarButtonItem.lens.image .~ image(named: "icon--share")
  <> UIBarButtonItem.lens.accessibilityLabel %~ { _ in Strings.dashboard_accessibility_label_share_project() }
