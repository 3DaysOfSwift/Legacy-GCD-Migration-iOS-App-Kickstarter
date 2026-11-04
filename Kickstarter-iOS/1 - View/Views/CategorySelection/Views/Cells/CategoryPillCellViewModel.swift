import Foundation
import KsApi

public typealias CategoryPillCellValue = (name: String, category: KsApi.Category, indexPath: IndexPath?)

@MainActor
public final class CategoryPillCellViewModel {
  var onTitle: ((String) -> Void)?
  var onSelection: ((Bool) -> Void)?
  var onTap: ((IndexPath, KsApi.Category) -> Void)?
  private var value: CategoryPillCellValue?
  private var lastSelection: Bool?

  func configure(with value: CategoryPillCellValue) {
    self.value = value
    self.onTitle?(value.name)
  }

  func pillCellTapped() {
    guard let value = self.value, let indexPath = value.indexPath else { return }
    self.onTap?(indexPath, value.category)
  }

  func setIsSelected(selected: Bool) {
    guard self.lastSelection != selected else { return }
    self.lastSelection = selected
    self.onSelection?(selected)
  }
}
