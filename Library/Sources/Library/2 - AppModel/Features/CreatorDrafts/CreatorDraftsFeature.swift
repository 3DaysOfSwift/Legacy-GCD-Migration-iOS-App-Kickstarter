import Foundation
import KsApi
import Prelude
import ReactiveSwift

@MainActor
public protocol CreatorDraftsProvider {
  func load(project: Project) async throws -> UpdateDraft
  func save(draft: UpdateDraft, title: String, body: String, isPublic: Bool) async throws -> UpdateDraft
  func add(file: URL, draft: UpdateDraft) async throws -> UpdateDraft.Image
  func remove(image: UpdateDraft.Image, draft: UpdateDraft) async throws -> UpdateDraft.Image
}

@MainActor
public struct AsyncCreatorDraftsProvider: CreatorDraftsProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func load(project: Project) async throws -> UpdateDraft { try await self.service.creatorDraft(project: project) }
  public func save(draft: UpdateDraft, title: String, body: String, isPublic: Bool) async throws -> UpdateDraft {
    try await self.service.saveCreatorDraft(draft, title: title, body: body, isPublic: isPublic)
  }
  public func add(file: URL, draft: UpdateDraft) async throws -> UpdateDraft.Image {
    try await self.service.addCreatorDraftImage(file: file, draft: draft)
  }
  public func remove(image: UpdateDraft.Image, draft: UpdateDraft) async throws -> UpdateDraft.Image {
    try await self.service.removeCreatorDraftImage(image, draft: draft)
  }
}

/// The server remains the durable draft store. This Feature coordinates reads
/// and ordered edits; abandoning observation cannot undo an admitted edit.
@MainActor
public final class CreatorDraftsFeature {
  private struct Key: Hashable {
    let projectID: Int
    let userID: Int?
    let generation: Int
  }
  private final class Route {
    let key: Key
    var read: (id: UUID, revision: Int, task: Task<Void, Never>)?
    init(key: Key) { self.key = key }
  }
  private enum Command: Equatable {
    case save(title: String, body: String, isPublic: Bool)
    case add(URL)
    case remove(Int)
  }
  private enum Outcome {
    case saved(UpdateDraft)
    case image(UpdateDraft.Image)
  }
  private struct Pending {
    let id: UUID
    let command: Command
    let draftID: Int
    let task: Task<Outcome, Error>
  }
  public let sessionFeature: SessionFeature
  private let makeProvider: () -> any CreatorDraftsProvider
  private let sleep: (TimeInterval) async throws -> Void
  private var routes: [UUID: Route] = [:]
  private var drafts: [Key: UpdateDraft] = [:]
  private var revisions: [Key: Int] = [:]
  private var tails: [Key: Pending] = [:]
  private var writes: [UUID: Task<Outcome, Error>] = [:]
  private var reads: [UUID: Task<Void, Never>] = [:]
  private var observations: [UUID: Task<Void, Never>] = [:]
  private let loadPipe = Signal<(UUID, Result<UpdateDraft, ErrorEnvelope>), Never>.pipe()
  private let attachmentsPipe = Signal<(UUID, [UpdateDraft.Attachment]), Never>.pipe()
  public var loads: Signal<(UUID, Result<UpdateDraft, ErrorEnvelope>), Never> { self.loadPipe.output }
  public var attachments: Signal<(UUID, [UpdateDraft.Attachment]), Never> { self.attachmentsPipe.output }

  public init(
    sessionFeature: SessionFeature, makeProvider: @escaping () -> any CreatorDraftsProvider,
    sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
      if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    }
  ) {
    self.sessionFeature = sessionFeature
    self.makeProvider = makeProvider
    self.sleep = sleep
  }
  private func isCurrent(_ key: Key) -> Bool {
    self.sessionFeature.isCurrent(userID: key.userID, generation: key.generation)
  }
  private func requireCurrent(_ key: Key) throws {
    try Task.checkCancellation()
    guard self.isCurrent(key) else { throw CancellationError() }
  }
  public func release(route: UUID) { self.routes.removeValue(forKey: route)?.read?.task.cancel() }
  public func reset() {
    for route in Array(self.routes.keys) { self.release(route: route) }
    self.drafts.removeAll()
    self.revisions.removeAll()
    for task in self.observations.values { task.cancel() }
  }
  public func load(project: Project, route: UUID) async { await self.requestLoad(project: project, route: route).value }

  @discardableResult
  public func requestLoad(project: Project, route: UUID) -> Task<Void, Never> {
    let key = Key(projectID: project.id, userID: self.sessionFeature.currentUser?.id, generation: self.sessionFeature.generation)
    let revision = self.revisions[key, default: 0]
    if let state = self.routes[route], state.key == key, let read = state.read, read.revision == revision {
      return read.task
    }
    self.release(route: route)
    let state = Route(key: key)
    self.routes[route] = state
    let id = UUID()
    let provider = self.makeProvider()
    let predecessor = self.tails[key]?.task
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let task = Task { [self] in
      defer { self.reads[id] = nil; if state.read?.id == id { state.read = nil } }
      do {
        if let predecessor { _ = await predecessor.result }
        try self.requireCurrent(key)
        let draft = try await provider.load(project: project)
        try await self.sleep(delay)
        try self.requireCurrent(key)
        guard self.routes[route] === state, self.revisions[key, default: 0] == revision else { return }
        self.drafts[key] = draft
        self.loadPipe.input.send(value: (route, .success(draft)))
        self.publishAttachments(key: key)
      } catch {
        guard !Task.isCancelled, !(error is CancellationError), self.isCurrent(key),
              self.routes[route] === state, self.revisions[key, default: 0] == revision else { return }
        self.loadPipe.input.send(value: (route, .failure((error as? ErrorEnvelope) ?? .couldNotParseJSON)))
      }
    }
    state.read = (id, revision, task)
    self.reads[id] = task
    return task
  }

  public func save(route: UUID, title: String, body: String, isPublic: Bool) async throws -> UpdateDraft {
    let value = try await self.execute(.save(title: title, body: body, isPublic: isPublic), route: route)
    guard case .saved(let draft) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return draft
  }
  public func add(file: URL, route: UUID) async throws -> UpdateDraft.Image {
    let value = try await self.execute(.add(file), route: route)
    guard case .image(let image) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return image
  }
  public func remove(imageID: Int, route: UUID) async throws -> UpdateDraft.Image {
    let value = try await self.execute(.remove(imageID), route: route)
    guard case .image(let image) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return image
  }
  private func execute(_ command: Command, route: UUID) async throws -> Outcome {
    try Task.checkCancellation()
    guard let state = self.routes[route] else { throw CancellationError() }
    do {
      let value = try await self.request(command, state: state).value
      try self.requireCurrent(state.key)
      guard self.routes[route] === state else { throw CancellationError() }
      return value
    } catch {
      try self.requireCurrent(state.key)
      guard self.routes[route] === state else { throw CancellationError() }
      throw error
    }
  }

  public func saveResult(route: UUID, title: String, body: String, isPublic: Bool) -> SignalProducer<UpdateDraft, ErrorEnvelope> {
    self.result(.save(title: title, body: body, isPublic: isPublic), route: route).attemptMap {
      guard case .saved(let draft) = $0 else { return .failure(.couldNotParseJSON) }
      return .success(draft)
    }
  }
  public func addResult(file: URL, route: UUID) -> SignalProducer<UpdateDraft.Image, ErrorEnvelope> {
    self.imageResult(.add(file), route: route)
  }
  public func removeResult(attachment: UpdateDraft.Attachment, route: UUID) -> SignalProducer<UpdateDraft.Image, ErrorEnvelope> {
    guard case .image(let image) = attachment else {
      return SignalProducer(error: .couldNotParseJSON)
    }
    return self.imageResult(.remove(image.id), route: route)
  }
  private func imageResult(_ command: Command, route: UUID) -> SignalProducer<UpdateDraft.Image, ErrorEnvelope> {
    self.result(command, route: route).attemptMap {
      guard case .image(let image) = $0 else { return .failure(.couldNotParseJSON) }
      return .success(image)
    }
  }

  private func request(_ command: Command, state: Route) throws -> Task<Outcome, Error> {
    let key = state.key
    try self.requireCurrent(key)
    guard let admittedDraft = self.drafts[key] else { throw ErrorEnvelope.couldNotParseJSON }
    let previous = self.tails[key]
    if let previous, previous.command == command, previous.draftID == admittedDraft.update.id { return previous.task }
    let id = UUID()
    let provider = self.makeProvider()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.revisions[key, default: 0] += 1
    let task = Task { [self] in
      defer { self.writes[id] = nil; if self.tails[key]?.id == id { self.tails[key] = nil } }
      if let previous { _ = await previous.task.result }
      try self.requireCurrent(key)
      guard var draft = self.drafts[key], draft.update.id == admittedDraft.update.id else { throw CancellationError() }
      let outcome: Outcome
      do {
        switch command {
        case let .save(title, body, isPublic):
          if draft.update.title != title || draft.update.body != body || draft.update.isPublic != isPublic {
            draft = try await provider.save(draft: draft, title: title, body: body, isPublic: isPublic)
          }
          outcome = .saved(draft)
        case .add(let file):
          let image = try await provider.add(file: file, draft: draft)
          draft = draft |> UpdateDraft.lens.images .~ (draft.images.filter { $0.id != image.id } + [image])
          outcome = .image(image)
        case .remove(let id):
          guard let image = draft.images.first(where: { $0.id == id }) else { throw ErrorEnvelope.couldNotParseJSON }
          let removed = try await provider.remove(image: image, draft: draft)
          draft = draft |> UpdateDraft.lens.images .~ draft.images.filter { $0.id != removed.id }
          outcome = .image(removed)
        }
        try self.requireCurrent(key)
        self.drafts[key] = draft
        try await self.sleep(delay)
        try self.requireCurrent(key)
        self.publishAttachments(key: key)
        return outcome
      } catch {
        try self.requireCurrent(key)
        throw error
      }
    }
    self.tails[key] = Pending(id: id, command: command, draftID: admittedDraft.update.id, task: task)
    self.writes[id] = task
    return task
  }

  private func publishAttachments(key: Key) {
    guard let draft = self.drafts[key], self.isCurrent(key) else { return }
    let attachments = draft.images.map(UpdateDraft.Attachment.image) + (draft.video.map { [.video($0)] } ?? [])
    for (route, state) in self.routes where state.key == key {
      self.attachmentsPipe.input.send(value: (route, attachments))
    }
  }

  // Values-only adapter for the existing screens; execution belongs to the task
  // queue above. Disposing observation never cancels an admitted server write.
  private func result(_ command: Command, route: UUID) -> SignalProducer<Outcome, ErrorEnvelope> {
    let state = self.routes[route]
    return SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        guard let state, self.routes[route] === state, self.isCurrent(state.key) else { observer.sendInterrupted(); return }
        let work: Task<Outcome, Error>
        do { work = try self.request(command, state: state) }
        catch { observer.send(error: (error as? ErrorEnvelope) ?? .couldNotParseJSON); return }
        let id = UUID()
        let task = Task { [self] in
          defer { self.observations[id] = nil }
          do {
            let outcome = try await work.value
            try self.requireCurrent(state.key)
            guard self.routes[route] === state else { observer.sendInterrupted(); return }
            observer.send(value: outcome)
            observer.sendCompleted()
          } catch {
            guard !Task.isCancelled, !(error is CancellationError), self.isCurrent(state.key), self.routes[route] === state else {
              observer.sendInterrupted(); return
            }
            observer.send(error: (error as? ErrorEnvelope) ?? .couldNotParseJSON)
          }
        }
        self.observations[id] = task
        lifetime.observeEnded { task.cancel() }
      }
    }
  }

  public func waitForOperations() async {
    while !self.reads.isEmpty || !self.writes.isEmpty || !self.observations.isEmpty {
      for task in Array(self.reads.values) { await task.value }
      for task in Array(self.writes.values) { _ = await task.result }
      for task in Array(self.observations.values) { await task.value }
    }
  }
}
