import Combine
import Foundation
import GraphAPI
import KsApi

@MainActor
public protocol ReportProjectFormViewModelInputs {
  @discardableResult func viewDidLoad() -> Task<Void, Never>
}

@MainActor
public protocol ReportProjectFormViewModelOutputs {}

@MainActor
public protocol ReportProjectFormViewModelType {
  var inputs: ReportProjectFormViewModelInputs { get }
  var outputs: ReportProjectFormViewModelOutputs { get }
}

@MainActor
public final class ReportProjectFormViewModel: ReportProjectFormViewModelType,
  ReportProjectFormViewModelInputs, ReportProjectFormViewModelOutputs, ObservableObject {
  @Published public var retrievedEmail: String?
  @Published public var saveButtonEnabled = false
  @Published public var saveButtonLoading = false
  @Published public var detailsText = "" {
    didSet { self.saveButtonEnabled = !self.detailsText.isEmpty && !self.saveButtonLoading && !self.submitSuccess }
  }
  @Published public var bannerMessage: MessageBannerViewViewModel?
  @Published public var submitSuccess = false
  public var projectID: String?
  public var projectFlaggingKind: GraphAPI.NonDeprecatedFlaggingKind?

  private let feature: ProjectReportingFeature
  private var emailTask: Task<Void, Never>?
  private var submissionTask: Task<Void, Never>?
  private var emailID: UUID?
  private var submissionID: UUID?

  public init(feature: ProjectReportingFeature? = nil) {
    self.feature = feature ?? AppModel.shared.projectReportingFeature
  }

  deinit {
    self.emailTask?.cancel()
    self.submissionTask?.cancel()
  }

  @discardableResult
  public func viewDidLoad() -> Task<Void, Never> {
    if let task = self.emailTask { return task }
    let feature = self.feature
    let context = feature.context
    let id = UUID()
    self.emailID = id
    let task = Task { [weak self] in
      defer { if self?.emailID == id { self?.emailTask = nil } }
      do {
        let email = try await feature.email(context: context)
        try feature.requireCurrent(context)
        guard self?.emailID == id else { return }
        self?.retrievedEmail = email
      } catch {
        guard !Task.isCancelled, !(error is CancellationError), feature.context == context,
              self?.emailID == id else { return }
        self?.retrievedEmail = ""
      }
    }
    self.emailTask = task
    return task
  }

  @discardableResult
  public func didTapSave() -> Task<Void, Never>? {
    if let task = self.submissionTask { return task }
    guard !self.submitSuccess else { return nil }
    guard let projectID = self.projectID, let kind = self.projectFlaggingKind else {
      self.showFailure()
      return nil
    }
    let feature = self.feature
    let context = feature.context
    let command: Task<Void, Error>
    do {
      command = try feature.submit(.init(projectID: projectID, kind: kind, details: self.detailsText), context: context)
    } catch {
      self.showFailure()
      return nil
    }
    let id = UUID()
    self.submissionID = id
    self.saveButtonEnabled = false
    self.saveButtonLoading = true
    let task = Task { [weak self] in
      defer {
        if self?.submissionID == id {
          self?.submissionTask = nil
          self?.saveButtonLoading = false
          self?.saveButtonEnabled = !(self?.detailsText.isEmpty ?? true) && !(self?.submitSuccess ?? false)
        }
      }
      do {
        try await command.value
        try feature.requireCurrent(context)
        guard self?.submissionID == id, self?.projectID == projectID,
              self?.projectFlaggingKind == kind else { return }
        self?.submitSuccess = true
        self?.bannerMessage = MessageBannerViewViewModel((
          type: .success, message: Strings.Your_message_has_been_sent()
        ))
      } catch {
        guard !Task.isCancelled, !(error is CancellationError), feature.context == context,
              self?.submissionID == id, self?.projectID == projectID,
              self?.projectFlaggingKind == kind else { return }
        self?.showFailure()
      }
    }
    self.submissionTask = task
    return task
  }

  private func showFailure() {
    self.bannerMessage = MessageBannerViewViewModel((
      type: .error, message: Strings.Something_went_wrong_please_try_again()
    ))
    self.saveButtonEnabled = !self.detailsText.isEmpty
    self.saveButtonLoading = false
  }

  public func stop() {
    self.emailID = nil
    self.submissionID = nil
    self.emailTask?.cancel()
    self.submissionTask?.cancel()
    self.emailTask = nil
    self.submissionTask = nil
    self.saveButtonLoading = false
    self.saveButtonEnabled = !self.detailsText.isEmpty && !self.submitSuccess
  }

  public var inputs: ReportProjectFormViewModelInputs { self }
  public var outputs: ReportProjectFormViewModelOutputs { self }
}
