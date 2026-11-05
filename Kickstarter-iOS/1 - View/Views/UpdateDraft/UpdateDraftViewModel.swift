import KsApi
import Prelude
import UIKit

@MainActor
final class UpdateDraftViewModel {
  enum Event {
    case attachmentAdded(UpdateDraft.Attachment), attachmentRemoved(UpdateDraft.Attachment)
    case attachments([UpdateDraft.Attachment]), body(String), bodyTextViewBecomeFirstResponder
    case goToPreview(UpdateDraft), isAttachmentsSectionHidden(Bool), isLoading(Bool), isBackersOnly(Bool)
    case isBodyPlaceholderHidden(Bool), isPreviewButtonEnabled(Bool), navigationItemTitle(String)
    case notifyPresenterViewControllerWantsDismissal, resignFirstResponder, showAddAttachmentFailure
    case showAttachmentActions([AttachmentSource]), showImagePicker(AttachmentSource), showLoadFailure
    case showRemoveAttachmentConfirmation(UpdateDraft.Attachment), showRemoveAttachmentFailure
    case showSaveFailure, title(String), titleTextFieldBecomeFirstResponder
  }
  var onEvent: ((Event) -> Void)?
  private let feature: CreatorDraftsFeature
  private let route = UUID()
  private var project: Project?
  private var didLoad = false
  private var draft: UpdateDraft?
  private var currentTitle: String?
  private var currentBody: String?
  private var backersOnly: Bool?
  private var currentAttachments: [UpdateDraft.Attachment]?
  private var lastAttachmentHidden: Bool?
  private var lastPreviewEnabled: Bool?
  private var lastPlaceholderHidden: Bool?
  private var saveTask: Task<Void, Never>?
  private var saveRevision = UUID()
  private var imageTasks: [UUID: Task<Void, Never>] = [:]

  init(creatorDraftsFeature: CreatorDraftsFeature? = nil) {
    let feature = creatorDraftsFeature ?? AppModel.shared.creatorDraftsFeature
    self.feature = feature
    feature.observe(route: self.route) { [weak self] event in self?.receive(event) }
  }
  deinit {
    self.saveTask?.cancel()
    for task in self.imageTasks.values { task.cancel() }
    let feature = self.feature
    let route = self.route
    Task { @MainActor in feature.release(route: route) }
  }
  func configureWith(project: Project) {
    self.project = project
    if self.didLoad { self.feature.requestLoad(project: project, route: self.route) }
  }
  func viewDidLoad() {
    self.didLoad = true
    self.onEvent?(.isLoading(true))
    self.publishAttachmentHidden(true)
    self.publishPreviewEnabled(false)
    if let project = self.project { self.feature.requestLoad(project: project, route: self.route) }
  }
  private func receive(_ event: CreatorDraftsFeature.Event) {
    switch event {
    case let .load(.failure(_)):
      self.onEvent?(.showLoadFailure)
      self.onEvent?(.notifyPresenterViewControllerWantsDismissal)
    case let .load(.success(draft)):
      self.draft = draft
      self.currentTitle = draft.update.title
      self.currentBody = draft.update.body ?? ""
      self.backersOnly = !draft.update.isPublic
      self.onEvent?(.isLoading(false))
      self.onEvent?(.navigationItemTitle(Strings.dashboard_post_update_compose_update_number(update_number: Format.wholeNumber(draft.update.sequence))))
      self.onEvent?(.title(draft.update.title))
      self.onEvent?(.body(draft.update.body ?? ""))
      self.onEvent?(.isBackersOnly(!draft.update.isPublic))
      let attachments = draft.images.map(UpdateDraft.Attachment.image) + (draft.video.map { [.video($0)] } ?? [])
      self.onEvent?(.attachments(attachments))
      self.publishPlaceholder()
      if draft.update.title.isEmpty { self.onEvent?(.titleTextFieldBecomeFirstResponder) }
      else if (draft.update.body ?? "").isEmpty { self.onEvent?(.bodyTextViewBecomeFirstResponder) }
      self.publishValidation()
    case let .attachments(attachments):
      self.currentAttachments = attachments
      self.publishAttachmentHidden(attachments.isEmpty)
      self.publishValidation()
    }
  }
  func titleTextChanged(to title: String) { self.currentTitle = title; self.publishValidation() }
  func bodyTextChanged(to body: String) { self.currentBody = body; self.publishPlaceholder(); self.publishValidation() }
  func isBackersOnlyOn(_ value: Bool) { self.backersOnly = value; self.onEvent?(.isBackersOnly(value)) }
  private func publishValidation() {
    guard let title = self.currentTitle, let body = self.currentBody, let attachments = self.currentAttachments else { return }
    self.publishPreviewEnabled(!title.trimmed().isEmpty && (!body.trimmed().isEmpty || !attachments.isEmpty))
  }
  private func publishPreviewEnabled(_ value: Bool) {
    guard self.lastPreviewEnabled != value else { return }
    self.lastPreviewEnabled = value
    self.onEvent?(.isPreviewButtonEnabled(value))
  }
  private func publishAttachmentHidden(_ value: Bool) {
    guard self.lastAttachmentHidden != value else { return }
    self.lastAttachmentHidden = value
    self.onEvent?(.isAttachmentsSectionHidden(value))
  }
  private func publishPlaceholder() {
    guard let body = self.currentBody else { return }
    let hidden = !body.isEmpty
    guard self.lastPlaceholderHidden != hidden else { return }
    self.lastPlaceholderHidden = hidden
    self.onEvent?(.isBodyPlaceholderHidden(hidden))
  }
  func addAttachmentButtonTapped(availableSources: [AttachmentSource]) { self.onEvent?(.showAttachmentActions(availableSources)) }
  func addAttachmentSheetButtonTapped(_ action: AttachmentSource) { self.onEvent?(.showImagePicker(action)) }
  func attachmentTapped(id: Int) {
    if let attachment = self.currentAttachments?.first(where: { $0.id == id }) { self.onEvent?(.showRemoveAttachmentConfirmation(attachment)) }
  }
  func imagePicked(url: URL, fromSource _: AttachmentSource) {
    guard self.draft != nil else { return }
    let id = UUID()
    let feature = self.feature
    let route = self.route
    self.imageTasks[id] = Task { [weak self] in
      defer { self?.imageTasks[id] = nil }
      do {
        let image = try await feature.add(file: url, route: route)
        guard !Task.isCancelled else { return }
        self?.onEvent?(.attachmentAdded(.image(image)))
      } catch {
        guard !Task.isCancelled, !(error is CancellationError) else { return }
        self?.onEvent?(.showAddAttachmentFailure)
      }
    }
  }
  func remove(attachment: UpdateDraft.Attachment) {
    guard self.draft != nil else { return }
    guard case let .image(image) = attachment else { self.onEvent?(.showRemoveAttachmentFailure); return }
    let id = UUID()
    let feature = self.feature
    let route = self.route
    self.imageTasks[id] = Task { [weak self] in
      defer { self?.imageTasks[id] = nil }
      do {
        let removed = try await feature.remove(imageID: image.id, route: route)
        guard !Task.isCancelled else { return }
        self?.onEvent?(.attachmentRemoved(.image(removed)))
      } catch {
        guard !Task.isCancelled, !(error is CancellationError) else { return }
        self?.onEvent?(.showRemoveAttachmentFailure)
      }
    }
  }
  func imagePickerCanceled() {}
  func titleTextFieldDoneEditing() { self.onEvent?(.bodyTextViewBecomeFirstResponder) }
  func viewWillDisappear() { self.onEvent?(.resignFirstResponder) }
  func closeButtonTapped() { self.save(preview: false) }
  func previewButtonTapped() { self.save(preview: true) }
  private func save(preview: Bool) {
    guard let title = self.currentTitle, let body = self.currentBody, let backersOnly = self.backersOnly else { return }
    self.saveTask?.cancel()
    let revision = UUID()
    self.saveRevision = revision
    let feature = self.feature
    let route = self.route
    self.saveTask = Task { [weak self] in
      do {
        let saved = try await feature.save(route: route, title: title, body: body, isPublic: !backersOnly)
        guard !Task.isCancelled, let self, self.saveRevision == revision else { return }
        if preview { self.onEvent?(.goToPreview(saved)) }
        else { self.onEvent?(.notifyPresenterViewControllerWantsDismissal) }
      } catch {
        guard !Task.isCancelled, !(error is CancellationError), let self, self.saveRevision == revision else { return }
        self.onEvent?(.showSaveFailure)
      }
    }
  }
  func waitForPending() async {
    await self.feature.waitForOperations()
    await self.saveTask?.value
    for task in Array(self.imageTasks.values) { await task.value }
  }
}

public enum AttachmentSource: String {
  case camera
  case cameraRoll = "camera_roll"

  public init(sourceType: UIImagePickerController.SourceType) {
    switch sourceType {
    case .camera:
      self = .camera
    case .photoLibrary:
      self = .cameraRoll
    default:
      fatalError("unsupported source: \(sourceType)")
    }
  }

  public var title: String {
    switch self {
    case .camera:
      return Strings.dashboard_post_update_compose_attachment_buttons_new_photo()
    case .cameraRoll:
      return Strings.dashboard_post_update_compose_attachment_buttons_choose_from_camera_roll()
    }
  }

  public var sourceType: UIImagePickerController.SourceType {
    switch self {
    case .camera:
      return .camera
    case .cameraRoll:
      return .photoLibrary
    }
  }
}

extension AttachmentSource: Equatable {}
public func == (lhs: AttachmentSource, rhs: AttachmentSource) -> Bool {
  switch (lhs, rhs) {
  case (.camera, .camera), (.cameraRoll, .cameraRoll):
    return true
  default:
    return false
  }
}
