import AVFoundation
import Foundation
import Kingfisher
import KingfisherWebP
import UIKit

/// UI handles stay on MainActor. A thumbnail is optional and never delays playback.
@MainActor
public struct PreparedProjectMedia {
  public let player: AVPlayer
  public let thumbnail: UIImage?
  public init(player: AVPlayer, thumbnail: UIImage? = nil) {
    self.player = player
    self.thumbnail = thumbnail
  }
}

/// One preparation owns its optional image read and AVFoundation readiness observation.
@MainActor
final class ProjectMediaPreparation {
  private var thumbnail: UIImage?
  private var thumbnailTask: Task<Void, Never>?

  static func loadImage(url: URL) async throws -> UIImage {
    let result = try await KingfisherManager.shared.retrieveImage(
      with: url, options: [.processor(WebPProcessor.default), .cacheSerializer(WebPSerializer.default)]
    )
    try Task.checkCancellation()
    return result.image
  }

  static func load(url: URL, thumbnailURL: URL?) async throws -> PreparedProjectMedia {
    try await ProjectMediaPreparation().load(url: url, thumbnailURL: thumbnailURL)
  }

  private func load(url: URL, thumbnailURL: URL?) async throws -> PreparedProjectMedia {
    if let thumbnailURL {
      self.thumbnailTask = Task { [weak self] in
        // Same cache, WebP processor and serializer as the existing image helper.
        let image = try? await Self.loadImage(url: thumbnailURL)
        guard !Task.isCancelled else { return }
        self?.thumbnail = image
      }
    }
    defer { self.thumbnailTask?.cancel() }
    let asset = AVURLAsset(url: url)
    return try await withTaskCancellationHandler {
      _ = try await asset.load(.duration, .tracks)
      try Task.checkCancellation()
      let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["duration", "tracks"])
      let player = AVPlayer(playerItem: item)
      try await Self.waitUntilReady(item)
      try Task.checkCancellation()
      return PreparedProjectMedia(player: player, thumbnail: self.thumbnail)
    } onCancel: {
      asset.cancelLoading()
    }
  }

  /// AVPlayerItem readiness has no native async API. The stream owns exactly one
  /// KVO observation; failure, success and cancellation all invalidate it.
  static func waitUntilReady(_ item: AVPlayerItem) async throws {
    let (statuses, continuation) = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
      // AVFoundation can notify with a nil typed change payload. Read the
      // current status at the notification boundary and transfer only its value.
      continuation.yield(item.status.rawValue)
    }
    defer { observation.invalidate(); continuation.finish() }
    for await value in statuses {
      try Task.checkCancellation()
      switch AVPlayerItem.Status(rawValue: value) {
      case .readyToPlay: return
      case .failed: throw item.error ?? URLError(.cannotDecodeContentData)
      default: continue
      }
    }
    throw CancellationError()
  }
}
