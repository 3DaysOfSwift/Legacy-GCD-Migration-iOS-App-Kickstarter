
import Prelude
import UIKit

@MainActor
public protocol MessageBannerViewControllerPresenting {
  var messageBannerViewController: MessageBannerViewController? { get set }

  func configureMessageBannerViewController(on parentViewController: UIViewController)
    -> MessageBannerViewController?
}

@MainActor
public protocol MessageBannerViewControllerDelegate: AnyObject {
  // Called when banner view hides if dismissType is `.bannerOnly`.
  func messageBannerViewDidHide(type: MessageBannerType)
}

public final class MessageBannerViewController: UIViewController, NibLoading {
  @IBOutlet fileprivate var backgroundView: UIView!
  @IBOutlet fileprivate var iconImageView: UIImageView!
  @IBOutlet fileprivate var messageLabel: UILabel!

  private var bannerType: MessageBannerType?

  public enum DismissType {
    // Banner cannot be dismissed and will not be dismissed automatically.
    case persist
    // Banner can be dismissed by the user and will be dismissed automatically.
    // Once the banner is dismissed, the delegate method `messageBannerViewDidHide` is called.
    case bannerOnly
    // Banner can be dismissed by the user and will be dismissed automatically.
    // Once the banner is dismissed, the presenting view controller is popped.
    case bannerAndViewController
  }

  private var dismissType: DismissType = .bannerOnly

  internal var bottomConstraint: NSLayoutConstraint?
  private let viewModel = MessageBannerViewModel()

  weak var delegate: MessageBannerViewControllerDelegate?

  struct AnimationConstants {
    static let hideDuration: TimeInterval = 0.25
    static let showDuration: TimeInterval = 0.3
  }

  public override func viewDidLoad() {
    super.viewDidLoad()

    self.view.isHidden = true

    _ = self.backgroundView
      |> \.isAccessibilityElement .~ true

    _ = self.messageLabel
      |> \.isAccessibilityElement .~ false
  }

  public override func bindStyles() {
    super.bindStyles()

    _ = self.view
      |> \.backgroundColor .~ .clear

    _ = self.backgroundView
      |> roundedStyle(cornerRadius: 4)

    _ = self.messageLabel
      |> UILabel.lens.font .~ .ksr_subhead()
  }

  public override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onConfiguration = { [weak self] configuration in
      guard let self else { return }
      let type = configuration.type
      self.iconImageView.isHidden = !type.shouldShowIconImage
      self.backgroundView.backgroundColor = type.backgroundColor
      self.backgroundView.accessibilityLabel = "\(configuration.message) \(Strings.Message_banner_accessibility_Double_tap_to_dismiss())"
      self.messageLabel.text = configuration.message
      self.messageLabel.textColor = type.textColor
      self.messageLabel.textAlignment = type.textAlignment
      if let color = type.iconImageTintColor { self.iconImageView.tintColor = color }
      if let name = type.iconImageName { self.iconImageView.image = image(named: name, inBundle: Bundle.main) }
    }
    self.viewModel.onHidden = { [weak self] isHidden in
      guard let self, !(isHidden && self.dismissType == .persist) else { return }
      self.showViewAndAnimate(isHidden)
    }
  }

  public func showBanner(
    with type: MessageBannerType,
    message: String,
    dismissType: DismissType = .bannerOnly
  ) {
    self.bannerType = type
    self.dismissType = dismissType
    self.viewModel.update(with: (type, message))
    self.viewModel.bannerViewWillShow(true)
  }

  private func showViewAndAnimate(_ isHidden: Bool) {
    if !isHidden, !self.view.isHidden, self.dismissType == .persist { return }

    let duration = isHidden ? AnimationConstants.hideDuration : AnimationConstants.showDuration

    let hiddenConstant = self.view.frame.height + (self.view.superview?.safeAreaInsets.bottom ?? 0)

    if !isHidden {
      self.view.superview?.bringSubviewToFront(self.view)

      if self.dismissType != .persist {
        self.view.superview?.isUserInteractionEnabled = false
      }

      self.view.isHidden = isHidden

      self.bottomConstraint?.constant = hiddenConstant

      // Force an early render to set the height
      self.view.superview?.layoutIfNeeded()
    }

    UIView.animate(
      withDuration: duration,
      delay: 0.0,
      options: .curveEaseInOut,
      animations: { [weak self] in
        guard let self = self else { return }

        if isHidden {
          // Tells VoiceOver to resign focus of the message banner.
          // This causes the reader to focus on the previously selected element.
          if AppEnvironment.current.isVoiceOverRunning() {
            UIAccessibility.post(notification: UIAccessibility.Notification.layoutChanged, argument: nil)
          }
        }

        self.bottomConstraint?.constant = isHidden ? hiddenConstant : 0
        self.view.superview?.layoutIfNeeded()
      },
      completion: { [weak self] _ in
        self?.view.isHidden = isHidden

        self?.viewModel.bannerViewAnimationFinished(isHidden: isHidden)

        if !isHidden {
          // Tells VoiceOver to focus on the message banner.
          // This causes the reader to read the message and allows the user to dismiss the banner.
          if AppEnvironment.current.isVoiceOverRunning() {
            UIAccessibility.post(
              notification: UIAccessibility.Notification.layoutChanged,
              argument: self?.backgroundView
            )
          }
        } else {
          if self?.dismissType == .bannerAndViewController {
            self?.navigationController?.popViewController(animated: true)
            return
          }

          self?.view.superview?.isUserInteractionEnabled = true

          if let type = self?.bannerType {
            self?.delegate?.messageBannerViewDidHide(type: type)
          }
        }
      }
    )
  }

  @IBAction private func bannerViewPanned(_ sender: UIPanGestureRecognizer) {
    guard self.dismissType != .persist, let view = sender.view else {
      return
    }

    let currentTouchPoint = sender.translation(in: self.view.superview)

    if sender.state == .cancelled || sender.state == .ended {
      self.viewModel.bannerViewWillShow(false)

      return
    }

    let yPos = currentTouchPoint.y
    let heightLimit = view.frame.height / 8

    if yPos == 0 {
      return
    } else if yPos < -heightLimit {
      // "rubber band" effect
      let absYPos = abs(yPos)
      let adjustedYPos = heightLimit * (1 + log10(absYPos / heightLimit))

      self.bottomConstraint?.constant = -adjustedYPos
    } else {
      self.bottomConstraint?.constant = yPos
    }
  }

  @IBAction private func bannerViewTapped(_: Any) {
    guard self.dismissType != .persist else { return }

    self.viewModel.bannerViewWillShow(false)
  }
}

extension MessageBannerViewControllerPresenting where Self: UIViewController {
  public func configureMessageBannerViewController(on parentViewController: UIViewController)
    -> MessageBannerViewController? {
    let nibName = Nib.MessageBannerViewController.rawValue
    let messageBannerViewController = MessageBannerViewController(
      nibName: nibName,
      bundle: .main
    )

    guard let messageBannerView = messageBannerViewController.view else {
      return nil
    }

    parentViewController.addChild(messageBannerViewController)
    parentViewController.view.addSubview(messageBannerView)

    messageBannerViewController.didMove(toParent: parentViewController)

    messageBannerView.translatesAutoresizingMaskIntoConstraints = false

    let bottomViewBannerConstraint = messageBannerView.bottomAnchor
      .constraint(equalTo: parentViewController.view.layoutMarginsGuide.bottomAnchor)

    messageBannerViewController.bottomConstraint = bottomViewBannerConstraint

    parentViewController.view.addConstraints([
      bottomViewBannerConstraint,
      messageBannerView.widthAnchor.constraint(equalTo: parentViewController.view.widthAnchor)
    ])

    return messageBannerViewController
  }
}
