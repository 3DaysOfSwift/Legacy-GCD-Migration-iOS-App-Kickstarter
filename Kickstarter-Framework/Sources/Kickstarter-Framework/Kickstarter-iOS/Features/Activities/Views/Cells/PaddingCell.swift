import Library
import UIKit

internal final class PaddingCell: StaticTableViewCell {
  override func awakeFromNib() {
    super.awakeFromNib()
    // UIKit loads this view on the main thread; NSObject declares this hook nonisolated.
    MainActor.assumeIsolated {
      self.accessibilityElementsHidden = true
    }
  }
}
