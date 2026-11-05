@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

private enum Constants {
  static let communityLink = "https://www.kickstarter.com/help/community"
}

@MainActor
internal final class CommentCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  let vm = CommentCellViewModel()

  private let authorBadge = CommentRecorder<Comment.AuthorBadge>()
  private let authorImageURL = CommentRecorder<URL?>()
  private let authorName = CommentRecorder<String>()
  private let body = CommentRecorder<String>()
  private let bottomRowStackViewIsHidden = CommentRecorder<Bool>()
  private let cellAuthor = CommentRecorder<Comment.Author>()
  private let commentStatus = CommentRecorder<Comment.Status>()
  private let flagButtonIsHidden = CommentRecorder<Bool>()
  private let notifyDelegateLinkTappedWithURL = CommentRecorder<URL>()
  private let postTime = CommentRecorder<String>()
  private let postedButtonIsHidden = CommentRecorder<Bool>()
  private let replyButtonIsHidden = CommentRecorder<Bool>()
  private let replyCommentTapped = CommentRecorder<Comment>()
  private let shouldIndentContent = CommentRecorder<Bool>()
  private let viewCommentReplies = CommentRecorder<Comment>()
  private let viewRepliesStackViewIsHidden = CommentRecorder<Bool>()

  override func setUp() async throws {
    try await super.setUp()
    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .authorBadge(value): self.authorBadge.record(value)
      case let .authorImageURL(value): self.authorImageURL.record(value)
      case let .authorName(value): self.authorName.record(value)
      case let .body(value): self.body.record(value)
      case let .bottomRowStackViewIsHidden(value): self.bottomRowStackViewIsHidden.record(value)
      case let .cellAuthor(value): self.cellAuthor.record(value)
      case let .commentStatus(value): self.commentStatus.record(value)
      case let .flagButtonIsHidden(value): self.flagButtonIsHidden.record(value)
      case let .notifyDelegateLinkTappedWithURL(value): self.notifyDelegateLinkTappedWithURL.record(value)
      case let .postTime(value): self.postTime.record(value)
      case let .postedButtonIsHidden(value): self.postedButtonIsHidden.record(value)
      case let .replyButtonIsHidden(value): self.replyButtonIsHidden.record(value)
      case let .replyCommentTapped(value): self.replyCommentTapped.record(value)
      case let .shouldIndentContent(value): self.shouldIndentContent.record(value)
      case let .viewCommentReplies(value): self.viewCommentReplies.record(value)
      case let .viewRepliesViewHidden(value): self.viewRepliesStackViewIsHidden.record(value)
      }
    }
  }

  func testOutputs() {
    let author = Comment.Author.template
      |> \.imageUrl .~ "http://www.kickstarter.com/small.jpg"

    let comment = Comment.template
      |> \.author .~ author

    let project = Project.template
      |> \.personalization.isBacking .~ true

    self.vm.configureWith(comment: comment, project: project)

    self.authorBadge.assertValues([.creator], "The author's badge is emitted.")
    self.authorImageURL.assertValues([URL(string: "http://www.kickstarter.com/small.jpg")!])
    self.authorName.assertValues([comment.author.name], "The author's name is emitted.")
    self.body.assertValues([comment.body], "The comment body is emitted.")
    self.commentStatus.assertValues([.success], "The comment status is emmited.")
    self.postTime.assertValueCount(1, "The relative time of the comment is emitted.")
  }

  func testOutput_ReplyComment() {
    let comment = Comment.template
    withEnvironment(currentUser: .template) {
      self.vm.configureWith(comment: comment, project: .template)
      self.replyCommentTapped.assertDidNotEmitValue()

      self.vm.replyButtonTapped()

      self.replyCommentTapped
        .assertValue(comment, "The that should be replied to was emmited")
    }
  }

  func testOutput_CellHeaderTapped_EmitsCellAuthor() {
    let comment = Comment.template
    withEnvironment(currentUser: .template) {
      self.vm.configureWith(comment: comment, project: .template)
      self.cellAuthor.assertDidNotEmitValue()

      self.vm.cellHeaderTapped()

      self.cellAuthor
        .assertValue(comment.author)
    }
  }

  func testOutputs_bottomRowStackViewIsHidden_LoggedIn() {
    let user = User.template |> \.id .~ 12_345

    withEnvironment(currentUser: user) {
      self.vm.configureWith(comment: .template, project: .template)

      self.bottomRowStackViewIsHidden
        .assertValue(
          true,
          "The feature flags are false, therefore the stack view is hidden."
        )
    }
  }

  func testOutputs_bottomRowStackViewIsHidden_IsBacking() {
    let project = Project.template
      |> \.personalization.isBacking .~ true

    self.vm.configureWith(comment: .template, project: project)

    self.bottomRowStackViewIsHidden
      .assertValue(
        true,
        "The feature flags are false, therefore the stack view is hidden."
      )
  }

  func testOutput_bottomRowStackViewIsHidden_IsReply() {
    self.vm.configureWith(comment: .replyTemplate, project: .template)

    self.bottomRowStackViewIsHidden
      .assertValue(
        true,
        "The bottom row stack view should be hidden if comment is a reply."
      )
  }

  func testOutput_bottomRowStackViewIsHidden_LoggedOut_IsReplyTrue() {
    withEnvironment(currentUser: nil) {
      self.vm.configureWith(comment: .replyTemplate, project: .template)

      self.bottomRowStackViewIsHidden
        .assertValue(
          true,
          "The bottom row stack view should be hidden if comment is a reply."
        )
    }
  }

  func testOutput_shouldIndentContent_True() {
    self.vm.configureWith(comment: .replyTemplate, project: .template)
    self.vm.bindStyles()
    self.shouldIndentContent.assertValue(true)
  }

  func testOutput_shouldIndentContent_False() {
    self.vm.configureWith(comment: .template, project: .template)
    self.vm.bindStyles()
    self.shouldIndentContent.assertValue(false)
  }

  func testOutputs_flagButtonIsHidden() {
    self.vm.configureWith(comment: .template, project: .template)

    self.flagButtonIsHidden
      .assertValue(true, "The feature flag is not enabled, therefore the flag button is hidden.")
  }

  func testOutput_notifyDelegateLinkTappedWithURL() {
    guard let expectedURL = HelpType.community
      .url(withBaseUrl: AppEnvironment.current.apiService.serverConfig.webBaseUrl) else {
      XCTFail()
      return
    }

    self.vm.configureWith(comment: .template, project: nil)


    self.vm.linkTapped(url: expectedURL)

    self.notifyDelegateLinkTappedWithURL
      .assertValue(expectedURL, "The URL directs to Kickstarters Community Guidelines.")
  }

  func testOutputs_replyButtonIsHidden_IsBacker_False_IsLoggedOut() {
    withEnvironment(currentUser: nil) {
      self.vm.configureWith(comment: .template, project: .template)

      self.replyButtonIsHidden
        .assertValue(true, "The replyButton is hidden because the user is not a backer AND not logged in.")
    }
  }

  func testOutputs_replyButtonIsHidden_IsBacker_False_IsLoggedIn() {
    let user = User.template |> \.id .~ 12_345

    withEnvironment(currentUser: user) {
      self.vm.configureWith(comment: .template, project: .template)

      self.replyButtonIsHidden
        .assertValue(true, "The replyButton is hidden because the user is logged in but not a backer.")
    }
  }

  func testOutputs_replyButtonIsHidden_IsNotBacker_IsNotCreatorOrCollaborator_False() {
    let user = User.template |> \.id .~ 12_345

    let project = Project.template
      |> \.memberData.permissions .~ [.post, .comment]

    withEnvironment(currentUser: user) {
      self.vm.configureWith(comment: .template, project: project)

      self.replyButtonIsHidden
        .assertValue(false, "The replyButton is not hidden because the user is a creator collaborator.")
    }
  }

  func testOutputs_replyButtonIsHidden_IsNotBacker_IsNotCreatorOrCollaborator_True() {
    let user = User.template |> \.id .~ 12_345

    withEnvironment(currentUser: user) {
      self.vm.configureWith(comment: .template, project: .template)

      self.replyButtonIsHidden
        .assertValue(
          true,
          "The replyButton is hidden because the user is not backing, and not a creator or collaborator."
        )
    }
  }

  func testOutputs_replyButtonIsHidden_viewRepliesStackViewIsHidden_IsBacker_True_IsLoggedIn() {
    let project = Project.template
      |> \.personalization.isBacking .~ true

    let user = User.template |> \.id .~ 12_345

    withEnvironment(currentUser: user) {
      self.vm.configureWith(comment: .template, project: project)

      self.replyButtonIsHidden
        .assertValue(false, "The replyButton is not hidden.")
    }
    self.viewRepliesStackViewIsHidden
      .assertValue(false, "The stack view is not hidden.")
  }

  func testOutputs_replyButtonIsHidden_viewRepliesStackViewIsHidden_IsBacker_False_IsLoggedIn() {
    let user = User.template |> \.id .~ 12_345

    withEnvironment(currentUser: user) {
      self.vm.configureWith(comment: .template, project: .template)

      self.replyButtonIsHidden
        .assertValue(true, "The replyButton is hidden because the user is not a backer.")
    }
    self.viewRepliesStackViewIsHidden
      .assertValue(
        false,
        "The stack view is not hidden when there are replies on the comment."
      )
  }

  func testOutputs_UserIs_LoggedOut() {
    let author = Comment.Author.template
      |> \.imageUrl .~ "http://www.kickstarter.com/small.jpg"

    let comment = Comment.template
      |> \.author .~ author

    self.vm.configureWith(comment: comment, project: .template)

    self.authorBadge.assertValues([.creator], "The author's badge is emitted.")
    self.authorImageURL.assertValues([URL(string: "http://www.kickstarter.com/small.jpg")!])
    self.authorName.assertValues([comment.author.name], "The author's name is emitted.")
    self.body.assertValues([comment.body], "The comment body is emitted.")
    self.postTime.assertValueCount(1, "The relative time of the comment is emitted.")
    self.replyButtonIsHidden.assertValue(true, "User is not logged in.")
  }

  func testOutput_ViewCommentReplies() {
    let comment = Comment.template
    withEnvironment(currentUser: .template) {
      self.vm.configureWith(comment: comment, project: .template)
      self.viewCommentReplies.assertDidNotEmitValue()

      self.vm.viewRepliesButtonTapped()

      self.viewCommentReplies
        .assertValue(comment, "A Comment was emitted after the view replies button was tapped.")
    }
  }

  func testOutputs_When_Flag_RemovedPerGuidelines() {
    let comment = Comment.template
      |> \.removedPerGuidelines .~ true

    self.vm.configureWith(comment: comment, project: .template)

    let commentHasBeenRemovedString = Strings
      .This_comment_has_been_removed_for_violating_kickstarters_community_guidelines(
        community_guidelines: "https://www.kickstarter.com/help/community"
      )
    self.body
      .assertLastValue(commentHasBeenRemovedString)
  }

  func testOutputs_When_Flag_IsDeleted() {
    let comment = Comment.template
      |> \.isDeleted .~ true

    self.vm.configureWith(comment: comment, project: .template)

    let body = Strings.This_comment_has_been_removed_by_Kickstarter() + " " + Strings
      .Learn_more_about_comment_guidelines(community_link: Constants.communityLink)
    self.body.assertLastValue(body)
  }

  func testOutputs_When_Flag_HasFlagging() {
    let comment = Comment.template
      |> \.hasFlaggings .~ true
      |> \.sustained .~ false

    self.vm.configureWith(comment: comment, project: .template)

    let body = Strings
      .This_comment_is_under_review_for_potentially_violating_kickstarters_community_guidelines(
        community_guidelines: Constants.communityLink
      )

    self.body.assertLastValue(body)
  }

  func testOutputs_When_Flag_HasFlagging_And_Sustained() {
    let comment = Comment.template
      |> \.hasFlaggings .~ true
      |> \.sustained .~ true

    self.vm.configureWith(comment: comment, project: .template)

    self.body.assertLastValue(comment.body)
  }

  func testPersonalizedLabels_UserIs_Creator_Author() {
    let comment = Comment.template

    self.vm.configureWith(comment: comment, project: .template)
    self.authorBadge.assertValues([.creator], "The author's badge is emitted.")
  }

  func testPersonalizedLabels_User_Is_You_Author() {
    let author = Comment.Author.template
      |> \.id .~ "12345"

    let comment = Comment.template
      |> \.author .~ author
      |> \.authorBadges .~ [.superbacker]

    let user = User.template |> \.id .~ 12_345

    withEnvironment(currentUser: user) {
      self.vm.configureWith(comment: comment, project: .template)
      self.authorBadge.assertValues([.you], "The author's badge is emitted.")
    }
  }

  func testPersonalizedLabels_UserIs_Superbacker_Author() {
    let comment = Comment.superbackerTemplate

    self.vm.configureWith(comment: comment, project: .template)
    self.authorBadge.assertValues([.superbacker], "The author's badge is emitted.")
  }

  func testPersonalizedLabels_UserIs_Backer_Author() {
    let comment = Comment.backerTemplate

    self.vm.configureWith(comment: comment, project: .template)
    self.authorBadge.assertValues([.backer], "The author's badge is emitted.")
  }

  func testReusingCellReplacesBlockedAuthorAndReplyVisibility() {
    let backingProject = Project.template |> \.personalization.isBacking .~ true
    withEnvironment(currentUser: .template) {
      self.vm.configureWith(comment: .blockedTemplate, project: .template)
      self.vm.configureWith(comment: .template, project: backingProject)
      self.authorName.assertLastValue(Comment.template.author.name)
      self.body.assertLastValue(Comment.template.body)
      self.replyButtonIsHidden.assertLastValue(false)
      self.bottomRowStackViewIsHidden.assertLastValue(false)
    }
  }

  func testBlockedAuthor() {
    let comment = Comment.blockedTemplate

    self.vm.configureWith(comment: comment, project: .template)
    self.authorBadge.assertValues([.backer], "The default badge is emitted.")
    self.authorName.assertValue(Strings.Blocked_user(), "The author's name is hidden.")
    self.authorImageURL.assertValue(nil, "The author's avatar is hidden.")
    self.body.assertValue(Strings.This_user_has_been_blocked(), "The comment text is hidden.")
  }

  func testBindStylesEmitsAuthorBadge() {
    self.authorBadge.assertDidNotEmitValue()

    self.vm.configureWith(comment: .template, project: .template)

    self.authorBadge.assertValues([.creator], "The author's badge is emitted.")

    self.vm.bindStyles()

    self.authorBadge.assertValues([.creator, .creator], "The author's badge is emitted.")
  }

  func testBindStylesEmitsCommentStatus() {
    self.commentStatus.assertDidNotEmitValue()

    let comment = Comment.template
      |> \.status .~ .retrying

    self.vm.configureWith(comment: comment, project: .template)

    self.commentStatus.assertValues([.retrying], "The comment status is emitted.")
    self.postedButtonIsHidden.assertValues([true], "The posted button hiddent state is emitted.")

    self.vm.bindStyles()

    self.commentStatus.assertValues([.retrying, .retrying], "The comment status is emitted.")
    self.postedButtonIsHidden.assertValues([true, true], "The posted button hiddent state is emitted.")
  }

  func testPostedButtonIsHidden_NotHiddenWhenCommentStatus_IsRetrySuccess() {
    let comment = Comment.template
      |> \.status .~ .retrySuccess

    self.vm.configureWith(comment: comment, project: .template)

    self.commentStatus.assertValues([.retrySuccess], "The comment status is emitted.")
    self.postedButtonIsHidden.assertValues([false], "The posted button hiddent state is emitted.")

    self.vm.bindStyles()

    self.commentStatus.assertValues([.retrySuccess, .retrySuccess], "The comment status is emitted.")
    self.postedButtonIsHidden.assertValues([false, false], "The posted button hiddent state is emitted.")
  }

  func testViewRepliesContainerHidden_IsHiddenWhenNoReplies() {
    self.viewRepliesStackViewIsHidden.assertDidNotEmitValue()

    let comment = Comment.template
      |> \.replyCount .~ 0

    self.vm.configureWith(comment: comment, project: .template)

    self.viewRepliesStackViewIsHidden.assertValues([true])
  }

  func testViewRepliesContainerHidden_IsHiddenWhenCommentHasReplies_False() {
    let comment = Comment.template
      |> \.replyCount .~ 1

    self.viewRepliesStackViewIsHidden.assertDidNotEmitValue()

    self.vm.configureWith(comment: comment, project: .template)

    self.viewRepliesStackViewIsHidden
      .assertValue(false, "The stack view is not hidden because there are replies.")
  }
}

private final class CommentRecorder<Value> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(file: StaticString = #filePath, line: UInt = #line) {
    self.assertValueCount(0, file: file, line: line)
  }
}
private extension CommentRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
  func assertValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    self.assertValues([expected], message, file: file, line: line)
  }
  func assertLastValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.last, expected, message, file: file, line: line)
  }
}
