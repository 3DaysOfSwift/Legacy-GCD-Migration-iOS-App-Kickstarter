@testable import Kickstarter_iOS
import GraphAPI
import KDS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class BackerDashboardProjectCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  private let vm = BackerDashboardProjectCellViewModel()

  private let metadataIconIsHidden = DashboardRecorder<Bool>()
  private let metadataText = DashboardRecorder<String>()
  private let prelaunchProject = DashboardRecorder<Bool>()
  private let percentFundedText = DashboardRecorder<String>()
  private let photoURL = DashboardRecorder<String>()
  private let progress = DashboardRecorder<Float>()
  private let progressBarColor = DashboardRecorder<UIColor>()
  private let projectTitleText = DashboardRecorder<String>()
  private let savedIconIsHidden = DashboardRecorder<Bool>()

  override func setUp() async throws {
    try await super.setUp()
    self.vm.onChange = {
      guard let state = self.vm.state else { return }
      self.metadataIconIsHidden.values.append(state.metadataIconIsHidden)
      self.metadataText.values.append(state.metadataText)
      self.percentFundedText.values.append(state.percentFundedText.string)
      self.photoURL.values.append(state.photoURL?.absoluteString ?? "")
      self.progress.values.append(state.progress)
      self.prelaunchProject.values.append(state.prelaunchProject)
      self.progressBarColor.values.append(state.progressBarColor)
      self.projectTitleText.values.append(state.projectTitleText.string)
      self.savedIconIsHidden.values.append(state.savedIconIsHidden)
    }
  }

  func testProjectData_Live() {
    let endingInDays = self.endingIn(days: 14)

    let project = .template
      |> Project.lens.name .~ "Best of Lazy Bathtub Cat"
      |> Project.lens.photo.full .~ "http://www.lazybathtubcat.com/vespa.jpg"
      |> Project.lens.stats.fundingProgress .~ 0.5
      |> Project.lens.dates.deadline .~ endingInDays
      |> Project.lens.prelaunchActivated .~ false
      |> Project.lens.displayPrelaunch .~ false

    self.vm.configureWith(project: project)

    self.metadataIconIsHidden.assertValues([false])
    self.metadataText.assertValues(["14 days"])
    self.percentFundedText.assertValues(["50%"])
    self.photoURL.assertValues(["http://www.lazybathtubcat.com/vespa.jpg"])
    self.progress.assertValues([0.5])
    self.progressBarColor.assertValues([LegacyColors.ksr_create_700.uiColor()])
    self.projectTitleText.assertValues(["Best of Lazy Bathtub Cat"])
    self.savedIconIsHidden.assertValues([true])
  }

  func testProjectData_Successful() {
    let project = .template
      |> Project.lens.name .~ "Best of Lazy Bathtub Cat"
      |> Project.lens.photo.full .~ "http://www.lazybathtubcat.com/vespa.jpg"
      |> Project.lens.stats.fundingProgress .~ 1.1
      |> Project.lens.state .~ .successful
      |> Project.lens.prelaunchActivated .~ false
      |> Project.lens.displayPrelaunch .~ false

    self.vm.configureWith(project: project)

    self.metadataIconIsHidden.assertValues([true])
    self.metadataText.assertValues(["Successful"])
    self.percentFundedText.assertValues(["110%"])
    self.photoURL.assertValues(["http://www.lazybathtubcat.com/vespa.jpg"])
    self.progress.assertValues([1.1])
    self.progressBarColor.assertValues([LegacyColors.ksr_create_700.uiColor()])
    self.projectTitleText.assertValues(["Best of Lazy Bathtub Cat"])
    self.savedIconIsHidden.assertValues([true])
  }

  func testProjectData_Failed() {
    let project = .template
      |> Project.lens.name .~ "Best of Lazy Bathtub Cat"
      |> Project.lens.photo.full .~ "http://www.lazybathtubcat.com/vespa.jpg"
      |> Project.lens.stats.fundingProgress .~ 0.2
      |> Project.lens.state .~ .failed
      |> Project.lens.prelaunchActivated .~ false
      |> Project.lens.displayPrelaunch .~ false

    self.vm.configureWith(project: project)

    self.metadataIconIsHidden.assertValues([true])
    self.metadataText.assertValues(["Unsuccessful"])
    self.percentFundedText.assertValues(["20%"])
    self.photoURL.assertValues(["http://www.lazybathtubcat.com/vespa.jpg"])
    self.progress.assertValues([0.2])
    self.progressBarColor.assertValues([LegacyColors.ksr_support_300.uiColor()])
    self.projectTitleText.assertValues(["Best of Lazy Bathtub Cat"])
    self.savedIconIsHidden.assertValues([true])
  }

  func testProjectData_Saved() {
    let project = .template
      |> Project.lens.name .~ "Best of Lazy Bathtub Cat"
      |> Project.lens.photo.full .~ "http://www.lazybathtubcat.com/vespa.jpg"
      |> Project.lens.stats.fundingProgress .~ 1.1
      |> Project.lens.state .~ .successful
      |> Project.lens.personalization.isStarred .~ true
      |> Project.lens.prelaunchActivated .~ false
      |> Project.lens.displayPrelaunch .~ false

    self.vm.configureWith(project: project)

    self.metadataIconIsHidden.assertValues([true])
    self.metadataText.assertValues(["Successful"])
    self.percentFundedText.assertValues(["110%"])
    self.photoURL.assertValues(["http://www.lazybathtubcat.com/vespa.jpg"])
    self.progress.assertValues([1.1])
    self.progressBarColor.assertValues([LegacyColors.ksr_create_700.uiColor()])
    self.projectTitleText.assertValues(["Best of Lazy Bathtub Cat"])
    self.savedIconIsHidden.assertValues([false])
  }

  func testProjectData_Prelaunch_Displayed() {
    let project = .template
      |> Project.lens.name .~ "Best of Lazy Bathtub Cat"
      |> Project.lens.photo.full .~ "http://www.lazybathtubcat.com/vespa.jpg"
      |> Project.lens.prelaunchActivated .~ true
      |> Project.lens.displayPrelaunch .~ true
      |> Project.lens.personalization.isStarred .~ true

    self.prelaunchProject.assertDidNotEmitValue()

    self.vm.configureWith(project: project)

    self.prelaunchProject.assertValues([true])
    self.metadataText.assertValues(["Coming soon"])
  }

  func testProjectData_Prelaunch_ActivatedButNotDisplayed() {
    let project = .template
      |> Project.lens.name .~ "Best of Lazy Bathtub Cat"
      |> Project.lens.photo.full .~ "http://www.lazybathtubcat.com/vespa.jpg"
      |> Project.lens.prelaunchActivated .~ true
      |> Project.lens.displayPrelaunch .~ false
      |> Project.lens.personalization.isStarred .~ true
      |> Project.lens.state .~ .successful

    self.prelaunchProject.assertDidNotEmitValue()

    self.vm.configureWith(project: project)

    self.prelaunchProject.assertValues([false])
    self.metadataText.assertValues(["Successful"])
  }

  func testProjectData_Prelaunch_DateIsZero() {
    let project = .template
      |> Project.lens.name .~ "Best of Lazy Bathtub Cat"
      |> Project.lens.photo.full .~ "http://www.lazybathtubcat.com/vespa.jpg"
      |> Project.lens.prelaunchActivated .~ nil
      |> Project.lens.displayPrelaunch .~ nil
      |> Project.lens.dates.launchedAt .~ 0
      |> Project.lens.personalization.isStarred .~ true
      |> Project.lens.state .~ .successful

    self.prelaunchProject.assertDidNotEmitValue()

    self.vm.configureWith(project: project)

    self.prelaunchProject.assertValues([true])
    self.metadataText.assertValues(["Coming soon"])
  }

  func testProjectData_GraphQL_Live() {
    let endingInDays = self.endingIn(days: 10)

    let jsonString = """
      {
              "__typename": "Project",
              "projectId": "pid",
              "name": "Test Project Data Live",
              "projectState": "LIVE",
              "image": {
                "__typename": "Image",
                "id": "placeholder",
                "url": "https://www.kickerstart.com/image.png"
              },
              "goal": {
                "__typename": "Money",
                "amount": "500.0",
                "currency": "USD",
                "symbol": "$"
              },
              "pledged": {
                "__typename": "Money",
                "amount": "250.0",
                "currency": "USD",
                "symbol": "$"
              },
              "isLaunched": true,
              "projectPrelaunchActivated": false,
              "deadlineAt": \(endingInDays),
              "projectLaunchedAt": 1706727593,
              "isWatched": false
    }
    """

    let fragment: GraphAPI.BackerDashboardProjectCellFragment = try! testGraphObject(jsonString: jsonString)

    self.vm.configureWith(project: fragment)

    self.metadataIconIsHidden.assertValues([false])
    self.metadataText.assertValues(["10 days"])
    self.percentFundedText.assertValues(["50%"])
    self.photoURL.assertValues(["https://www.kickerstart.com/image.png"])
    self.progress.assertValues([0.5])
    self.progressBarColor.assertValues([LegacyColors.ksr_create_700.uiColor()])
    self.projectTitleText.assertValues(["Test Project Data Live"])
    self.savedIconIsHidden.assertValues([true])
  }

  func testProjectData_GraphQL_Successful() {
    let jsonString = """
        {
          "__typename": "Project",
          "projectId": "pid",
          "name": "Test Project Data Successful",
          "projectState": "SUCCESSFUL",
          "image": {
            "__typename": "Image",
            "id": "id",
            "url": "https://www.kickerstart.com/image.png"
          },
          "goal": {
            "__typename": "Money",
            "amount": "500.0",
            "currency": "CAD",
            "symbol": "$"
          },
          "pledged": {
            "__typename": "Money",
            "amount": "2000.00",
            "currency": "CAD",
            "symbol": "$"
          },
          "isLaunched": true,
          "projectPrelaunchActivated": false,
          "deadlineAt": 1625071247,
          "projectLaunchedAt": 1622479247,
          "isWatched": false
        }
    """

    let fragment: GraphAPI.BackerDashboardProjectCellFragment = try! testGraphObject(jsonString: jsonString)

    self.vm.configureWith(project: fragment)

    self.metadataIconIsHidden.assertValues([true])
    self.metadataText.assertValues(["Successful"])
    self.percentFundedText.assertValues(["400%"])
    self.photoURL.assertValues(["https://www.kickerstart.com/image.png"])
    self.progress.assertValues([4.0])
    self.progressBarColor.assertValues([LegacyColors.ksr_create_700.uiColor()])
    self.projectTitleText.assertValues(["Test Project Data Successful"])
    self.savedIconIsHidden.assertValues([true])
  }

  func testProjectData_GraphQL_Failed() {
    let jsonString = """
        {
          "__typename": "Project",
          "projectId": "pid",
          "name": "Test Project Data Failed",
          "projectState": "FAILED",
          "image": {
            "__typename": "Image",
            "id": "id",
            "url": "https://www.kickerstart.com/image.png"
          },
          "goal": {
            "__typename": "Money",
            "amount": "500.0",
            "currency": "CAD",
            "symbol": "$"
          },
          "pledged": {
            "__typename": "Money",
            "amount": "50.0",
            "currency": "CAD",
            "symbol": "$"
          },
          "isLaunched": true,
          "projectPrelaunchActivated": false,
          "deadlineAt": 1625071247,
          "projectLaunchedAt": 1622479247,
          "isWatched": false
        }
    """

    let fragment: GraphAPI.BackerDashboardProjectCellFragment = try! testGraphObject(jsonString: jsonString)

    self.vm.configureWith(project: fragment)

    self.metadataIconIsHidden.assertValues([true])
    self.metadataText.assertValues(["Unsuccessful"])
    self.percentFundedText.assertValues(["10%"])
    self.photoURL.assertValues(["https://www.kickerstart.com/image.png"])
    self.progress.assertValues([0.1])
    self.progressBarColor.assertValues([LegacyColors.ksr_support_300.uiColor()])
    self.projectTitleText.assertValues(["Test Project Data Failed"])
    self.savedIconIsHidden.assertValues([true])
  }

  func testProjectData_GraphQL_Saved() {
    let endingInDays = self.endingIn(days: 94)

    let jsonString = """
      {
              "__typename": "Project",
              "projectId": "pid",
              "name": "Test Project Data Live",
              "projectState": "LIVE",
              "image": {
                "__typename": "Image",
                "id": "placeholder",
                "url": "https://www.kickerstart.com/image.png"
              },
              "goal": {
                "__typename": "Money",
                "amount": "500.0",
                "currency": "USD",
                "symbol": "$"
              },
              "pledged": {
                "__typename": "Money",
                "amount": "250.0",
                "currency": "USD",
                "symbol": "$"
              },
              "isLaunched": true,
              "projectPrelaunchActivated": false,
              "deadlineAt": \(endingInDays),
              "projectLaunchedAt": 1706727593,
              "isWatched": true
    }
    """

    let fragment: GraphAPI.BackerDashboardProjectCellFragment = try! testGraphObject(jsonString: jsonString)

    self.vm.configureWith(project: fragment)

    self.metadataIconIsHidden.assertValues([false])
    self.metadataText.assertValues(["94 days"])
    self.percentFundedText.assertValues(["50%"])
    self.photoURL.assertValues(["https://www.kickerstart.com/image.png"])
    self.progress.assertValues([0.5])
    self.progressBarColor.assertValues([LegacyColors.ksr_create_700.uiColor()])
    self.projectTitleText.assertValues(["Test Project Data Live"])
    self.savedIconIsHidden.assertValues([false])
  }

  func testProjectData_GraphQL_Prelaunch_Displayed() {
    let jsonString = """
        {
          "__typename": "Project",
          "projectId": "pid",
          "name": "Test Project Data Prelaunch",
          "projectState": "SUBMITTED",
          "image": {
            "__typename": "Photo",
            "id": "imageid",
            "url": "https://www.kickstarter.com/image.png"
          },
          "goal": {
            "__typename": "Money",
            "amount": "100000.0",
            "currency": "CAD",
            "symbol": "$"
          },
          "pledged": {
            "__typename": "Money",
            "amount": "0.0",
            "currency": "CAD",
            "symbol": "$"
          },
          "isLaunched": false,
          "projectPrelaunchActivated": true,
          "deadlineAt": null,
          "projectLaunchedAt": null,
          "isWatched": false
        }
    """

    let fragment: GraphAPI.BackerDashboardProjectCellFragment = try! testGraphObject(jsonString: jsonString)

    self.vm.configureWith(project: fragment)

    self.prelaunchProject.assertValues([true])
    self.metadataText.assertValues(["Coming soon"])
  }

  func testProjectData_GraphQL_Prelaunch_ActivatedButNotDisplayed() {
    let jsonString = """
        {
          "__typename": "Project",
          "projectId": "pid",
          "name": "Test Project Data Successful",
          "projectState": "SUCCESSFUL",
          "image": {
            "__typename": "Image",
            "id": "id",
            "url": "https://www.kickerstart.com/image.png"
          },
          "goal": {
            "__typename": "Money",
            "amount": "500.0",
            "currency": "CAD",
            "symbol": "$"
          },
          "pledged": {
            "__typename": "Money",
            "amount": "2000.00",
            "currency": "CAD",
            "symbol": "$"
          },
          "isLaunched": true,
          "projectPrelaunchActivated": true,
          "deadlineAt": 1625071247,
          "projectLaunchedAt": 1622479247,
          "isWatched": false
        }
    """

    let fragment: GraphAPI.BackerDashboardProjectCellFragment = try! testGraphObject(jsonString: jsonString)

    self.vm.configureWith(project: fragment)

    self.prelaunchProject.assertValues([false])
    self.metadataText.assertValues(["Successful"])
  }

  private func endingIn(days: Int) -> TimeInterval {
    self.dateType.init().timeIntervalSince1970 + 60.0 * 60.0 * 24.0 * Double(days)
  }
}

private final class DashboardRecorder<Value: Equatable> {
  var values: [Value] = []
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, message, file: file, line: line)
  }
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
