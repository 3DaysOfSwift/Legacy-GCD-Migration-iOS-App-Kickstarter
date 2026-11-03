import WebKit

public struct WKNavigationActionData {
  public let navigationAction: WKNavigationAction?
  public let navigationType: WKNavigationType
  public let request: URLRequest
  public let targetFrame: WKFrameInfoData?

  public init(navigationAction: WKNavigationAction) {
    self.navigationAction = navigationAction
    self.navigationType = navigationAction.navigationType
    self.request = navigationAction.request
    self.targetFrame = navigationAction.targetFrame.map(WKFrameInfoData.init(frameInfo:))
  }

  internal init(
    navigationType: WKNavigationType,
    request: URLRequest,
    sourceFrame _: WKFrameInfoData,
    targetFrame: WKFrameInfoData?
  ) {
    // Synthetic navigation data has no WebKit-owned action. Constructing an
    // empty WKNavigationAction is not a valid substitute for a real event.
    self.navigationAction = nil
    self.navigationType = navigationType
    self.request = request
    self.targetFrame = targetFrame
  }
}

public struct WKFrameInfoData {
  public let frameInfo: WKFrameInfo?
  public let mainFrame: Bool

  public init(frameInfo: WKFrameInfo) {
    self.frameInfo = frameInfo
    self.mainFrame = frameInfo.isMainFrame
  }

  public init(mainFrame: Bool, request _: URLRequest) {
    self.frameInfo = nil
    self.mainFrame = mainFrame
  }
}
