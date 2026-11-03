@testable import Kickstarter_iOS

import Kingfisher


import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

final class VideoFeedShareSheetViewTests: TestCase {
  private let previewImageURL = URL(string: "https://test.com/preview.jpg")!

  override func setUp() async throws {
    try await super.setUp()

    UIView.setAnimationsEnabled(false)

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 225))
    let testImage = renderer.image { ctx in
      UIColor.systemBlue.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 225))
    }

    try await KingfisherManager.shared.cache.store(testImage, forKey: self.previewImageURL.absoluteString)
  }

  override func tearDown() async throws {
    try await KingfisherManager.shared.cache.removeImage(forKey: self.previewImageURL.absoluteString)

    UIView.setAnimationsEnabled(true)

    try await super.tearDown()
  }

  @MainActor
  func testVideoFeedShareSheetView() {
    orthogonalCombos(
      Language.allLanguages,
      Device.allCases
    ).forEach { language, device in
      let appBundle = Bundle(identifier: KickstarterBundleIdentifier.debug.rawValue) ?? Bundle.main

      withEnvironment(
        language: language,
        mainBundle: MockBundle(bundleIdentifier: appBundle.bundleIdentifier)
      ) {
        let view = VideoFeedShareSheetView(item: self.mockFeedItem)
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(
          origin: .zero,
          size: device.deviceSize
        )

        assertSnapshot(
          of: controller,
          as: .image(perceptualPrecision: 0.99),
          named: "\(language.rawValue)_\(device)"
        )
      }
    }
  }

  @MainActor
  func testRenderedPreviewCard() {
    let view = VideoFeedShareSheetView(item: self.mockFeedItem)
    let image = view.renderedPreviewCard()

    XCTAssertNotNil(image, "renderedPreviewCard() returned nil")

    guard let image else { return }

    assertSnapshot(
      of: image,
      as: .image(perceptualPrecision: 0.99)
    )
  }

  // MARK: - Helpers

  @MainActor
  private var mockFeedItem: VideoFeedItem {
    VideoFeedItem(
      id: "0",
      pid: 3,
      slug: "video_feed",
      projectURL: "https://test.com",
      title: "Ringo Move - The Ultimate Workout Bottle",
      creator: "Creator Name",
      creatorImageURL: nil,
      statsText: VideoFeedItem.statsTextInUserPreferredCurrency(
        pledgedAmount: 50_134,
        currencyCode: "USD",
        backersCount: 431
      ),
      badges: [
        .init(type: .projectWeLove, text: "Project We Love", icon: nil),
        .init(type: .daysLeft, text: "3 days left", icon: nil)
      ],
      videoURL: nil,
      videoPreviewImageURL: self.previewImageURL,
      projectId: "1",
      isSaved: false,
      sharesCount: 1,
      watchesCount: 50,
      percentFunded: 100
    )
  }
}
