@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class ActivityProjectStatusViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  fileprivate let vm = ActivityProjectStatusViewModel()
  func testProject_Launched() {
    let project = .cosmicSurgery
      |> Project.lens.name .~ "A Very Important Project About Kittens and Puppies"
      |> Project.lens.stats.fundingProgress .~ 0

    let activity = .template
      |> Activity.lens.id .~ 0
      |> Activity.lens.project .~ project
      |> Activity.lens.category .~ .launch

    self.vm.configureWith(activity: activity)

    XCTAssertEqual(self.vm.metadataText, Strings.Friend_name_launched_a_project(friend_name: project.creator.name))
    XCTAssertEqual(self.vm.percentFundedText.string, "0%")
    XCTAssertEqual(self.vm.projectImageURL?.absoluteString, project.photo.full)
    XCTAssertEqual(self.vm.projectName, project.name)
  }

  func testProject_You_Launched() {
    let you = User.projectCreator
      |> \.id .~ 4
      |> \.name .~ "Gina B"

    let project = .cosmicSurgery
      |> Project.lens.name .~ "A Very Important Project About Kittens and Puppies"
      |> Project.lens.stats.fundingProgress .~ 0.01
      |> Project.lens.creator .~ you

    let activity = .template
      |> Activity.lens.id .~ 0
      |> Activity.lens.project .~ project
      |> Activity.lens.category .~ .launch

    withEnvironment(currentUser: you) {
      self.vm.configureWith(activity: activity)

      XCTAssertEqual(self.vm.metadataText, Strings.You_Launched())
      XCTAssertEqual(self.vm.percentFundedText.string, "1%")
      XCTAssertEqual(self.vm.projectImageURL?.absoluteString, project.photo.full)
      XCTAssertEqual(self.vm.projectName, project.name)
    }
  }

  func testProject_Success() {
    let you = User.projectCreator
      |> \.id .~ 4
      |> \.name .~ "Gina B"

    let project = .cosmicSurgery
      |> Project.lens.name .~ "A Very Important Project About Kittens and Puppies"
      |> Project.lens.stats.fundingProgress .~ 1.3
      |> Project.lens.creator .~ you

    let activity = .template
      |> Activity.lens.id .~ 0
      |> Activity.lens.project .~ project
      |> Activity.lens.category .~ .success

    self.vm.configureWith(activity: activity)

    XCTAssertEqual(self.vm.metadataText, Strings.activity_successfully_funded())
    XCTAssertEqual(self.vm.percentFundedText.string, "129%")
    XCTAssertEqual(self.vm.projectImageURL?.absoluteString, project.photo.full)
    XCTAssertEqual(self.vm.projectName, project.name)
  }

  func testProject_Failure() {
    let project = .cosmicSurgery
      |> Project.lens.name .~ "A Very Important Project About Kittens and Puppies"
      |> Project.lens.stats.fundingProgress .~ 0.6

    let activity = .template
      |> Activity.lens.id .~ 0
      |> Activity.lens.project .~ project
      |> Activity.lens.category .~ .failure

    self.vm.configureWith(activity: activity)

    XCTAssertEqual(self.vm.metadataText, Strings.Unsuccessfully_Funded())
    XCTAssertEqual(self.vm.percentFundedText.string, "60%")
    XCTAssertEqual(self.vm.projectImageURL?.absoluteString, project.photo.full)
    XCTAssertEqual(self.vm.projectName, project.name)
  }

  func testProject_Canceled() {
    let project = .cosmicSurgery
      |> Project.lens.name .~ "A Very Important Project About Kittens and Puppies"
      |> Project.lens.stats.fundingProgress .~ 0.01

    let activity = .template
      |> Activity.lens.id .~ 0
      |> Activity.lens.project .~ project
      |> Activity.lens.category .~ .cancellation

    self.vm.configureWith(activity: activity)

    XCTAssertEqual(self.vm.metadataText, Strings.Project_Cancelled())
    XCTAssertEqual(self.vm.percentFundedText.string, "1%")
    XCTAssertEqual(self.vm.projectImageURL?.absoluteString, project.photo.full)
    XCTAssertEqual(self.vm.projectName, project.name)
  }

  func testProject_Suspended() {
    let project = .cosmicSurgery
      |> Project.lens.name .~ "A Very Important Project About Kittens and Puppies"
      |> Project.lens.stats.fundingProgress .~ 0.04

    let activity = .template
      |> Activity.lens.id .~ 0
      |> Activity.lens.project .~ project
      |> Activity.lens.category .~ .suspension

    self.vm.configureWith(activity: activity)

    XCTAssertEqual(self.vm.metadataText, Strings.Project_Suspended())
    XCTAssertEqual(self.vm.percentFundedText.string, "4%")
    XCTAssertEqual(self.vm.projectImageURL?.absoluteString, project.photo.full)
    XCTAssertEqual(self.vm.projectName, project.name)
  }
  func testProgressClampsAndMissingProjectKeepsProjectFields() {
    let project = Project.template |> Project.lens.stats.fundingProgress .~ 2.5
    self.vm.configureWith(activity: Activity.template |> Activity.lens.project .~ project)
    XCTAssertEqual(self.vm.fundingProgressPercentage, 1)
    self.vm.configureWith(activity: Activity.template |> Activity.lens.project .~ nil)
    XCTAssertEqual(self.vm.fundingProgressPercentage, 1)
    XCTAssertEqual(self.vm.projectName, project.name)
  }

}
