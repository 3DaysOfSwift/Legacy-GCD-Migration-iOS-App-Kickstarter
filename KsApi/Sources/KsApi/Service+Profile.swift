import GraphAPI

extension Service {
  @MainActor public func sessionSetup() async throws -> GraphUserSetup {
    let values = try await self.cancellableQuery(GraphAPI.FetchUserSetupQuery(), map: { data in
      guard let setup = UserEnvelope<GraphUserSetup>.userEnvelope(from: data)?.me else {
        throw ErrorEnvelope.couldNotParseJSON
      }
      return (setup.email, setup.enabledFeatures.map(\.rawValue), setup.ppoHasAction, setup.backingActionCount)
    })
    // Generated feature enums stay on the owning actor; only raw names cross the callback boundary.
    return GraphUserSetup(
      email: values.0, enabledFeatures: Set(values.1.compactMap(ServerFeature.init(rawValue:))),
      ppoHasAction: values.2, backingActionCount: values.3)
  }

  @MainActor public func accountEmailUser() async throws -> GraphUser {
    try await self.cancellableQuery(GraphAPI.FetchUserQuery(withStoredCards: false), map: { data in
      guard let user = UserEnvelope<GraphUser>.userEnvelope(from: data)?.me else {
        throw ErrorEnvelope.couldNotParseJSON
      }
      return user
    })
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
    let _: Void = try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.UpdateUserAccountMutation(input: input),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: { _ in () })
  }

  @MainActor public func saveCurrency(_ input: ChangeCurrencyInput) async throws {
    let _: Void = try await CancellableGraphQLRequest.fetch(start: { completion in
      GraphQL.shared.client.perform(
        mutation: GraphAPI.UpdateUserProfileMutation(input: GraphAPI.UpdateUserProfileInput.from(input)),
        queue: .global(qos: .userInitiated), resultHandler: completion
      )
    }, map: { _ in () })
  }

  @MainActor public func requestEmailVerification() async throws {
    let _: Void = try await CancellableGraphQLRequest
      .fetch(start: { completion in
        GraphQL.shared.client.perform(
          mutation: GraphAPI.UserSendEmailVerificationMutation(input: .init()),
          queue: .global(qos: .userInitiated), resultHandler: completion
        )
      }, map: { _ in () })
  }

  @MainActor public func authenticateApple(input: SignInWithAppleInput) async throws
    -> SignInWithAppleEnvelope {
    try await CancellableGraphQLRequest
      .fetch(start: { completion in
        GraphQL.shared.client.perform(
          mutation: GraphAPI.SignInWithAppleMutation(input: GraphAPI.SignInWithAppleInput.from(input)),
          queue: .global(qos: .userInitiated), resultHandler: completion
        )
      }, map: { data in
        guard let envelope = SignInWithAppleEnvelope.from(data) else { throw ErrorEnvelope.couldNotParseJSON }
        return envelope
      })
  }

  @MainActor public func sessionGraphUser() async throws -> User {
    try await self.cancellableQuery(GraphAPI.FetchUserQuery(withStoredCards: false), map: { data in
      guard let user = UserEnvelope<User>.user(from: data)?.me else {
        throw ErrorEnvelope.couldNotParseJSON
      }
      return user
    })
  }

  @MainActor public func clearActivityIndicator() async throws -> Int {
    try await CancellableGraphQLRequest
      .fetch(start: { completion in
        GraphQL.shared.client.perform(
          mutation: GraphAPI.ClearUserUnseenActivityMutation(input: .init()),
          queue: .global(qos: .userInitiated), resultHandler: completion
        )
      }, map: { data in
        guard let envelope = ClearUserUnseenActivityEnvelope.from(data) else { throw ErrorEnvelope.couldNotParseJSON }
        return envelope.activityIndicatorCount
      })
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
