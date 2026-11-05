import Foundation
import GraphAPI

struct PostCommentEnvelope: Decodable {
  let createComment: CreateComment

  struct CreateComment: Decodable {
    let comment: GraphComment
  }
}

extension PostCommentEnvelope {
  static func comment(from data: GraphAPI.PostCommentMutation.Data) throws -> Comment {
    guard let commentFragment = data.createComment?.comment?.fragments.commentFragment,
          let comment = Comment.comment(
            from: commentFragment.fragments.commentBaseFragment,
            replyCount: commentFragment.replies?.totalCount
          ) else {
      throw ErrorEnvelope.couldNotParseJSON
    }

    return comment
  }
}
