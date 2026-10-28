import Foundation
import GraphAPI
import KsApi

@MainActor
public protocol ProjectReportingProvider {
  func options() async throws -> [ReportProjectInfoListItem]
  func email() async throws -> String?
  func submit(_ draft: ProjectReportingFeature.Draft) async throws
}

@MainActor
public struct AsyncProjectReportingProvider: ProjectReportingProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func options() async throws -> [ReportProjectInfoListItem] {
    try await self.service.fetchProjectFlaggingOptions()
  }
  public func email() async throws -> String? { try await self.service.reportingEmail() }
  public func submit(_ draft: ProjectReportingFeature.Draft) async throws {
    try await self.service.submitProjectReport(input: CreateFlaggingInput(
      contentId: draft.projectID, kind: draft.kind, details: draft.details, clientMutationId: nil
    ))
  }
}

/// Reporting reads follow the screen task's lifetime. Admitted submissions belong
/// to this Feature: dismissing a form cannot undo a report accepted by the server.
@MainActor
public final class ProjectReportingFeature {
  public struct Context: Hashable {
    fileprivate let userID: Int?
    fileprivate let generation: Int
  }
  public struct Draft: Equatable {
    public let projectID: String
    public let kind: GraphAPI.NonDeprecatedFlaggingKind
    public let details: String
    public init(projectID: String, kind: GraphAPI.NonDeprecatedFlaggingKind, details: String) {
      self.projectID = projectID
      self.kind = kind
      self.details = details
    }
  }
  private struct Pending {
    let id: UUID
    let draft: Draft
    let task: Task<Void, Error>
  }
  public let sessionFeature: SessionFeature
  private let makeProvider: () -> any ProjectReportingProvider
  private var tails: [Context: Pending] = [:]
  private var commands: [UUID: Task<Void, Error>] = [:]

  public init(sessionFeature: SessionFeature, makeProvider: @escaping () -> any ProjectReportingProvider) {
    self.sessionFeature = sessionFeature
    self.makeProvider = makeProvider
  }

  public var context: Context {
    Context(userID: self.sessionFeature.currentUser?.id, generation: self.sessionFeature.generation)
  }
  public func requireCurrent(_ context: Context) throws {
    try Task.checkCancellation()
    guard self.context == context else { throw CancellationError() }
  }
  public func options(context: Context) async throws -> [ReportProjectInfoListItem] {
    try self.requireCurrent(context)
    do {
      let result = try await self.makeProvider().options()
      try self.requireCurrent(context)
      return result
    } catch {
      try self.requireCurrent(context)
      throw error
    }
  }
  public func email(context: Context) async throws -> String? {
    try self.requireCurrent(context)
    do {
      let result = try await self.makeProvider().email()
      try self.requireCurrent(context)
      return result
    } catch {
      try self.requireCurrent(context)
      throw error
    }
  }

  /// Equivalent pending submissions share; changed reports execute in account
  /// order. Failures are surfaced for an explicit retry, never retried silently.
  public func submit(_ draft: Draft, context: Context) throws -> Task<Void, Error> {
    try self.requireCurrent(context)
    guard !draft.projectID.isEmpty, !draft.details.isEmpty else { throw ErrorEnvelope.couldNotParseJSON }
    let previous = self.tails[context]
    if let previous, previous.draft == draft { return previous.task }
    let id = UUID()
    let provider = self.makeProvider()
    let task = Task { [self] in
      defer {
        self.commands[id] = nil
        if self.tails[context]?.id == id { self.tails[context] = nil }
      }
      if let previous { _ = await previous.task.result }
      try self.requireCurrent(context)
      do {
        try await provider.submit(draft)
        try self.requireCurrent(context)
      } catch {
        try self.requireCurrent(context)
        throw error
      }
    }
    self.tails[context] = Pending(id: id, draft: draft, task: task)
    self.commands[id] = task
    return task
  }

  public func waitForOperations() async {
    while !self.commands.isEmpty {
      for task in Array(self.commands.values) { _ = await task.result }
    }
  }
}
