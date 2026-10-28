@testable import KsApi
@testable import Library
import Prelude
import ReactiveSwift
import XCTest

@MainActor
final class CreatorDraftsFeatureTests: XCTestCase {
  private var provider: ControlledCreatorDraftsProvider!
  private var feature: CreatorDraftsFeature!
  private let route = UUID()
  private var disposables = CompositeDisposable()

  override func setUp() async throws {
    try await super.setUp()
    let provider = ControlledCreatorDraftsProvider()
    self.provider = provider
    self.feature = CreatorDraftsFeature(
      sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
      makeProvider: { provider }, sleep: { _ in }
    )
    await self.feature.load(project: .template, route: self.route)
  }
  override func tearDown() async throws {
    self.disposables.dispose()
    self.feature.reset()
    self.provider.loads.releaseAll()
    self.provider.saves.releaseAll()
    self.provider.adds.releaseAll()
    self.provider.removes.releaseAll()
    await self.feature.waitForOperations()
    try await super.tearDown()
  }
  private func save(_ title: String) -> SignalProducer<UpdateDraft, ErrorEnvelope> {
    self.feature.saveResult(route: self.route, title: title, body: "Body", isPublic: false)
  }

  func testEquivalentSavesShareAndDifferentFieldsExecuteInOrder() async throws {
    var completed = 0
    self.disposables += self.save("First").startWithResult { _ in completed += 1 }
    self.disposables += self.save("First").startWithResult { _ in completed += 1 }
    self.disposables += self.save("Second").startWithResult { _ in completed += 1 }
    await self.provider.saves.waitFor(1)
    XCTAssertEqual(self.provider.titles, ["First"])
    try self.provider.saves.finish(0, .success(.template |> UpdateDraft.lens.update.title .~ "First"))
    await self.provider.saves.waitFor(2)
    XCTAssertEqual(self.provider.titles, ["First", "Second"])
    XCTAssertEqual(self.provider.savedDrafts[1].update.title, "First")
    try self.provider.saves.finish(1, .success(.template |> UpdateDraft.lens.update.title .~ "Second"))
    await self.feature.waitForOperations()
    XCTAssertEqual(completed, 3)
  }

  func testUploadSettlesBeforeSaveAndSaveUsesCurrentImages() async throws {
    self.disposables += self.feature.addResult(file: URL(fileURLWithPath: "/tmp/test.png"), route: self.route).startWithResult { _ in }
    self.disposables += self.save("After upload").startWithResult { _ in }
    await self.provider.adds.waitFor(1)
    XCTAssertEqual(self.provider.saves.count, 0)
    try self.provider.adds.finish(0, .success(.template))
    await self.provider.saves.waitFor(1)
    XCTAssertEqual(self.provider.savedDrafts.first?.images.map(\.id), [UpdateDraft.Image.template.id])
    try self.provider.saves.finish(0, .success(self.provider.savedDrafts[0]))
    await self.feature.waitForOperations()
  }

  func testFailureDoesNotBlockFollowingEditAndRetryIsExplicit() async throws {
    var failures = 0
    self.disposables += self.save("First").startWithResult { if case .failure = $0 { failures += 1 } }
    self.disposables += self.save("Second").startWithResult { _ in }
    await self.provider.saves.waitFor(1)
    try self.provider.saves.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.provider.saves.waitFor(2)
    try self.provider.saves.finish(1, .success(.template))
    await self.feature.waitForOperations()
    XCTAssertEqual(failures, 1)
    XCTAssertEqual(self.provider.saves.count, 2)
  }

  func testScreenReleaseSuppressesDeliveryButAdmittedSaveSettles() async throws {
    var emitted = false
    self.disposables += self.save("First").startWithResult { _ in emitted = true }
    await self.provider.saves.waitFor(1)
    self.feature.release(route: self.route)
    try self.provider.saves.finish(0, .success(.template))
    await self.feature.waitForOperations()
    XCTAssertFalse(emitted)
    XCTAssertEqual(self.provider.saves.count, 1)
  }

  func testSessionChangeSuppressesOutcomeAndQueuedMutation() async throws {
    var emitted = false
    self.disposables += self.save("First").startWithResult { _ in emitted = true }
    self.disposables += self.save("Second").startWithResult { _ in emitted = true }
    await self.provider.saves.waitFor(1)
    self.feature.sessionFeature.sessionChanged()
    try self.provider.saves.finish(0, .success(.template))
    await self.feature.waitForOperations()
    XCTAssertFalse(emitted)
    XCTAssertEqual(self.provider.saves.count, 1)
  }

  func testReplacedReadRejectsLateSuccess() async throws {
    self.provider.pauseLoad = true
    var loaded: [String] = []
    self.disposables += self.feature.loads.observeValues {
      if case .success(let draft) = $0.1 { loaded.append(draft.update.title) }
    }
    let first = self.feature.requestLoad(project: .template, route: self.route)
    await self.provider.loads.waitFor(1)
    let second = self.feature.requestLoad(project: .template |> Project.lens.id .~ 2, route: self.route)
    await self.provider.loads.waitFor(2)
    try self.provider.loads.finish(1, .success(.template |> UpdateDraft.lens.update.title .~ "Current"))
    await second.value
    try self.provider.loads.finish(0, .success(.template |> UpdateDraft.lens.update.title .~ "Obsolete"))
    await first.value
    XCTAssertEqual(loaded, ["Current"])
  }

  func testUnchangedDraftDoesNotSendWrite() async throws {
    let draft = UpdateDraft.template
    let saved = try await self.feature.save(route: self.route, title: draft.update.title,
      body: draft.update.body ?? "", isPublic: draft.update.isPublic)
    XCTAssertEqual(saved.update.title, draft.update.title)
    XCTAssertEqual(self.provider.saves.count, 0)
  }

  func testUnsupportedVideoRemovalUsesFailureOutput() async {
    var failed = false
    self.disposables += self.feature.removeResult(attachment: .video(.template), route: self.route)
      .startWithResult { if case .failure = $0 { failed = true } }
    await self.feature.waitForOperations()
    XCTAssertTrue(failed)
    XCTAssertEqual(self.provider.removes.count, 0)
  }

  func testNewUploadDoesNotRestorePreviouslyDeletedImage() async throws {
    var lists: [[Int]] = []
    self.disposables += self.feature.attachments.observeValues { lists.append($0.1.map(\.id)) }
    self.disposables += self.feature.addResult(file: URL(fileURLWithPath: "/tmp/one.png"), route: self.route).startWithResult { _ in }
    await self.provider.adds.waitFor(1)
    try self.provider.adds.finish(0, .success(.template))
    await self.feature.waitForOperations()
    self.disposables += self.feature.removeResult(attachment: .image(.template), route: self.route).startWithResult { _ in }
    await self.provider.removes.waitFor(1)
    try self.provider.removes.finish(0, .success(.template))
    await self.feature.waitForOperations()
    self.disposables += self.feature.addResult(file: URL(fileURLWithPath: "/tmp/two.png"), route: self.route).startWithResult { _ in }
    await self.provider.adds.waitFor(2)
    try self.provider.adds.finish(1, .success(.template |> UpdateDraft.Image.lens.id .~ 2))
    await self.feature.waitForOperations()
    XCTAssertEqual(lists, [[1], [], [2]])
  }

  func testPreviewThenCloseDoesNotNavigateWithEarlierSaveResponse() async throws {
    let vm = UpdateDraftViewModel(creatorDraftsFeature: self.feature)
    var previews = 0
    var dismissals = 0
    self.disposables += vm.goToPreview.observeValues { _ in previews += 1 }
    self.disposables += vm.notifyPresenterViewControllerWantsDismissal.observeValues { dismissals += 1 }
    vm.configureWith(project: .template)
    vm.viewDidLoad()
    await self.feature.waitForOperations()
    vm.titleTextChanged(to: "Preview version")
    vm.previewButtonTapped()
    await self.provider.saves.waitFor(1)
    vm.titleTextChanged(to: "Close version")
    vm.closeButtonTapped()
    try self.provider.saves.finish(0, .success(.template |> UpdateDraft.lens.update.title .~ "Preview version"))
    await self.provider.saves.waitFor(2)
    XCTAssertEqual(previews, 0)
    XCTAssertEqual(dismissals, 0)
    try self.provider.saves.finish(1, .success(.template |> UpdateDraft.lens.update.title .~ "Close version"))
    await self.feature.waitForOperations()
    XCTAssertEqual(previews, 0)
    XCTAssertEqual(dismissals, 1)
  }
}

@MainActor
private final class ControlledCreatorDraftsProvider: CreatorDraftsProvider {
  var pauseLoad = false
  let loads = AccountRequestGate<UpdateDraft>()
  let saves = AccountRequestGate<UpdateDraft>()
  let adds = AccountRequestGate<UpdateDraft.Image>()
  let removes = AccountRequestGate<UpdateDraft.Image>()
  var titles: [String] = []
  var savedDrafts: [UpdateDraft] = []
  func load(project: Project) async throws -> UpdateDraft {
    if self.pauseLoad { return try await self.loads.request() }
    return .template
  }
  func save(draft: UpdateDraft, title: String, body: String, isPublic: Bool) async throws -> UpdateDraft {
    self.titles.append(title)
    self.savedDrafts.append(draft)
    return try await self.saves.request()
  }
  func add(file: URL, draft: UpdateDraft) async throws -> UpdateDraft.Image { try await self.adds.request() }
  func remove(image: UpdateDraft.Image, draft: UpdateDraft) async throws -> UpdateDraft.Image { try await self.removes.request() }
}
