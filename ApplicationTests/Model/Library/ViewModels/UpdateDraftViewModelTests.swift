@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import UIKit
import XCTest

@MainActor
final class UpdateDraftViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  let feature = CreatorDraftsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncCreatorDraftsProvider(service: AppEnvironment.current.apiService) }
  )
  lazy var vm: UpdateDraftViewModel = UpdateDraftViewModel(creatorDraftsFeature: self.feature)
  let attachmentAdded = DraftRecorder<UpdateDraft.Attachment>()
  let attachmentRemoved = DraftRecorder<UpdateDraft.Attachment>()
  let attachments = DraftRecorder<[UpdateDraft.Attachment]>()
  let body = DraftRecorder<String>()
  let bodyTextViewBecomeFirstResponder = DraftRecorder<()>()
  let goToPreview = DraftRecorder<UpdateDraft>()
  let isAttachmentsSectionHidden = DraftRecorder<Bool>()
  let isBackersOnly = DraftRecorder<Bool>()
  let isBodyPlaceholderHidden = DraftRecorder<Bool>()
  let isLoading = DraftRecorder<Bool>()
  let isPreviewButtonEnabled = DraftRecorder<Bool>()
  let navigationItemTitle = DraftRecorder<String>()
  let notifyPresenterViewControllerWantsDismissal = DraftRecorder<()>()
  let resignFirstResponder = DraftRecorder<()>()
  let showAddAttachmentFailure = DraftRecorder<()>()
  let showAttachmentActions = DraftRecorder<[AttachmentSource]>()
  let showImagePicker = DraftRecorder<AttachmentSource>()
  let showLoadFailure = DraftRecorder<()>()
  let showRemoveAttachmentConfirmation = DraftRecorder<UpdateDraft.Attachment>()
  let showRemoveAttachmentFailure = DraftRecorder<()>()
  let showSaveFailure = DraftRecorder<()>()
  let title = DraftRecorder<String>()
  let titleTextFieldBecomeFirstResponder = DraftRecorder<()>()

  override func setUp() async throws {
    try await super.setUp()

    MainActor.assumeIsolated { self.bindOutputs() }
  }

  private func bindOutputs() {
    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .attachmentAdded(value): self.attachmentAdded.record(value)
      case let .attachmentRemoved(value): self.attachmentRemoved.record(value)
      case let .attachments(value): self.attachments.record(value)
      case let .body(value): self.body.record(value)
      case .bodyTextViewBecomeFirstResponder: self.bodyTextViewBecomeFirstResponder.record(())
      case let .goToPreview(value): self.goToPreview.record(value)
      case let .isAttachmentsSectionHidden(value): self.isAttachmentsSectionHidden.record(value)
      case let .isBackersOnly(value): self.isBackersOnly.record(value)
      case let .isBodyPlaceholderHidden(value): self.isBodyPlaceholderHidden.record(value)
      case let .isLoading(value): self.isLoading.record(value)
      case let .isPreviewButtonEnabled(value): self.isPreviewButtonEnabled.record(value)
      case let .navigationItemTitle(value): self.navigationItemTitle.record(value)
      case .notifyPresenterViewControllerWantsDismissal: self.notifyPresenterViewControllerWantsDismissal.record(())
      case .resignFirstResponder: self.resignFirstResponder.record(())
      case .showAddAttachmentFailure: self.showAddAttachmentFailure.record(())
      case let .showAttachmentActions(value): self.showAttachmentActions.record(value)
      case let .showImagePicker(value): self.showImagePicker.record(value)
      case .showLoadFailure: self.showLoadFailure.record(())
      case let .showRemoveAttachmentConfirmation(value): self.showRemoveAttachmentConfirmation.record(value)
      case .showRemoveAttachmentFailure: self.showRemoveAttachmentFailure.record(())
      case .showSaveFailure: self.showSaveFailure.record(())
      case let .title(value): self.title.record(value)
      case .titleTextFieldBecomeFirstResponder: self.titleTextFieldBecomeFirstResponder.record(())
      }
    }
  }

  func testConfiguredBlank() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.title.assertValues([""])
      self.body.assertValues([""])
      self.isBackersOnly.assertValues([false])
      self.attachments.assertValues([[]])
    }
  }

  func testConfiguredWithNavigationItemTitle() async {
    let draft = .template |> UpdateDraft.lens.update.sequence .~ 7
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.navigationItemTitle.assertValues([
        Strings.dashboard_post_update_compose_update_number(
          update_number: Format.wholeNumber(7)
        )
      ])
    }
  }

  func testConfiguredWithTitle() async {
    let draft = .template |> UpdateDraft.lens.update.title .~ "Hello, world!"
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.title.assertValues(["Hello, world!"])
    }
  }

  func testConfiguredWithBody() async {
    let draft = .template |> UpdateDraft.lens.update.body .~ "Thanks for your support!"
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.body.assertValues(["Thanks for your support!"])
    }
  }

  func testConfiguredWithPublic() async {
    let draft = .template |> UpdateDraft.lens.update.isPublic .~ true
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.isBackersOnly.assertValues([false])
    }
  }

  func testConfiguredWithPrivate() async {
    let draft = .template |> UpdateDraft.lens.update.isPublic .~ false
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.isBackersOnly.assertValues([true])
    }
  }

  func testConfiguredWithVideo() async {
    let video = UpdateDraft.Video.template
    let draft = .template |> UpdateDraft.lens.video .~ video
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.attachments.assertValues([[.video(video)]])
    }
  }

  func testConfiguredWithImages() async {
    let images = [.template, .template |> UpdateDraft.Image.lens.id %~ { $0 + 1 }]
    let draft = .template |> UpdateDraft.lens.images .~ images
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.attachments.assertValues([images.map(UpdateDraft.Attachment.image)])
    }
  }

  func testConfiguredWithVideoAndImages() async {
    let video = UpdateDraft.Video.template
    let images = [.template, .template |> UpdateDraft.Image.lens.id %~ { $0 + 1 }]
    let draft = .template
      |> UpdateDraft.lens.video .~ video
      |> UpdateDraft.lens.images .~ images
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.attachments.assertValues([images.map(UpdateDraft.Attachment.image) + [.video(video)]])
    }
  }

  func testIsLoading() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()

      self.isLoading.assertValues([true], "is loading")

      await self.vm.waitForPending()

      self.isLoading.assertValues([true, false], "is loaded")
    }
  }

  func testPreviewButtonEnabled() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.isPreviewButtonEnabled.assertValues([false], "emits on view did load")
      self.isBodyPlaceholderHidden.assertValues([false], "emits on view did load")

      await self.vm.waitForPending()

      self.vm.bodyTextChanged(to: "Thanks for believing in me.")
      self.isPreviewButtonEnabled.assertValues([false])
      self.isBodyPlaceholderHidden.assertValues([false, true])

      self.vm.titleTextChanged(to: "Hello")
      self.isPreviewButtonEnabled.assertValues([false, true])
      self.isBodyPlaceholderHidden.assertValues([false, true])

      self.vm.titleTextChanged(to: "Hello, world!")
      self.isPreviewButtonEnabled.assertValues([false, true])
      self.isBodyPlaceholderHidden.assertValues([false, true])

      self.vm.bodyTextChanged(to: "")
      self.isPreviewButtonEnabled.assertValues([false, true, false])
      self.isBodyPlaceholderHidden.assertValues([false, true, false])

      self.vm.bodyTextChanged(to: " ")
      self.isPreviewButtonEnabled.assertValues([false, true, false])
      self.isBodyPlaceholderHidden.assertValues([false, true, false, true])

      self.vm.bodyTextChanged(to: " \n\n\n")
      self.isPreviewButtonEnabled.assertValues([false, true, false])
      self.isBodyPlaceholderHidden.assertValues([false, true, false, true])

      self.vm.bodyTextChanged(to: "Thanks for believing in my project!")
      self.isPreviewButtonEnabled.assertValues([false, true, false, true])
      self.isBodyPlaceholderHidden.assertValues([false, true, false, true])
    }
  }

  func testBlankTitleBecomesFirstReponder() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.titleTextFieldBecomeFirstResponder.assertValueCount(1)
      self.bodyTextViewBecomeFirstResponder.assertValueCount(0)
    }
  }

  func testBlankBodyBecomesFirstReponderWithTitlePresent() async {
    let titled = .blank |> UpdateDraft.lens.update.title .~ "Hello, world!"
    await withEnvironment(apiService: MockService(fetchDraftResponse: titled)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.titleTextFieldBecomeFirstResponder.assertValueCount(0)
      self.bodyTextViewBecomeFirstResponder.assertValueCount(1)
    }
  }

  func testIsBackersOnlyOnTappedFlipsVisibility() async {
    let draft = .template |> UpdateDraft.lens.update.isPublic .~ false
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.isBackersOnly.assertValues([true])

      self.vm.isBackersOnlyOn(false)
      self.isBackersOnly.assertValues([true, false])

      self.vm.isBackersOnlyOn(true)
      self.isBackersOnly.assertValues([true, false, true])
    }
  }

  func testAddAttachments() async {
    let image: UpdateDraft.Image = .template
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank, addAttachmentResponse: image)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.vm.addAttachmentButtonTapped(availableSources: [.cameraRoll])
      self.showAttachmentActions.assertValues([[.cameraRoll]])

      self.vm.addAttachmentSheetButtonTapped(.cameraRoll)
      self.showImagePicker.assertValues([.cameraRoll])

      self.vm.imagePickerCanceled()

      self.vm.addAttachmentButtonTapped(availableSources: [.camera, .cameraRoll])
      self.showAttachmentActions.assertValues([[.cameraRoll], [.camera, .cameraRoll]])

      self.vm.addAttachmentSheetButtonTapped(.camera)
      self.showImagePicker.assertValues([.cameraRoll, .camera])

      self.vm.imagePicked(url: URL(string: "/tmp/photo.jpg")!, fromSource: .camera)

      self.attachmentAdded.assertValues([])
      await self.vm.waitForPending()
      self.attachmentAdded.assertValues([.image(image)])
    }
  }

  func testAddAttachmentFailure() async {
    await withEnvironment(apiService: MockService(
      fetchDraftResponse: .blank,
      addAttachmentError: .couldNotParseJSON
    )) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.vm.addAttachmentButtonTapped(availableSources: [.cameraRoll])
      self.showAttachmentActions.assertValues([[.cameraRoll]])

      self.vm.addAttachmentSheetButtonTapped(.cameraRoll)
      self.showImagePicker.assertValues([.cameraRoll])

      self.vm.imagePicked(url: URL(string: "/tmp/photo.jpg")!, fromSource: .cameraRoll)

      self.showAddAttachmentFailure.assertValueCount(0)
      await self.vm.waitForPending()
      self.attachmentAdded.assertValues([])
      self.showAddAttachmentFailure.assertValueCount(1)
    }
  }

  func testRemoveAttachment() async {
    let id = 1
    let image = .template |> UpdateDraft.Image.lens.id .~ id
    let draft = .template
      |> UpdateDraft.lens.images .~ [image]
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft, removeAttachmentResponse: image)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.vm.attachmentTapped(id: id)
      self.showRemoveAttachmentConfirmation.assertValues([.image(image)])

      self.vm.attachmentTapped(id: id)
      self.showRemoveAttachmentConfirmation.assertValues([.image(image), .image(image)])

      self.vm.remove(attachment: .image(image))

      self.attachmentRemoved.assertValues([])
      await self.vm.waitForPending()
      self.attachmentRemoved.assertValues([.image(image)])
    }
  }

  func testRemoveAttachmentFailure() async {
    let id = 1
    let image = .template |> UpdateDraft.Image.lens.id .~ id
    let draft = .template |> UpdateDraft.lens.images .~ [image]
    await withEnvironment(apiService: MockService(
      fetchDraftResponse: draft,
      removeAttachmentError: .couldNotParseJSON
    )) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.vm.attachmentTapped(id: id)
      self.showRemoveAttachmentConfirmation.assertValues([.image(image)])

      self.vm.remove(attachment: .image(image))

      self.showRemoveAttachmentFailure.assertValueCount(0)
      await self.vm.waitForPending()
      self.attachmentRemoved.assertValues([])
      self.showRemoveAttachmentFailure.assertValueCount(1)
    }
  }

  func testBlankAttachmentVisibility() async {
    let id = 1
    let image = .template |> UpdateDraft.Image.lens.id .~ id
    await withEnvironment(
      apiService: MockService(
        fetchDraftResponse: .blank, addAttachmentResponse: image, removeAttachmentResponse: image
      )
    ) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()

      self.isAttachmentsSectionHidden.assertValues([true])

      await self.vm.waitForPending()

      self.isAttachmentsSectionHidden.assertValues([true])

      self.vm.addAttachmentButtonTapped(availableSources: [.camera, .cameraRoll])
      self.vm.addAttachmentSheetButtonTapped(.camera)
      self.vm.imagePicked(url: URL(string: "/tmp/photo.jpg")!, fromSource: .camera)

      await self.vm.waitForPending()

      self.isAttachmentsSectionHidden.assertValues([true, false])

      self.vm.attachmentTapped(id: id)
      self.vm.remove(attachment: .image(image))

      await self.vm.waitForPending()

      self.isAttachmentsSectionHidden.assertValues([true, false, true])
    }
  }

  func testExistingAttachmentVisibility() async {
    let existingId = 1
    let existingImage = .template |> UpdateDraft.Image.lens.id .~ existingId
    let newImage = .template |> UpdateDraft.Image.lens.id .~ 2
    let draft = .template |> UpdateDraft.lens.images .~ [existingImage]
    await withEnvironment(
      apiService: MockService(
        fetchDraftResponse: draft, addAttachmentResponse: newImage, removeAttachmentResponse: existingImage
      )
    ) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()

      self.isAttachmentsSectionHidden.assertValues([true])

      await self.vm.waitForPending()

      self.isAttachmentsSectionHidden.assertValues([true, false])

      self.vm.addAttachmentButtonTapped(availableSources: [.camera, .cameraRoll])
      self.vm.addAttachmentSheetButtonTapped(.camera)
      self.vm.imagePicked(url: URL(string: "/tmp/photo.jpg")!, fromSource: .camera)

      await self.vm.waitForPending()

      self.isAttachmentsSectionHidden.assertValues([true, false])

      self.vm.attachmentTapped(id: existingId)
      self.vm.remove(attachment: .image(existingImage))

      await self.vm.waitForPending()

      self.isAttachmentsSectionHidden.assertValues([true, false])
    }
  }

  func testTitleTextFieldDoneEditing() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.bodyTextViewBecomeFirstResponder.assertValueCount(0)

      self.vm.titleTextFieldDoneEditing()
      self.bodyTextViewBecomeFirstResponder.assertValueCount(1)
    }
  }

  func testDismissalWithoutEdits() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(0)
      self.resignFirstResponder.assertValueCount(0)

      self.vm.closeButtonTapped()
      self.vm.viewWillDisappear()
      await self.vm.waitForPending()

      self.resignFirstResponder.assertValueCount(1)
      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(1)
    }
  }

  func testDismissalWithEdits() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.vm.titleTextChanged(to: "Hello, world!")

      self.vm.closeButtonTapped()
      await self.vm.waitForPending()

      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(1)
    }
  }

  func testPreviewTapped() async {
    let draft = UpdateDraft.template
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.goToPreview.assertValues([])
      self.vm.previewButtonTapped()
      await self.vm.waitForPending()

      self.goToPreview.assertValues([draft])
    }
  }

  func testPreviewTappedWithEdits() async {
    let draft = UpdateDraft.template
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.vm.titleTextChanged(to: "Hello, world!")

      self.goToPreview.assertValues([])
      self.vm.previewButtonTapped()
      await self.vm.waitForPending()

      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(0)

      self.goToPreview.assertValues([draft])
    }
  }

  func testTrackEditBody() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.vm.bodyTextChanged(to: "Hello, world!")

      self.vm.closeButtonTapped()
      await self.vm.waitForPending()

      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(1)
    }
  }

  func testTrackEditIsBackersOnly() async {
    let draft = .blank |> UpdateDraft.lens.update.isPublic .~ true
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.vm.isBackersOnlyOn(true)

      self.vm.closeButtonTapped()
      await self.vm.waitForPending()

      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(1)
    }
  }

  func testErrorLoadingDraft() async {
    await withEnvironment(apiService: MockService(fetchDraftError: .couldNotParseJSON)) {
      self.showLoadFailure.assertValueCount(0)
      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(0)

      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.showLoadFailure.assertValueCount(1)
      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(1)
    }
  }

  func testErrorSavingDraft() async {
    let apiService = MockService(fetchDraftResponse: .blank, updateDraftError: .couldNotParseJSON)
    await withEnvironment(apiService: apiService) {
      self.vm.configureWith(project: .template)
      self.vm.viewDidLoad()
      await self.vm.waitForPending()

      self.vm.bodyTextChanged(to: "Hello, world!")

      self.vm.closeButtonTapped()
      await self.vm.waitForPending()

      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(0)
      self.showSaveFailure.assertValueCount(1)
    }
  }
}

final class DraftRecorder<Value> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
}
private extension DraftRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
