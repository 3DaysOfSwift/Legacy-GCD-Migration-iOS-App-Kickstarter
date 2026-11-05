@testable import Kickstarter_iOS
import KDS
@testable import KsApi


import Prelude
import XCTest

/* swiftlint:disable force_unwrapping */
@MainActor
internal final class DiscoveryPostcardViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  internal let vm = DiscoveryPostcardViewModel()
  internal let backersTitleLabelText = PostcardRecorder<String>()
  internal let cellAccessibilityLabel = PostcardRecorder<String>()
  internal let cellAccessibilityValue = PostcardRecorder<String>()
  internal let deadlineSubtitleLabelText = PostcardRecorder<String>()
  internal let deadlineTitleLabelText = PostcardRecorder<String>()
  internal let fundingProgressBarViewHidden = PostcardRecorder<Bool>()
  internal let fundingProgressContainerViewHidden = PostcardRecorder<Bool>()
  internal let locationLabelText = PostcardRecorder<String>()
  internal let locationStackViewHidden = PostcardRecorder<Bool>()
  internal let metadataIcon = PostcardRecorder<UIImage?>()
  internal let metadataIconTintColor = PostcardRecorder<UIColor>()
  internal let metadataTextColor = PostcardRecorder<UIColor>()
  internal let metadataLabelText = PostcardRecorder<String>()
  internal let metadataViewHidden = PostcardRecorder<Bool>()
  internal let percentFundedTitleLabelText = PostcardRecorder<String>()
  internal let progressPercentage = PostcardRecorder<Float>()
  internal let projectImageURL = PostcardRecorder<String?>()
  internal let projectNameAndBlurbLabelText = PostcardRecorder<String>()
  internal let projectStateIconHidden = PostcardRecorder<Bool>()
  internal let projectStateStackViewHidden = PostcardRecorder<Bool>()
  internal let projectStateSubtitleLabelText = PostcardRecorder<String>()
  internal let projectStateTitleLabelColor = PostcardRecorder<UIColor>()
  internal let projectStateTitleLabelText = PostcardRecorder<String>()
  internal let projectStatsStackViewHidden = PostcardRecorder<Bool>()
  internal let socialImageURL = PostcardRecorder<String?>()
  internal let socialLabelText = PostcardRecorder<String>()
  internal let socialStackViewHidden = PostcardRecorder<Bool>()
  internal let projectCategoryName = PostcardRecorder<String>()
  internal let projectCategoryViewHidden = PostcardRecorder<Bool>()
  internal let projectCategoryStackViewHidden = PostcardRecorder<Bool>()
  internal let projectIsStaffPickViewHidden = PostcardRecorder<Bool>()

  internal override func setUp() async throws {
    try await super.setUp()
    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .backersTitleLabelText(value): self.backersTitleLabelText.record(value)
      case .backersSubtitleLabelText: break
      case let .cellAccessibilityLabel(value): self.cellAccessibilityLabel.record(value)
      case let .cellAccessibilityValue(value): self.cellAccessibilityValue.record(value)
      case let .deadlineSubtitleLabelText(value): self.deadlineSubtitleLabelText.record(value)
      case let .deadlineTitleLabelText(value): self.deadlineTitleLabelText.record(value)
      case let .fundingProgressBarViewHidden(value): self.fundingProgressBarViewHidden.record(value)
      case let .fundingProgressContainerViewHidden(value): self.fundingProgressContainerViewHidden.record(value)
      case let .locationStackViewHidden(value): self.locationStackViewHidden.record(value)
      case let .locationLabelText(value): self.locationLabelText.record(value)
      case let .metadataLabelText(value): self.metadataLabelText.record(value)
      case let .metadataIcon(value): self.metadataIcon.record(value)
      case let .metadataIconImageViewTintColor(value): self.metadataIconTintColor.record(value)
      case let .metadataTextColor(value): self.metadataTextColor.record(value)
      case let .metadataViewHidden(value): self.metadataViewHidden.record(value)
      case let .percentFundedTitleLabelText(value): self.percentFundedTitleLabelText.record(value)
      case let .progressPercentage(value): self.progressPercentage.record(value)
      case let .projectImageURL(value): self.projectImageURL.record(value?.absoluteString)
      case let .projectNameAndBlurbLabelText(value): self.projectNameAndBlurbLabelText.record(value.string)
      case let .projectStateIconHidden(value): self.projectStateIconHidden.record(value)
      case let .projectStateStackViewHidden(value): self.projectStateStackViewHidden.record(value)
      case let .projectStateSubtitleLabelText(value): self.projectStateSubtitleLabelText.record(value)
      case let .projectStateTitleLabelColor(value): self.projectStateTitleLabelColor.record(value)
      case let .projectStateTitleLabelText(value): self.projectStateTitleLabelText.record(value)
      case let .projectCategoryName(value): self.projectCategoryName.record(value)
      case let .projectIsStaffPickLabelHidden(value): self.projectIsStaffPickViewHidden.record(value)
      case let .projectCategoryViewHidden(value): self.projectCategoryViewHidden.record(value)
      case let .projectCategoryStackViewHidden(value): self.projectCategoryStackViewHidden.record(value)
      case let .projectStatsStackViewHidden(value): self.projectStatsStackViewHidden.record(value)
      case let .socialImageURL(value): self.socialImageURL.record(value?.absoluteString)
      case let .socialLabelText(value): self.socialLabelText.record(value)
      case let .socialStackViewHidden(value): self.socialStackViewHidden.record(value)
      }
    }
  }

  func testCellAccessibility() {
    let project = .template
      |> Project.lens.name .~ "Hammocks for All"
      |> Project.lens.blurb .~ "Let's make hammocks universal for all creatures!"

    self.vm.configure(with: (project, nil, nil))
    self.cellAccessibilityLabel.assertValues([project.name])
    self.cellAccessibilityValue.assertValues([project.blurb + ". "])
  }

  func testCellAccessibilityProjectCancelledState() {
    let project = .template
      |> Project.lens.name .~ "Hammocks for All"
      |> Project.lens.blurb .~ "Let's make hammocks universal for all creatures!"
      |> Project.lens.state .~ .canceled

    self.vm.configure(with: (project, nil, nil))
    self.cellAccessibilityLabel.assertValues([project.name])
    self.cellAccessibilityValue.assertValues([project.blurb + ". " + "Project cancelled"])
  }

  @MainActor
  func testMetadata() {
    let featuredAt = AppEnvironment.current.calendar.startOfDay(for: MockDate().date).timeIntervalSince1970

    let backedProject = .template
      |> Project.lens.personalization.isBacking .~ true

    let featuredProject = .template
      |> \.category .~ Project.Category.art
      |> Project.lens.dates.featuredAt .~ featuredAt

    let backedColor: UIColor = LegacyColors.ksr_create_700.uiColor()
    let featuredColor: UIColor = LegacyColors.ksr_support_700.uiColor()

    let backedImage = image(named: "metadata-backing")
    let featuredImage = image(named: "metadata-featured")

    withEnvironment(currentUser: nil) {
      self.vm.configure(with: (Project.template, nil, nil))

      self.metadataLabelText.assertValueCount(0, "No metadata shown for logged out user.")
      self.metadataViewHidden.assertValues([true])

      AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeeef", user: User.template))
      self.vm.configure(with: (backedProject, nil, nil))

      self.metadataLabelText.assertValues([Strings.discovery_baseball_card_metadata_backer()])
      self.metadataViewHidden.assertValues([true, false])
      self.metadataIcon.assertValues([backedImage])
      self.metadataTextColor.assertValues([backedColor])
      self.metadataIconTintColor.assertValues([backedColor])

      self.metadataLabelText.assertValues(
        [
          Strings.discovery_baseball_card_metadata_backer()
        ], "Starred metadata takes precedence."
      )

      self.metadataViewHidden.assertValues([true, false])
      self.metadataIcon.assertValues([backedImage])
      self.metadataTextColor.assertValues([backedColor])
      self.metadataIconTintColor.assertValues([backedColor])

      self.vm.configure(with: (featuredProject, nil, nil))
      guard let parentName = featuredProject.category?.parentName else { return }
      self.metadataLabelText.assertValues(
        [
          Strings.discovery_baseball_card_metadata_backer(),
          Strings.discovery_baseball_card_metadata_featured_project(
            category_name: parentName
          )
        ], "Featured metadata emits."
      )

      self.metadataViewHidden.assertValues([true, false, false])
      self.metadataIcon.assertValues([backedImage, featuredImage])
      self.metadataTextColor.assertValues([backedColor, featuredColor])
      self.metadataIconTintColor.assertValues([backedColor, featuredColor])

      AppEnvironment.logout()

      // Implement when updating DiscoveryPageVC logout behavior.
      self.metadataViewHidden.assertValues([true, false, false])
    }
  }

  func testProjectStatsEmit() {
    let project = Project.template
    let deadline = project.dates.deadline!

    self.vm.configure(with: (project, nil, nil))

    self.backersTitleLabelText.assertValues([Format.wholeNumber(project.stats.backersCount)])

    let deadlineTitleAndSubtitle = Format.duration(secondsInUTC: deadline, useToGo: true)
    self.deadlineSubtitleLabelText.assertValues([deadlineTitleAndSubtitle.unit])
    self.deadlineTitleLabelText.assertValues([deadlineTitleAndSubtitle.time])

    self.percentFundedTitleLabelText.assertValues(
      [Format.percentage(project.stats.percentFunded)]
    )

    self.progressPercentage.assertValues([project.stats.fundingProgress])
    self.projectImageURL.assertValues([project.photo.full])
    self.projectNameAndBlurbLabelText.assertValues(
      ["\(project.name): \(project.blurb)"]
    )
  }

  func testProjectNamePunctuationIsRetained() {
    let project = .template
      |> Project.lens.name .~ "The Turtle Hat. Helping people come out of their shells!"

    self.vm.configure(with: (project, nil, nil))

    self.projectNameAndBlurbLabelText.assertValues(
      ["\(project.name) \(project.blurb)"]
    )
  }

  func testSocialData() {
    let oneFriend = [User.template |> \.name .~ "Milky"]

    let twoFriends = [
      User.template |> \.name .~ "Chad",
      User.template |> \.name .~ "Brad"
    ]

    let manyFriends = [
      User.template |> \.name .~ "Gayle",
      User.template |> \.name .~ "Eugene",
      User.template |> \.name .~ "Nancy",
      User.template |> \.name .~ "Phillis"
    ]

    let projectNoSocial = .template
      |> Project.lens.personalization.friends .~ nil

    let projectNoFriends = .template
      |> Project.lens.personalization.friends .~ []

    let projectOneFriend = .template
      |> Project.lens.personalization.friends .~ oneFriend

    let projectTwoFriends = .template
      |> Project.lens.personalization.friends .~ twoFriends

    let projectManyFriends = .template
      |> Project.lens.personalization.friends .~ manyFriends

    self.vm.configure(with: (projectNoSocial, nil, nil))
    self.socialImageURL.assertValues([nil])
    self.socialLabelText.assertValues([""])
    self.socialStackViewHidden.assertValues([true])

    self.vm.configure(with: (projectNoFriends, nil, nil))
    self.socialImageURL.assertValues([nil, nil])
    self.socialLabelText.assertValues(["", ""])
    self.socialStackViewHidden.assertValues([true])

    self.vm.configure(with: (projectOneFriend, nil, nil))
    self.socialImageURL.assertValues([nil, nil, oneFriend[0].avatar.medium])
    self.socialLabelText.assertValues(
      ["", "", Strings.project_social_friend_is_backer(friend_name: oneFriend[0].name)]
    )
    self.socialStackViewHidden.assertValues([true, false])

    self.vm.configure(with: (projectTwoFriends, nil, nil))
    self.socialImageURL.assertValues(
      [nil, nil, oneFriend[0].avatar.medium, twoFriends[0].avatar.medium],
      "First friend's avatar emits."
    )
    self.socialLabelText.assertValues(
      [
        "", "",
        Strings.project_social_friend_is_backer(friend_name: oneFriend.first?.name ?? ""),
        Strings.project_social_friend_and_friend_are_backers(
          friend_name: twoFriends[0].name,
          second_friend_name: twoFriends[1].name
        )
      ]
    )
    self.socialStackViewHidden.assertValues([true, false])

    self.vm.configure(with: (projectManyFriends, nil, nil))
    self.socialImageURL.assertValues([
      nil, nil, oneFriend[0].avatar.medium, twoFriends[0].avatar.medium,
      manyFriends[0].avatar.medium
    ], "First friend's avatar emits.")
    self.socialLabelText.assertValues(
      [
        "", "",
        Strings.project_social_friend_is_backer(friend_name: oneFriend.first?.name ?? ""),
        Strings.project_social_friend_and_friend_are_backers(
          friend_name: twoFriends[0].name,
          second_friend_name: twoFriends[1].name
        ),
        Strings.discovery_baseball_card_social_friends_are_backers(
          friend_name: manyFriends[0].name,
          second_friend_name: manyFriends[1].name, remaining_count: manyFriends.count - 2
        )
      ]
    )
    self.socialStackViewHidden.assertValues([true, false])
  }

  func testStatsAndStateViews() {
    let canceled = .template |> Project.lens.state .~ .canceled
    let failed = .template |> Project.lens.state .~ .failed
    let live = .template |> Project.lens.state .~ .live
    let successful = .template |> Project.lens.state .~ .successful
    let suspended = .template |> Project.lens.state .~ .suspended

    let greenColor = LegacyColors.ksr_create_700.uiColor()
    let navyColor = LegacyColors.ksr_support_700.uiColor()

    self.vm.configure(with: (live, nil, nil))
    self.projectStateStackViewHidden.assertValues([true])
    self.projectStateSubtitleLabelText.assertValueCount(1, "Empty subtitle string emits.")
    self.projectStatsStackViewHidden.assertValues([false])
    self.fundingProgressContainerViewHidden.assertValues([false])
    self.fundingProgressBarViewHidden.assertValues([false])

    self.vm.configure(with: (canceled, nil, nil))
    self.projectStateIconHidden.assertValues([true, true])
    self.projectStateSubtitleLabelText.assertValueCount(2)
    self.projectStateTitleLabelText.assertValues([
      "",
      Strings.Project_cancelled()
    ])
    self.projectStateTitleLabelColor.assertValues([navyColor])
    self.projectStateStackViewHidden.assertValues([true, false])
    self.projectStatsStackViewHidden.assertValues([false, true])
    self.fundingProgressBarViewHidden.assertValues([false, false])
    self.fundingProgressContainerViewHidden.assertValues([false, true])

    self.vm.configure(with: (failed, nil, nil))
    self.projectStateIconHidden.assertValues([true, true, true])
    self.projectStateSubtitleLabelText.assertValueCount(3)
    self.projectStateTitleLabelText.assertValues(
      [
        "",
        Strings.Project_cancelled(),
        Strings.dashboard_creator_project_funding_unsuccessful()
      ]
    )
    self.projectStateTitleLabelColor.assertValues([navyColor])
    self.projectStateStackViewHidden.assertValues([true, false])
    self.projectStatsStackViewHidden.assertValues([false, true])
    self.fundingProgressBarViewHidden.assertValues([false, false, true])
    self.fundingProgressContainerViewHidden.assertValues([false, true, false])

    self.vm.configure(with: (successful, nil, nil))
    self.projectStateIconHidden.assertValues([true, true, true, false])
    self.projectStateSubtitleLabelText.assertValueCount(4)
    self.projectStateTitleLabelText.assertValues(
      [
        "",
        Strings.Project_cancelled(),
        Strings.dashboard_creator_project_funding_unsuccessful(),
        Strings.Funding_successful()
      ]
    )
    self.projectStateTitleLabelColor.assertValues([navyColor, greenColor])
    self.projectStateStackViewHidden.assertValues([true, false])
    self.projectStatsStackViewHidden.assertValues([false, true])
    self.fundingProgressBarViewHidden.assertValues([false, false, true, false])
    self.fundingProgressContainerViewHidden.assertValues([false, true, false, false])

    self.vm.configure(with: (suspended, nil, nil))
    self.projectStateIconHidden.assertValues([true, true, true, false, true])
    self.projectStateSubtitleLabelText.assertValueCount(5)
    self.projectStateTitleLabelText.assertValues(
      [
        "",
        Strings.Project_cancelled(),
        Strings.dashboard_creator_project_funding_unsuccessful(),
        Strings.Funding_successful(),
        Strings.dashboard_creator_project_funding_suspended()
      ]
    )
    self.projectStateTitleLabelColor.assertValues([navyColor, greenColor, navyColor])
    self.projectStateStackViewHidden.assertValues([true, false])
    self.projectStatsStackViewHidden.assertValues([false, true])
    self.fundingProgressBarViewHidden.assertValues([false, false, true, false, false])
    self.fundingProgressContainerViewHidden.assertValues([false, true, false, false, true])
  }

  // MARK: - Project Category View

  func testShowsCategoryLabels_ParentCategorySelected() {
    let staffPickProject = Project.template
      |> Project.lens.staffPick .~ true
      |> Project.lens.category .~ .illustration

    self.vm.configure(with: (staffPickProject, KsApi.Category.art, nil))

    self.projectIsStaffPickViewHidden.assertValue(false)
    self.projectCategoryStackViewHidden.assertValue(false)
    self.projectCategoryName.assertValue(KsApi.Category.illustration.name)
    self.projectCategoryViewHidden.assertValue(false)
  }

  func testShowsCategoryLabels_AlwaysIfFilterCategoryIsNil() {
    self.vm.configure(with: (Project.template, nil, nil))

    self.projectCategoryStackViewHidden.assertValue(false)
  }

  func testHidesCategoryLabel_IfFilterCategoryIsEqualToProjectCategory() {
    let illustrationProject = Project.template
      |> \.category .~ .illustration

    self.vm.configure(with: (illustrationProject, .illustration, nil))

    self.projectIsStaffPickViewHidden.assertValue(true)
    self.projectCategoryStackViewHidden.assertValue(true)
    self.projectCategoryName.assertValue(KsApi.Category.illustration.name)
    self.projectCategoryViewHidden.assertValue(true)
  }

  func testLocationStackView_IsHidden_ParamsNotNil() {
    let project = Project.template
      |> \.location .~ Location.template

    let params = DiscoveryParams.defaults

    self.vm.configure(with: (project, .illustration, params))

    self.locationStackViewHidden.assertValues([true])
  }

  func testLocationStackView_IsNotHidden_ParamsNil() {
    let project = Project.template
      |> \.location .~ Location.template

    self.vm.configure(with: (project, .illustration, nil))

    self.locationStackViewHidden.assertValues([false])
  }

  func testLocationLabelText() {
    let project = Project.template
      |> \.location .~ Location.template

    self.vm.configure(with: (project, nil, nil))

    self.locationLabelText.assertValues(["Brooklyn"])
  }
}

final class PostcardRecorder<Value> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
}
private extension PostcardRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
  func assertValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    self.assertValues([expected], message, file: file, line: line)
  }
}
