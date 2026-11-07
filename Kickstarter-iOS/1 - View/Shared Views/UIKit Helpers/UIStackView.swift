import KDS
import UIKit.UIStackView

private let stackViewBackgroundViewTag: Int = 1

@MainActor public func ksr_addArrangedSubviewsToStackView() -> (@MainActor ([UIView], UIStackView) -> UIStackView) {
  return { subviews, stackView in
    for view in subviews { stackView.addArrangedSubview(view) }

    return stackView
  }
}

@MainActor public func ksr_setCustomSpacing(_ spacing: CGFloat) -> (@MainActor (UIView, UIStackView) -> UIStackView) {
  return { view, stackView in
    stackView.setCustomSpacing(spacing, after: view)

    return stackView
  }
}

@MainActor public func ksr_setBackgroundColor(_ color: UIColor) -> (@MainActor (UIStackView) -> UIStackView) {
  return { stackView in
    if let firstSubview = stackView.subviews.first, firstSubview.tag == stackViewBackgroundViewTag {
      firstSubview.backgroundColor = color

      return stackView
    }

    let backgroundView = UIView(frame: stackView.bounds)
    backgroundView.tag = stackViewBackgroundViewTag
    backgroundView.backgroundColor = color
    backgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    stackView.insertSubview(backgroundView, at: 0)

    return stackView
  }
}
