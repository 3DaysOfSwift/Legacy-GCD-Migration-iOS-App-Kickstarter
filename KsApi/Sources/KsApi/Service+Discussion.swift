import GraphAPI

/// Legacy discussion adapters complete without a page when GraphQL has no
/// decodable envelope. Keep this distinct from a valid empty page or API error.
public enum DiscussionResponseError: Error {
  case missingEnvelope
}

extension Service {
  @MainActor public func submitDiscussionComment(input: PostCommentInput) async throws -> Comment {
    let data: GraphAPI.PostCommentMutation.Data = try await CancellableGraphQLRequest.fetch { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.PostCommentMutation(input: GraphAPI.PostCommentInput.from(input)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }
    return try PostCommentEnvelope.comment(from: data)
  }

  @MainActor public func blockDiscussionUser(id: String) async throws -> EmptyResponseEnvelope {
    let _: GraphAPI.BlockUserMutation.Data = try await CancellableGraphQLRequest.fetch { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.BlockUserMutation(input: GraphAPI.BlockUserInput(blockUserId: id)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }
    return EmptyResponseEnvelope()
  }

  @MainActor public func discussionComments(
    slug: String?, updateID: String?, cursor: String?
  ) async throws -> CommentsEnvelope {
    let envelope: CommentsEnvelope?
    if let slug {
      let data = try await self.cancellableQuery(GraphAPI.FetchProjectCommentsQuery(
        slug: slug, cursor: .someOrNil(cursor), limit: nil
      ))
      envelope = CommentsEnvelope.commentsEnvelope(from: data)
    } else if let updateID {
      let data = try await self.cancellableQuery(GraphAPI.FetchUpdateCommentsQuery(
        postId: updateID, cursor: .someOrNil(cursor), limit: nil
      ))
      envelope = CommentsEnvelope.commentsEnvelope(from: data)
    } else {
      throw ErrorEnvelope.couldNotParseJSON
    }
    guard let envelope else { throw DiscussionResponseError.missingEnvelope }
    return envelope
  }

  @MainActor public func discussionReplies(
    id: String,
    cursor: String?
  ) async throws -> CommentRepliesEnvelope {
    let data = try await self.cancellableQuery(GraphAPI.FetchCommentRepliesQuery(
      commentId: id, cursor: .someOrNil(cursor), limit: CommentRepliesEnvelope.paginationLimit
    ))
    guard let envelope = CommentRepliesEnvelope.commentRepliesEnvelope(from: data)
    else { throw DiscussionResponseError.missingEnvelope }
    return envelope
  }
}
