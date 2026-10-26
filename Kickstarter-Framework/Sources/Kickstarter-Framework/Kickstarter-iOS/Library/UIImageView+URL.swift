import AlamofireImage
import Kingfisher
import KingfisherWebP
import ReactiveExtensions
import ReactiveSwift
import UIKit

extension UIImageView {
  #if DEBUG
    /// Install the local demo transport in the image clients' own sessions.
    /// Global URLProtocol registration does not configure an already-created session.
    public static func ksr_configureDemoImageLoading(protocolClass: URLProtocol.Type) {
      let configuration = AlamofireImage.ImageDownloader.defaultURLSessionConfiguration()
      configuration.protocolClasses = [protocolClass] + (configuration.protocolClasses ?? [])
      UIImageView.af.sharedImageDownloader = AlamofireImage.ImageDownloader(configuration: configuration)

      let kingfisherConfiguration = URLSessionConfiguration.ephemeral
      kingfisherConfiguration.protocolClasses = [protocolClass] + (kingfisherConfiguration.protocolClasses ?? [])
      Kingfisher.ImageDownloader.default.sessionConfiguration = kingfisherConfiguration
    }
  #endif

  public func ksr_setImageWithURL(
    _ url: URL,
    placeholderImage: UIImage? = nil
  ) {
    self.af.setImage(
      withURL: url,
      placeholderImage: placeholderImage,
      filter: nil,
      progress: nil,
      progressQueue: DispatchQueue.main,
      imageTransition: .crossDissolve(0.3),
      runImageTransitionIfCached: false,
      completion: nil
    )
  }

  public func ksr_setRoundedImageWith(_ url: URL) {
    self.af.setImage(
      withURL: url,
      placeholderImage: nil,
      filter: CircleFilter(),
      progress: nil,
      progressQueue: DispatchQueue.main,
      imageTransition: .crossDissolve(0.3),
      runImageTransitionIfCached: false,
      completion: nil
    )
  }

  public static func ksr_cacheImageWith(
    _ url: URL,
    completionHandler: @escaping (UIImage?) -> Void
  ) {
    /* WebPProcessor and WebPSerializer fall back to
     DefaultImageProcessor and DefaultCacheSerializer, respectively,
     for non-webp images */

    let options: KingfisherOptionsInfo = [
      .processor(WebPProcessor.default),
      .cacheSerializer(WebPSerializer.default)
    ]

    let prefetcher = ImagePrefetcher(
      resources: [url],
      options: options
    ) { cachedImages, failedImages, downloadedImages in
      var crossPlatformImage: UIImage?

      guard failedImages.isEmpty,
            let image = (cachedImages + downloadedImages).first else {
        completionHandler(crossPlatformImage)

        return
      }

      ImageCache.default.retrieveImage(
        forKey: image.cacheKey,
        options: options
      ) { result in

        switch result {
        case let .success(imageResult):
          if let imageResultImage = imageResult.image {
            crossPlatformImage = imageResultImage
          }

          completionHandler(crossPlatformImage)
        case .failure:
          completionHandler(crossPlatformImage)
        }
      }
    }

    prefetcher.start()
  }

  public static func ksr_stopFetchingImages() {
    ImageDownloader.default.cancelAll()
  }
}

private enum Associations {
  fileprivate static var ksr_imageUrl = 0
}

extension Rac where Object: UIImageView {
  public var ksr_imageUrl: Signal<URL?, Never> {
    nonmutating set {
      let prop: MutableProperty<URL?> = lazyMutableProperty(
        object,
        key: &Associations.ksr_imageUrl,
        setter: { [weak object] url in
          object?.af.cancelImageRequest()
          object?.image = nil
          guard let url = url else { return }
          object?.ksr_setImageWithURL(url)
        },
        getter: { nil }
      )

      prop <~ newValue.observeForUI()
    }

    get {
      .empty
    }
  }
}
