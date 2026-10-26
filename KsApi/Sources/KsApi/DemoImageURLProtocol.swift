#if DEBUG
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Owns local illustration responses for the demo's reserved image host.
/// Image consumers keep their existing loading/caching behaviour without network access.
internal final class DemoImageURLProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.scheme == "https" && request.url?.host == "images.demo.invalid"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url,
          let index = Int(url.deletingPathExtension().lastPathComponent),
          (0..<8).contains(index),
          ["/project/\(index).png", "/avatar/\(index).png"].contains(url.path) else {
      client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
      return
    }

    guard let data = Self.illustration(index: index, avatar: url.path.hasPrefix("/avatar/")) else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotDecodeContentData))
      return
    }
    // Existing image clients validate HTTP status as well as decoding the image bytes.
    guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "image/png", "Content-Length": String(data.count)]) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  // Rendering completes synchronously on the URL-loading thread. No child work survives cancellation.
  override func stopLoading() {}

  private static func illustration(index: Int, avatar: Bool) -> Data? {
    let width = avatar ? 128 : 640
    let height = avatar ? 128 : 360
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    let colors: [(CGFloat, CGFloat, CGFloat)] = [
      (0.09, 0.19, 0.32), (0.12, 0.34, 0.25), (0.46, 0.22, 0.32), (0.55, 0.32, 0.10),
      (0.05, 0.32, 0.46), (0.25, 0.40, 0.19), (0.27, 0.22, 0.44), (0.40, 0.24, 0.17)
    ]
    let color = colors[index]
    context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(gray: 1, alpha: 0.16))
    context.fillEllipse(in: CGRect(x: CGFloat(width) * 0.45, y: CGFloat(height) * 0.1,
      width: CGFloat(height), height: CGFloat(height)))
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.55))
    context.setLineWidth(avatar ? 3 : 5)
    for ring in 0..<3 {
      let inset = CGFloat(ring * (avatar ? 10 : 24))
      context.strokeEllipse(in: CGRect(x: 20 + inset, y: 20 + inset,
        width: CGFloat(height) - 40 - inset * 2, height: CGFloat(height) - 40 - inset * 2))
    }
    let names = ["NIGHT SKY", "FOREST TRAILS", "PAPER CITIES", "SOLAR JOURNAL",
      "OCEAN STORIES", "TINY GARDEN", "MOONLIGHT", "LOCAL SOUNDS"]
    let label = avatar ? "\(index + 1)" : "DEMO / \(names[index])"
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, avatar ? 44 : 25, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: attributes))
    context.textPosition = CGPoint(x: avatar ? 50 : 28, y: avatar ? 48 : 30)
    CTLineDraw(line, context)

    guard let image = context.makeImage() else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }
}
#endif
