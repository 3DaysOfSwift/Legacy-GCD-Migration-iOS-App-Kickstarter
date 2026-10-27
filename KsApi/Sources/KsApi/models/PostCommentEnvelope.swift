import Foundation
import GraphAPI
import ReactiveSwift

struct PostCommentEnvelope: Decodable {
  let createComment: CreateComment

  struct CreateComment: Decodable {
    let comment: GraphComment
  }
}

extension PostCommentEnvelope {
  /**
   Return a signal producer containing `Comment` or `ErrorEnvelope`
   */
  static func producer(
    from data: GraphAPI.PostCommentMutation
      .Data
  ) -> SignalProducer<Comment, ErrorEnvelope> {
    do {
      return SignalProducer(value: try self.comment(from: data))
    } catch {
      return SignalProducer(error: .couldNotParseJSON)
    }
  }

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
