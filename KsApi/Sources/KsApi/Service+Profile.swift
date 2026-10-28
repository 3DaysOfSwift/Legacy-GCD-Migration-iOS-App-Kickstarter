import GraphAPI

extension Service {
  @MainActor public func sessionSetup() async throws -> GraphUserSetup {
    let data = try await self.cancellableQuery(GraphAPI.FetchUserSetupQuery())
    guard let setup = UserEnvelope<GraphUserSetup>.userEnvelope(from: data)?.me else {
      throw ErrorEnvelope.couldNotParseJSON
    }
    return setup
  }

  @MainActor public func accountEmailUser() async throws -> GraphUser {
    let data = try await self.cancellableQuery(GraphAPI.FetchUserQuery(withStoredCards: false))
    guard let user = UserEnvelope<GraphUser>.userEnvelope(from: data)?.me else {
      throw ErrorEnvelope.couldNotParseJSON
    }
    return user
  }

  @MainActor public func saveEmail(_ input: ChangeEmailInput) async throws {
    try await self.updateAccount(GraphAPI.UpdateUserAccountInput.from(input))
  }

  @MainActor public func savePassword(_ input: ChangePasswordInput) async throws {
    try await self.updateAccount(GraphAPI.UpdateUserAccountInput.from(input))
  }

  @MainActor public func setInitialPassword(_ input: CreatePasswordInput) async throws {
    try await self.updateAccount(GraphAPI.UpdateUserAccountInput.from(input))
  }

  @MainActor private func updateAccount(_ input: GraphAPI.UpdateUserAccountInput) async throws {
    let _: GraphAPI.UpdateUserAccountMutation.Data = try await CancellableGraphQLRequest.fetch { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.UpdateUserAccountMutation(input: input),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }
  }

  @MainActor public func saveCurrency(_ input: ChangeCurrencyInput) async throws {
    let _: GraphAPI.UpdateUserProfileMutation.Data = try await CancellableGraphQLRequest.fetch { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.UpdateUserProfileMutation(input: GraphAPI.UpdateUserProfileInput.from(input)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }
  }

  @MainActor public func requestEmailVerification() async throws {
    let _: GraphAPI.UserSendEmailVerificationMutation.Data = try await CancellableGraphQLRequest
      .fetch { completion in
        GraphQL.shared.client.perform(
          mutation: GraphAPI.UserSendEmailVerificationMutation(input: .init()),
          queue: .global(qos: .userInitiated), resultHandler: completion
        )
      }
  }

  @MainActor public func authenticateApple(input: SignInWithAppleInput) async throws
    -> SignInWithAppleEnvelope {
    let data: GraphAPI.SignInWithAppleMutation.Data = try await CancellableGraphQLRequest
      .fetch { completion in
        GraphQL.shared.client.perform(
          mutation: GraphAPI.SignInWithAppleMutation(input: GraphAPI.SignInWithAppleInput.from(input)),
          queue: .global(qos: .userInitiated), resultHandler: completion
        )
      }
    guard let envelope = SignInWithAppleEnvelope.from(data) else { throw ErrorEnvelope.couldNotParseJSON }
    return envelope
  }

  @MainActor public func sessionGraphUser() async throws -> User {
    let data = try await self.cancellableQuery(GraphAPI.FetchUserQuery(withStoredCards: false))
    guard let user = UserEnvelope<User>.user(from: data)?.me else {
      throw ErrorEnvelope.couldNotParseJSON
    }
    return user
  }

  @MainActor public func clearActivityIndicator() async throws -> Int {
    let data: GraphAPI.ClearUserUnseenActivityMutation.Data = try await CancellableGraphQLRequest
      .fetch { completion in
        GraphQL.shared.client.perform(
          mutation: GraphAPI.ClearUserUnseenActivityMutation(input: .init()),
          queue: .global(qos: .userInitiated), resultHandler: completion
        )
      }
    guard let envelope = ClearUserUnseenActivityEnvelope.from(data) else {
      throw ErrorEnvelope.couldNotParseJSON
    }
    return envelope.activityIndicatorCount
  }

  @MainActor public func profileBackedProjects(cursor: String?) async throws -> GraphAPI
    .FetchMyBackedProjectsQuery.Data {
    try await self.cancellableQuery(GraphAPI.FetchMyBackedProjectsQuery(first: 20, after: .someOrNil(cursor)))
  }

  @MainActor public func profileSavedProjects(cursor: String?) async throws -> GraphAPI
    .FetchMySavedProjectsQuery.Data {
    try await self.cancellableQuery(GraphAPI.FetchMySavedProjectsQuery(first: 20, after: .someOrNil(cursor)))
  }
}
