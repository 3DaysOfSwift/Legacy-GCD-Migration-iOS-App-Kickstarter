import Foundation
import KsApi
import ReactiveSwift

@MainActor
public protocol ProjectMediaProvider {
  func report(project: any HasProjectWebURL, completed: Bool) async throws -> VoidEnvelope
}

@MainActor
public struct AsyncProjectMediaProvider: ProjectMediaProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func report(project: any HasProjectWebURL, completed: Bool) async throws -> VoidEnvelope {
    try await self.service.reportVideoEvent(project: project, completed: completed)
  }
}

/// Playback counter requests are independent events, not replaceable searches.
/// Start and completion may both be in flight; neither cancels the other.
@MainActor
public final class ProjectMediaFeature {
  private struct Event: Hashable {
    let route: UUID
    let url: String
    let completed: Bool
    let userID: Int?
  }

  private var requests: [Event: (id: UUID, task: Task<Void, Never>)] = [:]
  private let makeProvider: () -> any ProjectMediaProvider
  private let completionPipe = Signal<(UUID, Bool, VoidEnvelope), Never>.pipe()
  public var completions: Signal<(UUID, Bool, VoidEnvelope), Never> { self.completionPipe.output }

  public init(makeProvider: @escaping () -> any ProjectMediaProvider) {
    self.makeProvider = makeProvider
  }

  public func report(route: UUID, project: any HasProjectWebURL, completed: Bool) async {
    guard !Task.isCancelled else { return }
    await self.requestReport(route: route, project: project, completed: completed).value
  }

  @discardableResult
  public func requestReport(
    route: UUID, project: any HasProjectWebURL, completed: Bool
  ) -> Task<Void, Never> {
    let event = Event(
      route: route,
      url: project.projectWebURL,
      completed: completed,
      userID: AppEnvironment.current.currentUser?.id
    )
    if let request = self.requests[event] { return request.task }
    let token = UUID()
    let provider = self.makeProvider()
    let task = Task { [weak self] in
      defer { if self?.requests[event]?.id == token { self?.requests[event] = nil } }
      do {
        try Task.checkCancellation()
        guard event.userID == AppEnvironment.current.currentUser?.id else { return }
        let value = try await provider.report(project: project, completed: completed)
        try Task.checkCancellation()
        guard let self, self.requests[event]?.id == token,
              event.userID == AppEnvironment.current.currentUser?.id else { return }
        self.completionPipe.input.send(value: (route, completed, value))
      } catch {
        // Counter errors have always been non-user-facing; do not retry a write
        // whose server-side outcome may be unknown.
      }
    }
    self.requests[event] = (token, task)
    return task
  }

  public func release(route: UUID) {
    for event in self.requests.keys.filter({ $0.route == route }) {
      self.requests.removeValue(forKey: event)?.task.cancel()
    }
  }
}
