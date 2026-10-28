@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import UIKit
import XCTest

@MainActor
final class UpdateDraftViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  let feature = CreatorDraftsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncCreatorDraftsProvider(service: AppEnvironment.current.apiService) }
  )
  lazy var vm: UpdateDraftViewModelType = UpdateDraftViewModel(creatorDraftsFeature: self.feature)
  let attachmentAdded = TestObserver<UpdateDraft.Attachment, Never>()
  let attachmentRemoved = TestObserver<UpdateDraft.Attachment, Never>()
  let attachments = TestObserver<[UpdateDraft.Attachment], Never>()
  let body = TestObserver<String, Never>()
  let bodyTextViewBecomeFirstResponder = TestObserver<(), Never>()
  let goToPreview = TestObserver<UpdateDraft, Never>()
  let isAttachmentsSectionHidden = TestObserver<Bool, Never>()
  let isBackersOnly = TestObserver<Bool, Never>()
  let isBodyPlaceholderHidden = TestObserver<Bool, Never>()
  let isLoading = TestObserver<Bool, Never>()
  let isPreviewButtonEnabled = TestObserver<Bool, Never>()
  let navigationItemTitle = TestObserver<String, Never>()
  let notifyPresenterViewControllerWantsDismissal = TestObserver<(), Never>()
  let resignFirstResponder = TestObserver<(), Never>()
  let showAddAttachmentFailure = TestObserver<(), Never>()
  let showAttachmentActions = TestObserver<[AttachmentSource], Never>()
  let showImagePicker = TestObserver<AttachmentSource, Never>()
  let showLoadFailure = TestObserver<(), Never>()
  let showRemoveAttachmentConfirmation = TestObserver<UpdateDraft.Attachment, Never>()
  let showRemoveAttachmentFailure = TestObserver<(), Never>()
  let showSaveFailure = TestObserver<(), Never>()
  let title = TestObserver<String, Never>()
  let titleTextFieldBecomeFirstResponder = TestObserver<(), Never>()

  override func setUp() {
    super.setUp()

    MainActor.assumeIsolated { self.bindOutputs() }
  }

  private func bindOutputs() {
    self.vm.outputs.attachmentAdded.observe(self.attachmentAdded.observer)
    self.vm.outputs.attachmentRemoved.observe(self.attachmentRemoved.observer)
    self.vm.outputs.attachments.observe(self.attachments.observer)
    self.vm.outputs.body.observe(self.body.observer)
    self.vm.outputs.bodyTextViewBecomeFirstResponder.observe(self.bodyTextViewBecomeFirstResponder.observer)
    self.vm.outputs.goToPreview.observe(self.goToPreview.observer)
    self.vm.outputs.isAttachmentsSectionHidden.observe(self.isAttachmentsSectionHidden.observer)
    self.vm.outputs.isBackersOnly.observe(self.isBackersOnly.observer)
    self.vm.outputs.isBodyPlaceholderHidden.observe(self.isBodyPlaceholderHidden.observer)
    self.vm.outputs.isLoading.observe(self.isLoading.observer)
    self.vm.outputs.isPreviewButtonEnabled.observe(self.isPreviewButtonEnabled.observer)
    self.vm.outputs.navigationItemTitle.observe(self.navigationItemTitle.observer)
    self.vm.outputs.notifyPresenterViewControllerWantsDismissal
      .observe(self.notifyPresenterViewControllerWantsDismissal.observer)
    self.vm.outputs.resignFirstResponder.observe(self.resignFirstResponder.observer)
    self.vm.outputs.showAddAttachmentFailure.observe(self.showAddAttachmentFailure.observer)
    self.vm.outputs.showAttachmentActions.observe(self.showAttachmentActions.observer)
    self.vm.outputs.showImagePicker.observe(self.showImagePicker.observer)
    self.vm.outputs.showLoadFailure.observe(self.showLoadFailure.observer)
    self.vm.outputs.showRemoveAttachmentConfirmation.observe(self.showRemoveAttachmentConfirmation.observer)
    self.vm.outputs.showRemoveAttachmentFailure.observe(self.showRemoveAttachmentFailure.observer)
    self.vm.outputs.showSaveFailure.observe(self.showSaveFailure.observer)
    self.vm.outputs.title.observe(self.title.observer)
    self.vm.outputs.titleTextFieldBecomeFirstResponder
      .observe(self.titleTextFieldBecomeFirstResponder.observer)
  }

  func testConfiguredBlank() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.title.assertValues([""])
      self.body.assertValues([""])
      self.isBackersOnly.assertValues([false])
      self.attachments.assertValues([[]])
    }
  }

  func testConfiguredWithNavigationItemTitle() async {
    let draft = .template |> UpdateDraft.lens.update.sequence .~ 7
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

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
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.title.assertValues(["Hello, world!"])
    }
  }

  func testConfiguredWithBody() async {
    let draft = .template |> UpdateDraft.lens.update.body .~ "Thanks for your support!"
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.body.assertValues(["Thanks for your support!"])
    }
  }

  func testConfiguredWithPublic() async {
    let draft = .template |> UpdateDraft.lens.update.isPublic .~ true
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.isBackersOnly.assertValues([false])
    }
  }

  func testConfiguredWithPrivate() async {
    let draft = .template |> UpdateDraft.lens.update.isPublic .~ false
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.isBackersOnly.assertValues([true])
    }
  }

  func testConfiguredWithVideo() async {
    let video = UpdateDraft.Video.template
    let draft = .template |> UpdateDraft.lens.video .~ video
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.attachments.assertValues([[.video(video)]])
    }
  }

  func testConfiguredWithImages() async {
    let images = [.template, .template |> UpdateDraft.Image.lens.id %~ { $0 + 1 }]
    let draft = .template |> UpdateDraft.lens.images .~ images
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

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
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.attachments.assertValues([images.map(UpdateDraft.Attachment.image) + [.video(video)]])
    }
  }

  func testIsLoading() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()

      self.isLoading.assertValues([true], "is loading")

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.isLoading.assertValues([true, false], "is loaded")
    }
  }

  func testPreviewButtonEnabled() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.isPreviewButtonEnabled.assertValues([false], "emits on view did load")
      self.isBodyPlaceholderHidden.assertValues([false], "emits on view did load")

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.vm.inputs.bodyTextChanged(to: "Thanks for believing in me.")
      self.isPreviewButtonEnabled.assertValues([false])
      self.isBodyPlaceholderHidden.assertValues([false, true])

      self.vm.inputs.titleTextChanged(to: "Hello")
      self.isPreviewButtonEnabled.assertValues([false, true])
      self.isBodyPlaceholderHidden.assertValues([false, true])

      self.vm.inputs.titleTextChanged(to: "Hello, world!")
      self.isPreviewButtonEnabled.assertValues([false, true])
      self.isBodyPlaceholderHidden.assertValues([false, true])

      self.vm.inputs.bodyTextChanged(to: "")
      self.isPreviewButtonEnabled.assertValues([false, true, false])
      self.isBodyPlaceholderHidden.assertValues([false, true, false])

      self.vm.inputs.bodyTextChanged(to: " ")
      self.isPreviewButtonEnabled.assertValues([false, true, false])
      self.isBodyPlaceholderHidden.assertValues([false, true, false, true])

      self.vm.inputs.bodyTextChanged(to: " \n\n\n")
      self.isPreviewButtonEnabled.assertValues([false, true, false])
      self.isBodyPlaceholderHidden.assertValues([false, true, false, true])

      self.vm.inputs.bodyTextChanged(to: "Thanks for believing in my project!")
      self.isPreviewButtonEnabled.assertValues([false, true, false, true])
      self.isBodyPlaceholderHidden.assertValues([false, true, false, true])
    }
  }

  func testBlankTitleBecomesFirstReponder() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.titleTextFieldBecomeFirstResponder.assertValueCount(1)
      self.bodyTextViewBecomeFirstResponder.assertValueCount(0)
    }
  }

  func testBlankBodyBecomesFirstReponderWithTitlePresent() async {
    let titled = .blank |> UpdateDraft.lens.update.title .~ "Hello, world!"
    await withEnvironment(apiService: MockService(fetchDraftResponse: titled)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.titleTextFieldBecomeFirstResponder.assertValueCount(0)
      self.bodyTextViewBecomeFirstResponder.assertValueCount(1)
    }
  }

  func testIsBackersOnlyOnTappedFlipsVisibility() async {
    let draft = .template |> UpdateDraft.lens.update.isPublic .~ false
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.isBackersOnly.assertValues([true])

      self.vm.inputs.isBackersOnlyOn(false)
      self.isBackersOnly.assertValues([true, false])

      self.vm.inputs.isBackersOnlyOn(true)
      self.isBackersOnly.assertValues([true, false, true])
    }
  }

  func testAddAttachments() async {
    let image: UpdateDraft.Image = .template
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank, addAttachmentResponse: image)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.vm.inputs.addAttachmentButtonTapped(availableSources: [.cameraRoll])
      self.showAttachmentActions.assertValues([[.cameraRoll]])

      self.vm.inputs.addAttachmentSheetButtonTapped(.cameraRoll)
      self.showImagePicker.assertValues([.cameraRoll])

      self.vm.inputs.imagePickerCanceled()

      self.vm.inputs.addAttachmentButtonTapped(availableSources: [.camera, .cameraRoll])
      self.showAttachmentActions.assertValues([[.cameraRoll], [.camera, .cameraRoll]])

      self.vm.inputs.addAttachmentSheetButtonTapped(.camera)
      self.showImagePicker.assertValues([.cameraRoll, .camera])

      self.vm.inputs.imagePicked(url: URL(string: "/tmp/photo.jpg")!, fromSource: .camera)

      self.attachmentAdded.assertValues([])
      await self.feature.waitForOperations()
      await self.scheduler.advance()
      self.attachmentAdded.assertValues([.image(image)])
    }
  }

  func testAddAttachmentFailure() async {
    await withEnvironment(apiService: MockService(
      fetchDraftResponse: .blank,
      addAttachmentError: .couldNotParseJSON
    )) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.vm.inputs.addAttachmentButtonTapped(availableSources: [.cameraRoll])
      self.showAttachmentActions.assertValues([[.cameraRoll]])

      self.vm.inputs.addAttachmentSheetButtonTapped(.cameraRoll)
      self.showImagePicker.assertValues([.cameraRoll])

      self.vm.inputs.imagePicked(url: URL(string: "/tmp/photo.jpg")!, fromSource: .cameraRoll)

      self.showAddAttachmentFailure.assertValueCount(0)
      await self.feature.waitForOperations()
      await self.scheduler.advance()
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
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.vm.inputs.attachmentTapped(id: id)
      self.showRemoveAttachmentConfirmation.assertValues([.image(image)])

      self.vm.inputs.attachmentTapped(id: id)
      self.showRemoveAttachmentConfirmation.assertValues([.image(image), .image(image)])

      self.vm.inputs.remove(attachment: .image(image))

      self.attachmentRemoved.assertValues([])
      await self.feature.waitForOperations()
      await self.scheduler.advance()
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
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.vm.inputs.attachmentTapped(id: id)
      self.showRemoveAttachmentConfirmation.assertValues([.image(image)])

      self.vm.inputs.remove(attachment: .image(image))

      self.showRemoveAttachmentFailure.assertValueCount(0)
      await self.feature.waitForOperations()
      await self.scheduler.advance()
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
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()

      self.isAttachmentsSectionHidden.assertValues([true])

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.isAttachmentsSectionHidden.assertValues([true])

      self.vm.inputs.addAttachmentButtonTapped(availableSources: [.camera, .cameraRoll])
      self.vm.inputs.addAttachmentSheetButtonTapped(.camera)
      self.vm.inputs.imagePicked(url: URL(string: "/tmp/photo.jpg")!, fromSource: .camera)

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.isAttachmentsSectionHidden.assertValues([true, false])

      self.vm.inputs.attachmentTapped(id: id)
      self.vm.inputs.remove(attachment: .image(image))

      await self.feature.waitForOperations()
      await self.scheduler.advance()

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
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()

      self.isAttachmentsSectionHidden.assertValues([true])

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.isAttachmentsSectionHidden.assertValues([true, false])

      self.vm.inputs.addAttachmentButtonTapped(availableSources: [.camera, .cameraRoll])
      self.vm.inputs.addAttachmentSheetButtonTapped(.camera)
      self.vm.inputs.imagePicked(url: URL(string: "/tmp/photo.jpg")!, fromSource: .camera)

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.isAttachmentsSectionHidden.assertValues([true, false])

      self.vm.inputs.attachmentTapped(id: existingId)
      self.vm.inputs.remove(attachment: .image(existingImage))

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.isAttachmentsSectionHidden.assertValues([true, false])
    }
  }

  func testTitleTextFieldDoneEditing() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.bodyTextViewBecomeFirstResponder.assertValueCount(0)

      self.vm.inputs.titleTextFieldDoneEditing()
      self.bodyTextViewBecomeFirstResponder.assertValueCount(1)
    }
  }

  func testDismissalWithoutEdits() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(0)
      self.resignFirstResponder.assertValueCount(0)

      self.vm.inputs.closeButtonTapped()
      self.vm.inputs.viewWillDisappear()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.resignFirstResponder.assertValueCount(1)
      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(1)
    }
  }

  func testDismissalWithEdits() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.vm.inputs.titleTextChanged(to: "Hello, world!")

      self.vm.inputs.closeButtonTapped()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(1)
    }
  }

  func testPreviewTapped() async {
    let draft = UpdateDraft.template
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.goToPreview.assertValues([])
      self.vm.inputs.previewButtonTapped()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.goToPreview.assertValues([draft])
    }
  }

  func testPreviewTappedWithEdits() async {
    let draft = UpdateDraft.template
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.vm.inputs.titleTextChanged(to: "Hello, world!")

      self.goToPreview.assertValues([])
      self.vm.inputs.previewButtonTapped()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(0)

      self.goToPreview.assertValues([draft])
    }
  }

  func testTrackEditBody() async {
    await withEnvironment(apiService: MockService(fetchDraftResponse: .blank)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.vm.inputs.bodyTextChanged(to: "Hello, world!")

      self.vm.inputs.closeButtonTapped()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(1)
    }
  }

  func testTrackEditIsBackersOnly() async {
    let draft = .blank |> UpdateDraft.lens.update.isPublic .~ true
    await withEnvironment(apiService: MockService(fetchDraftResponse: draft)) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.vm.inputs.isBackersOnlyOn(true)

      self.vm.inputs.closeButtonTapped()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(1)
    }
  }

  func testErrorLoadingDraft() async {
    await withEnvironment(apiService: MockService(fetchDraftError: .couldNotParseJSON)) {
      self.showLoadFailure.assertValueCount(0)
      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(0)

      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.showLoadFailure.assertValueCount(1)
      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(1)
    }
  }

  func testErrorSavingDraft() async {
    let apiService = MockService(fetchDraftResponse: .blank, updateDraftError: .couldNotParseJSON)
    await withEnvironment(apiService: apiService) {
      self.vm.inputs.configureWith(project: .template)
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.vm.inputs.bodyTextChanged(to: "Hello, world!")

      self.vm.inputs.closeButtonTapped()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.notifyPresenterViewControllerWantsDismissal.assertValueCount(0)
      self.showSaveFailure.assertValueCount(1)
    }
  }
}
