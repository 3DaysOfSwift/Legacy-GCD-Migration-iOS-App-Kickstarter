@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import ReactiveExtensions
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest
import UIKit
/*
 internal final class ShareViewModelTests: TestCase {
   internal let vm: ShareViewModelType = ShareViewModel()

   fileprivate let showShareSheet = TestObserver<(UIActivityViewController, UIView?), Never>()

   override func setUp() async throws {
     try await super.setUp()

     self.vm.outputs.showShareSheet.observe(self.showShareSheet.observer)
   }

   func testShowShareSheet_Discovery() {
     let project = .template |> Project.lens.id .~ 30
     let newProject = .template |> Project.lens.id .~ 55
     let view = UIView()

     self.vm.inputs.configureWith(shareContext: .discovery(project), shareContextView: view)
     self.vm.inputs.shareButtonTapped()
     self.vm.inputs.configureWith(shareContext: .discovery(newProject), shareContextView: view)

     self.showShareSheet.assertValueCount(1)
   }

   func testShowShareSheet_Project() {
     self.vm.inputs.configureWith(shareContext: .project(.template), shareContextView: nil)
     self.vm.inputs.shareButtonTapped()

     self.showShareSheet.assertValueCount(1)
   }

   func testShowShareSheet_Thanks() {
     self.vm.inputs.configureWith(shareContext: .thanks(.template), shareContextView: nil)
     self.vm.inputs.shareButtonTapped()

     self.showShareSheet.assertValueCount(1)
   }

   func testShowShareSheet_Update() {
     self.vm.inputs.configureWith(shareContext: .update(.template, .template), shareContextView: nil)
     self.vm.inputs.shareButtonTapped()

     self.showShareSheet.assertValueCount(1)
   }

   func testShowShareSheet_BackerOnlyUpdate() {
     self.vm.inputs.configureWith(
       shareContext: .update(
         .template,
         .template |> Update.lens.isPublic .~ false
       ),
       shareContextView: nil
     )
     self.vm.inputs.shareButtonTapped()

     self.showShareSheet.assertValueCount(1)
   }
 }
 */

@MainActor
final class ShareViewModelOwnershipTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testShareRequiresConfigurationAndPreservesSourceView() {
    let model = ShareViewModel()
    var sheets: [(UIActivityViewController, UIView?)] = []
    let observation = model.outputs.showShareSheet.observeValues { sheets.append($0) }
    defer { observation?.dispose() }
    model.inputs.shareButtonTapped()
    XCTAssertTrue(sheets.isEmpty)
    let source = UIView()
    model.inputs.configureWith(shareContext: .project(.template), shareContextView: source)
    XCTAssertTrue(sheets.isEmpty)
    model.inputs.shareButtonTapped()
    XCTAssertEqual(sheets.count, 1)
    XCTAssertTrue(sheets.first?.1 === source)
  }

  func testRepeatedShareUsesLatestSourceView() {
    let model = ShareViewModel()
    var sources: [UIView?] = []
    let observation = model.outputs.showShareSheet.observeValues { sources.append($0.1) }
    defer { observation?.dispose() }
    let first = UIView()
    let second = UIView()
    model.inputs.configureWith(shareContext: .discovery(.template), shareContextView: first)
    model.inputs.shareButtonTapped()
    model.inputs.configureWith(shareContext: .project(.template), shareContextView: second)
    model.inputs.shareButtonTapped()
    XCTAssertEqual(sources.count, 2)
    XCTAssertTrue(sources.first! === first)
    XCTAssertTrue(sources.last! === second)
  }
}
