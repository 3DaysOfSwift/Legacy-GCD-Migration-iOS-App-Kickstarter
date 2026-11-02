import GraphAPI

/// Legacy discussion adapters complete without a page when GraphQL has no
/// decodable envelope. Keep this distinct from a valid empty page or API error.
public enum DiscussionResponseError: Error {
  case missingEnvelope
}

extension Service {
  @MainActor public func submitDiscussionComment(input: PostCommentInput) async throws -> Comment {
    return try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.PostCommentMutation(input: GraphAPI.PostCommentInput.from(input)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: { try PostCommentEnvelope.comment(from: $0) })
  }

  @MainActor public func blockDiscussionUser(id: String) async throws -> EmptyResponseEnvelope {
    let _: Void = try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.BlockUserMutation(input: GraphAPI.BlockUserInput(blockUserId: id)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: { _ in () })
    return EmptyResponseEnvelope()
  }

  @MainActor public func discussionComments(
    slug: String?, updateID: String?, cursor: String?
  ) async throws -> CommentsEnvelope {
    let envelope: CommentsEnvelope?
    if let slug {
      envelope = try await self.cancellableQuery(GraphAPI.FetchProjectCommentsQuery(
        slug: slug, cursor: .someOrNil(cursor), limit: nil
      ), map: { CommentsEnvelope.commentsEnvelope(from: $0) })
    } else if let updateID {
      envelope = try await self.cancellableQuery(GraphAPI.FetchUpdateCommentsQuery(
        postId: updateID, cursor: .someOrNil(cursor), limit: nil
      ), map: { CommentsEnvelope.commentsEnvelope(from: $0) })
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
    let envelope = try await self.cancellableQuery(GraphAPI.FetchCommentRepliesQuery(
      commentId: id, cursor: .someOrNil(cursor), limit: CommentRepliesEnvelope.paginationLimit
    ), map: { CommentRepliesEnvelope.commentRepliesEnvelope(from: $0) })
    guard let envelope
    else { throw DiscussionResponseError.missingEnvelope }
    return envelope
  }
}
