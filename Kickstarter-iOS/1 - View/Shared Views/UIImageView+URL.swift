import AlamofireImage
import Kingfisher
import UIKit

// AlamofireImage owns each image-view request receipt, cancels replacement,
// weakly captures the view and checks both URL and receipt before assigning.
// Keep its cache, circle filter and cross-dissolve rather than adding a second loader.
@MainActor
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
}
