import Foundation
import GraphAPI
import KsApi
import Observation

@MainActor
public protocol DeveloperExamplesProvider {
  func page(parameters: DiscoveryParams, cursor: String?) async throws -> DiscoveryEnvelope
  func projects() async throws -> [DeveloperExamplesFeature.ProjectItem]
  func project(slug: String) async throws -> DeveloperExamplesFeature.ProjectItem?
}

@MainActor
public struct AsyncDeveloperExamplesProvider: DeveloperExamplesProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func page(parameters: DiscoveryParams, cursor: String?) async throws -> DiscoveryEnvelope {
    if let cursor { return try await self.service.discoveryPage(paginationURL: cursor) }
    return try await self.service.discoveryPage(params: parameters)
  }
  public func projects() async throws -> [DeveloperExamplesFeature.ProjectItem] {
    let data = try await self.service.richTextExampleProjects()
    return (data.projects?.nodes ?? []).compactMap { $0 }.map {
      .init(
        id: $0.id, name: $0.name, richText: $0.storyRichText.fragments.richTextComponentFragment)
    }
  }
  public func project(slug: String) async throws -> DeveloperExamplesFeature.ProjectItem? {
    guard let project = try await self.service.richTextExampleProject(slug: slug).project else {
      return nil
    }
    return .init(
      id: project.id, name: project.name,
      richText: project.storyRichText.fragments.richTextComponentFragment)
  }
}

/// Owns the beta examples' pagination, cached rich-text list and replaceable
/// direct-link reads. Each screen gets a route so independent examples cannot
/// cancel each other. UI adapters only render snapshots and report user intent.
@MainActor @Observable
public final class DeveloperExamplesFeature {
  public struct ProjectData: Identifiable, Hashable {
    public let id: Int
    public let title: String
    public init(id: Int, title: String) {
      self.id = id
      self.title = title
    }
  }
  public struct ProjectItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let richText: RichTextComponentFragment
    public init(id: String, name: String, richText: RichTextComponentFragment) {
      self.id = id
      self.name = name
      self.richText = richText
    }
  }
  public struct PageSnapshot {
    public var projects: [ProjectData] = []
    public var isLoading = false
    public var cursor: String?
    public var statusText = "Waiting to load"
    public var showProgressView: Bool { self.isLoading || self.cursor != nil }
  }
  public struct RichTextSnapshot {
    public var projects: [ProjectItem] = []
    public var isLoading = true
    public var errorMessage: String?
  }
  private struct Session: Equatable {
    let userID: Int?
    let generation: Int
  }
  private enum PageRequest: Equatable {
    case first(DiscoveryParams)
    case next(String)
  }
  private struct PageWork {
    let id: UUID
    let session: Session
    let request: PageRequest
    let previous: PageSnapshot
    let task: Task<Void, Never>
  }
  private struct ListWork {
    let id: UUID
    let session: Session
    let task: Task<Void, Never>
  }
  private struct LookupWork {
    let id: UUID
    let session: Session
    let slug: String
    let task: Task<ProjectItem?, Error>
  }
  public let sessionFeature: SessionFeature
  @ObservationIgnored private let makeProvider: () -> any DeveloperExamplesProvider
  private var pages: [UUID: PageSnapshot] = [:]
  private var lists: [UUID: RichTextSnapshot] = [:]
  @ObservationIgnored private var pageWork: [UUID: PageWork] = [:]
  @ObservationIgnored private var listWork: [UUID: ListWork] = [:]
  @ObservationIgnored private var lookupWork: [UUID: LookupWork] = [:]
  @ObservationIgnored private var lookupVersions: [UUID: UUID] = [:]
  @ObservationIgnored private var listSessions: [UUID: Session] = [:]

  public init(
    sessionFeature: SessionFeature, makeProvider: @escaping () -> any DeveloperExamplesProvider
  ) {
    self.sessionFeature = sessionFeature
    self.makeProvider = makeProvider
  }
  private var session: Session {
    .init(userID: self.sessionFeature.currentUser?.id, generation: self.sessionFeature.generation)
  }
  public func pageSnapshot(route: UUID) -> PageSnapshot { self.pages[route] ?? PageSnapshot() }
  public func richTextSnapshot(route: UUID) -> RichTextSnapshot {
    self.lists[route] ?? RichTextSnapshot()
  }

  public func loadFirstPage(route: UUID, refreshing: Bool = false) async {
    var parameters = DiscoveryParams.defaults
    if refreshing {
      parameters.staffPicks = true
      parameters.sort = .magic
    }
    await self.requestPage(.first(parameters), route: route).value
  }
  public func loadNextPage(route: UUID) async {
    // A repeated gesture joins the existing load; a terminal page returns now.
    // Neither case waits for a publisher event that may never arrive.
    if let work = self.pageWork[route], work.session == self.session {
      await work.task.value
    } else if let cursor = self.pages[route]?.cursor {
      await self.requestPage(.next(cursor), route: route).value
    }
  }
  private func requestPage(_ request: PageRequest, route: UUID) -> Task<Void, Never> {
    let session = self.session
    if let work = self.pageWork[route], work.request == request, work.session == session {
      return work.task
    }
    self.cancelPage(route: route)
    let previous = self.pageSnapshot(route: route)
    var loading = previous
    loading.isLoading = true
    loading.statusText = "Loading"
    self.pages[route] = loading
    let id = UUID()
    let provider = self.makeProvider()
    let task = Task { [self] in
      defer { if self.pageWork[route]?.id == id { self.pageWork[route] = nil } }
      do {
        try Task.checkCancellation()
        guard self.session == session else { throw CancellationError() }
        let envelope: DiscoveryEnvelope
        var values: [ProjectData]
        switch request {
        case .first(let parameters):
          envelope = try await provider.page(parameters: parameters, cursor: nil)
          values = []
        case .next(let cursor):
          envelope = try await provider.page(parameters: .defaults, cursor: cursor)
          values = previous.projects
        }
        try Task.checkCancellation()
        guard self.session == session, self.pageWork[route]?.id == id else { return }
        // Preserve the example's append behavior, including duplicate IDs.
        values += envelope.projects.map { .init(id: $0.id, title: $0.name) }
        let cursor = envelope.projects.isEmpty ? nil : envelope.urls.api.moreProjects
        self.pages[route] = PageSnapshot(
          projects: values, cursor: values.isEmpty ? nil : cursor,
          statusText: values.isEmpty
            ? "No results"
            : cursor == nil
              ? "Loaded all results" : "Got \(values.count) results; more are available")
      } catch {
        guard self.pageWork[route]?.id == id else { return }
        if Task.isCancelled || error is CancellationError || self.session != session {
          self.pages[route] = previous
        } else {
          // Original paginator clears displayed values and cursor on failure.
          let message = (error as? ErrorEnvelope)?.errorMessages.first ?? "Unknown error"
          self.pages[route] = PageSnapshot(statusText: "Error: \(message)")
        }
      }
    }
    self.pageWork[route] = PageWork(
      id: id, session: session, request: request, previous: previous, task: task)
    return task
  }

  public func loadRichTextProjects(route: UUID) async {
    let session = self.session
    if let work = self.listWork[route], work.session == session {
      await work.task.value
      return
    }
    if self.listSessions[route] == session, let state = self.lists[route], !state.projects.isEmpty {
      return
    }
    self.listWork.removeValue(forKey: route)?.task.cancel()
    self.lists[route] = RichTextSnapshot()
    self.listSessions[route] = session
    let id = UUID()
    let provider = self.makeProvider()
    let task = Task { [self] in
      defer { if self.listWork[route]?.id == id { self.listWork[route] = nil } }
      do {
        try Task.checkCancellation()
        guard self.session == session else { throw CancellationError() }
        let projects = try await provider.projects()
        try Task.checkCancellation()
        guard self.session == session, self.listWork[route]?.id == id else { return }
        self.lists[route] = RichTextSnapshot(projects: projects, isLoading: false)
      } catch {
        guard self.listWork[route]?.id == id else { return }
        let cancelled = Task.isCancelled || error is CancellationError || self.session != session
        self.lists[route] = RichTextSnapshot(
          isLoading: false,
          errorMessage: cancelled ? nil : error.localizedDescription)
      }
    }
    self.listWork[route] = ListWork(id: id, session: session, task: task)
    await task.value
  }

  public func loadProject(input: String, route: UUID) async throws -> ProjectItem? {
    guard let slug = Self.extractSlug(from: input) else {
      self.cancelLookup(route: route)
      return nil
    }
    let session = self.session
    let work: LookupWork
    if let pending = self.lookupWork[route], pending.slug == slug, pending.session == session {
      work = pending
    } else {
      self.cancelLookup(route: route)
      let id = UUID()
      let provider = self.makeProvider()
      let task = Task { [self] in
        try Task.checkCancellation()
        guard self.session == session else { throw CancellationError() }
        let project = try await provider.project(slug: slug)
        try Task.checkCancellation()
        guard self.session == session, self.lookupVersions[route] == id else {
          throw CancellationError()
        }
        return project
      }
      work = LookupWork(id: id, session: session, slug: slug, task: task)
      self.lookupWork[route] = work
      self.lookupVersions[route] = id
    }
    defer { if self.lookupWork[route]?.id == work.id { self.lookupWork[route] = nil } }
    let result = await work.task.result
    try Task.checkCancellation()
    guard self.session == session, self.lookupVersions[route] == work.id else {
      throw CancellationError()
    }
    return try result.get()
  }
  public func cancelLookup(route: UUID) {
    self.lookupWork.removeValue(forKey: route)?.task.cancel()
    self.lookupVersions[route] = nil
  }
  private func cancelPage(route: UUID) {
    guard let work = self.pageWork.removeValue(forKey: route) else { return }
    work.task.cancel()
    self.pages[route] = work.previous
  }
  public func suspend(route: UUID) {
    self.cancelPage(route: route)
    if let work = self.listWork.removeValue(forKey: route) {
      work.task.cancel()
      self.lists[route] = RichTextSnapshot(isLoading: false)
    }
    self.cancelLookup(route: route)
  }
  public func release(route: UUID) {
    self.suspend(route: route)
    self.pages[route] = nil
    self.lists[route] = nil
    self.listSessions[route] = nil
  }
  public func reset() {
    let routes = Set(self.pages.keys).union(self.lists.keys).union(self.lookupVersions.keys)
    for route in routes { self.release(route: route) }
  }
  private static func extractSlug(from input: String) -> String? {
    if input.contains("/"), !input.hasPrefix("http"), !input.hasPrefix("https") {
      let parts = input.split(separator: "/").map(String.init)
      if parts.count == 2 { return parts.joined(separator: "/") }
    }
    if let url = URL(string: input),
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    {
      let parts = components.path.split(separator: "/").map(String.init)
      if parts.count >= 3, parts[0].lowercased() == "projects" { return "\(parts[1])/\(parts[2])" }
    }
    return nil
  }
}
