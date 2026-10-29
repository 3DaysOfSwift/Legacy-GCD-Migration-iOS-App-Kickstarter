import Foundation
import KsApi
import Library
import Observation

extension Project: Identifiable {}

/// Owns the pagination example's screen lifetime and presentation projection.
@MainActor @Observable
internal final class PaginationExampleViewModel {
  typealias ProjectData = DeveloperExamplesFeature.ProjectData
  private let feature: DeveloperExamplesFeature
  private let route = UUID()
  var projects: [ProjectData] { self.feature.pageSnapshot(route: self.route).projects }
  var showProgressView: Bool { self.feature.pageSnapshot(route: self.route).showProgressView }
  var statusText: String { self.feature.pageSnapshot(route: self.route).statusText }

  init(feature: DeveloperExamplesFeature? = nil) {
    self.feature = feature ?? AppModel.shared.developerExamplesFeature
  }
  deinit {
    let feature = self.feature, route = self.route
    Task { @MainActor in feature.release(route: route) }
  }
  func load() async { await self.feature.loadFirstPage(route: self.route) }
  func refresh() async { await self.feature.loadFirstPage(route: self.route, refreshing: true) }
  func loadNextPage() async { await self.feature.loadNextPage(route: self.route) }
  func suspend() { self.feature.suspend(route: self.route) }
}
