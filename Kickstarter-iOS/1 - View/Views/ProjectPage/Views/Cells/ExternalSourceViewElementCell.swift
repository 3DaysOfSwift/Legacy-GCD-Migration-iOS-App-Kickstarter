import KsApi

import Prelude
import Prelude_UIKit
import WebKit

class ExternalSourceViewElementCell: UITableViewCell, ValueCell {
  // MARK: Properties

  private lazy var webView: WKWebView = {
    let configuration = WKWebViewConfiguration()
    configuration.allowsInlineMediaPlayback = true
    configuration.suppressesIncrementalRendering = true
    configuration.applicationNameForUserAgent = "Kickstarter-iOS"

    let webView = WKWebView(frame: .zero, configuration: configuration)

    webView.customUserAgent = Service.userAgent

    return webView
  }()

  private let viewModel = ExternalSourceViewElementCellViewModel()
  private var contentHeightConstraint: NSLayoutConstraint?

  // MARK: Initializers

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)

    self.configureViews()
    self.setupDelegate()
    self.setupConstraints()
    self.bindStyles()
  }

  // MARK: Lifecycle

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: View Model

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
  }

  // MARK: Helpers

  func configureWith(value: ExternalSourceViewElement) {
    self.viewModel.configureWith(element: value)
    if let htmlText = self.viewModel.htmlText {
      if let blank = URL(string: "about:blank") { self.webView.load(URLRequest(url: blank)) }
      if let url = URL(string: htmlText + "?playsinline=1") {
        var request = URLRequest(url: url)
        request.addValue(AppEnvironment.current.apiService.serverConfig.webBaseUrl.absoluteString,
                         forHTTPHeaderField: "Referer")
        self.webView.load(request)
      }
    }
    if let height = self.viewModel.contentHeight {
      self.contentHeightConstraint?.isActive = false
      self.contentHeightConstraint = self.webView.heightAnchor.constraint(equalToConstant: CGFloat(height))
      self.contentHeightConstraint?.isActive = true
    }
  }

  private func configureViews() {
    _ = (self.webView, self.contentView)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToMarginsInParent()
  }

  private func setupDelegate() {
    self.webView.uiDelegate = self
  }

  private func setupConstraints() {
    self.contentHeightConstraint = self.webView.heightAnchor.constraint(equalToConstant: .zero)
    self.contentHeightConstraint?.priority = .defaultHigh
    self.contentHeightConstraint?.isActive = true
  }
}

extension ExternalSourceViewElementCell: WKUIDelegate {
  func webView(
    _: WKWebView,
    createWebViewWith _: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures _: WKWindowFeatures
  ) -> WKWebView? {
    let canOpenInNewWindow = navigationAction.targetFrame == nil || navigationAction.targetFrame?
      .isMainFrame == false

    if canOpenInNewWindow,
       let urlToLoad = navigationAction.request.url,
       AppEnvironment.current.application.canOpenURL(urlToLoad) {
      AppEnvironment.current.application.open(urlToLoad, options: [:], completionHandler: nil)
    }

    return nil
  }
}
