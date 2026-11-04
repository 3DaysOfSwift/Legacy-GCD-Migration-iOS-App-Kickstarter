import KsApi

import Prelude
import Prelude_UIKit
import UIKit

class ImageViewElementCell: UITableViewCell, ValueCell {
  // MARK: Properties

  private lazy var imageAndCaptionStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var textView: UITextView = { UITextView(frame: .zero) }()
  private lazy var storyImageView: GIFAnimatedImageView = { GIFAnimatedImageView(frame: .zero) }()
  private var textViewHeightConstraint: NSLayoutConstraint?
  private var imageViewAspectConstraint: NSLayoutConstraint? {
    didSet {
      if let oldValue = oldValue {
        self.storyImageView.removeConstraint(oldValue)
      }

      if let newValue = imageViewAspectConstraint {
        self.storyImageView.addConstraint(newValue)
      }
    }
  }

  private let viewModel = ImageViewElementCellViewModel()
  private var pinchGesture: UIPinchGestureRecognizer!
  private var imageAspectRatio = CGFloat.zero
  weak var pinchToZoomDelegate: PinchToZoomDelegate?

  // MARK: Initializers

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)

    self.configureViews()
    self.setupConstraints()
    self.bindStyles()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func prepareForReuse() {
    super.prepareForReuse()

    self.imageViewAspectConstraint = nil
  }

  func configureWith(value imageData: (element: ImageViewElement, image: UIImage?)) {
    self.viewModel.configureWith(imageElement: imageData.element, image: imageData.image)
    self.resetTextView()
    if let caption = self.viewModel.attributedText {
      if caption.length > 0 { self.textViewHeightConstraint?.isActive = false }
      self.textView.attributedText = caption
    }
    self.resetImageView()
    if let image = self.viewModel.image {
      self.imageAspectRatio = image.size.width / image.size.height
      self.imageViewAspectConstraint = NSLayoutConstraint(
        item: self.storyImageView, attribute: .width, relatedBy: .equal,
        toItem: self.storyImageView, attribute: .height, multiplier: self.imageAspectRatio, constant: 0
      )
      self.storyImageView.image = image
    }
  }

  // MARK: View Styles

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseTableViewCellStyle()
      |> \.separatorInset .~
      .init(
        top: 0,
        left: 0,
        bottom: 0,
        right: self.bounds.size.width + ProjectHeaderCellStyles.Layout.insets
      )

    _ = self.contentView
      |> \.layoutMargins .~ .init(
        topBottom: Styles.gridHalf(3),
        leftRight: Styles.grid(3)
      )

    _ = self.imageAndCaptionStackView
      |> \.axis .~ .vertical
      |> \.spacing .~ Styles.grid(1)

    _ = self.textView
      |> textViewStyle

    _ = self.storyImageView
      |> imageViewStyle
      |> \.isUserInteractionEnabled .~ true
  }

  // MARK: Helpers

  private func resetImageView() {
    if self.storyImageView.isAnimating {
      self.storyImageView.stopAnimating()
      self.storyImageView.image = nil
    }
  }

  private func resetTextView() {
    self.textView.attributedText = nil
    self.textViewHeightConstraint?.isActive = true
  }

  private func configureViews() {
    _ = (self.imageAndCaptionStackView, self.contentView)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToMarginsInParent()

    _ = ([self.storyImageView, self.textView], self.imageAndCaptionStackView)
      |> ksr_addArrangedSubviewsToStackView()

    self.pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(self.pinch(sender:)))
    self.pinchGesture.delegate = self

    self.storyImageView.addGestureRecognizer(self.pinchGesture)
  }

  private func setupConstraints() {
    self.textViewHeightConstraint = self.textView.heightAnchor.constraint(equalToConstant: 0)
    self.textViewHeightConstraint?.isActive = true
  }

  @objc func pinch(sender: UIPinchGestureRecognizer) {
    switch sender.state {
    case .began:
      guard let image = self.storyImageView.image else { return }

      let originWithoutParentView = self.storyImageView.convert(
        self.storyImageView.frame.origin,
        to: nil
      )

      let frameWithinWindow = CGRect(
        x: originWithoutParentView.x,
        y: originWithoutParentView.y,
        width: self.storyImageView.frame.width,
        height: self.storyImageView.frame.height
      )

      self.pinchToZoomDelegate?.pinchZoomDidBegin(
        self.pinchGesture,
        frame: frameWithinWindow,
        image: image
      )
    case .changed:
      self.pinchToZoomDelegate?.pinchZoomDidChange(self.pinchGesture) {
        if !self.storyImageView.isHidden {
          self.storyImageView.isHidden.toggle()
        }
      }
    case .ended, .failed, .cancelled:
      self.pinchToZoomDelegate?.pinchZoomDidEnd(self.pinchGesture) {
        self.storyImageView.isHidden = false
      }
    default:
      return
    }
  }
}
