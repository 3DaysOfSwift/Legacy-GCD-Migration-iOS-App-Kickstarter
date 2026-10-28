import KsApi
import SwiftUI

/// Presentation of the reporting options owned by ProjectReportingFeature.
@MainActor
public final class ReportProjectInfoViewModel: ObservableObject {
  @Published public var listItems: [ReportProjectInfoListItem] = []
  @Published public var isLoading = false
  private let feature: ProjectReportingFeature
  private var loadTask: Task<Void, Never>?
  private var loadID: UUID?

  public init(feature: ProjectReportingFeature? = nil) {
    self.feature = feature ?? AppModel.shared.projectReportingFeature
  }

  deinit { self.loadTask?.cancel() }

  @discardableResult
  public func viewDidLoad() -> Task<Void, Never> {
    if let task = self.loadTask { return task }
    let feature = self.feature
    let context = feature.context
    let id = UUID()
    self.loadID = id
    self.isLoading = true
    let task = Task { [weak self] in
      defer {
        if self?.loadID == id {
          self?.loadTask = nil
          self?.isLoading = false
        }
      }
      do {
        let items = try await feature.options(context: context)
        try feature.requireCurrent(context)
        guard self?.loadID == id else { return }
        self?.listItems = items
      } catch {
        // The existing screen keeps its options empty on failure.
      }
    }
    self.loadTask = task
    return task
  }

  public func stop() {
    self.loadID = nil
    self.loadTask?.cancel()
    self.loadTask = nil
    self.isLoading = false
  }
}
