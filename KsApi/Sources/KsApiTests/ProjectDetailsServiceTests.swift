import ApolloTestSupport
import GraphAPI
import GraphAPITestMocks
@testable import KsApi
import KsApiTestHelpers
import XCTest

@MainActor
public final class ProjectDetailsServiceTests: XCTestCase {
  func test_projectDetails_fetchesProjectBackingAndRewards() async throws {
    let projectResponseURL = Bundle.module.url(
      forResource: "FetchProjectByParamQuery_Backing",
      withExtension: "json"
    )!

    let backingResponseURL = Bundle.module.url(
      forResource: "FetchBackingQuery",
      withExtension: "json"
    )!

    let rewardsResponseURL = Bundle.module.url(
      forResource: "FetchProjectRewardsByIdQuery",
      withExtension: "json"
    )!

    let fetchProjectResponse: GraphAPI.FetchProjectByParamQuery
      .Data = try! testGraphObject(fromResource: projectResponseURL)
    let fetchBackingResponse: GraphAPI.FetchBackingQuery
      .Data = try! testGraphObject(fromResource: backingResponseURL)
    let fetchRewardsResponse: GraphAPI.FetchProjectRewardsByIdQuery
      .Data = try! testGraphObject(
        fromResource: rewardsResponseURL,
        variables: ["includeShippingRules": true, "includeLocalPickup": true]
      )

    // This mimicks what Service does internally to map the GraphAPI objects to V1 model objects.
    // MockService requires V1 objects, so this is a best effort
    // to duplicate the actual GraphQL mapping behavior.
    let (mappedProject, backingID) = Project.project(from: fetchProjectResponse)
    let projectResult: Result<KsApi.Project.ProjectPamphletData, ErrorEnvelope>? = .success(
      .init(project: try XCTUnwrap(mappedProject), backingId: backingID)
    )
    let backingResult: Result<ProjectAndBackingEnvelope, ErrorEnvelope>? = .success(
      try XCTUnwrap(ProjectAndBackingEnvelope.envelope(from: fetchBackingResponse))
    )
    let rewardsResult: Result<[KsApi.Reward], ErrorEnvelope>? = .success(Project.projectRewards(from: fetchRewardsResponse))

    let mockService = MockService(
      fetchProjectAndBackingResult: backingResult,
      fetchProjectPamphletResult: projectResult,
      fetchProjectRewardsResult: rewardsResult
    )

    let project: KsApi.Project? = try await self.loadProject(using: mockService)

    XCTAssertNotNil(project)
    XCTAssertEqual(project?.personalization.isBacking, true)
    XCTAssertNotNil(project?.personalization.backing)
    XCTAssertEqual(project?.personalization.backing?.amount, 111.0)
    XCTAssertEqual(project?.stats.userCurrency, "EUR")
    XCTAssertEqual(project?.rewardsCount, 4)
    XCTAssertEqual(project?.rewards.count, 5)
    XCTAssertEqual(project?.rewards.first, Reward.noReward)
    XCTAssertNotNil(project?.rewards[1].shippingRulesExpanded)
    XCTAssertEqual(project?.rewards[1].shippingRulesExpanded?.count, 246)
    XCTAssertEqual(project?.rewards[2].shippingRulesExpanded?.count, 1)

    // These properties are only fetched by FetchProjectByParamQuery, but should be passed through.
    XCTAssertEqual(project?.extendedProjectProperties?.aiDisclosure?.involvesAi, false)
    XCTAssertEqual(project?.extendedProjectProperties?.risks, "May not deliver")
    XCTAssertEqual(project?.video?.id, 1_267_784)
    XCTAssertEqual(project?.flagging, true)
  }

  func test_projectDetails_fetchesProjectAndRewards() async throws {
    let projectResponseURL = Bundle.module.url(
      forResource: "FetchProjectByParamQuery_NoBacking",
      withExtension: "json"
    )!

    let rewardsResponseURL = Bundle.module.url(
      forResource: "FetchProjectRewardsByIdQuery",
      withExtension: "json"
    )!

    let fetchProjectResponse: GraphAPI.FetchProjectByParamQuery
      .Data = try! testGraphObject(fromResource: projectResponseURL)
    let fetchRewardsResponse: GraphAPI.FetchProjectRewardsByIdQuery
      .Data = try! testGraphObject(
        fromResource: rewardsResponseURL,
        variables: ["includeShippingRules": true, "includeLocalPickup": true]
      )

    // This mimicks what Service does internally to map the GraphAPI objects to V1 model objects.
    // MockService requires V1 objects, so this is a best effort
    // to duplicate the actual GraphQL mapping behavior.
    let (mappedProject, backingID) = Project.project(from: fetchProjectResponse)
    let projectResult: Result<KsApi.Project.ProjectPamphletData, ErrorEnvelope>? = .success(
      .init(project: try XCTUnwrap(mappedProject), backingId: backingID)
    )
    let rewardsResult: Result<[KsApi.Reward], ErrorEnvelope>? = .success(Project.projectRewards(from: fetchRewardsResponse))

    let mockService = MockService(
      fetchProjectPamphletResult: projectResult,
      fetchProjectRewardsResult: rewardsResult
    )

    let project: KsApi.Project? = try await self.loadProject(using: mockService)

    XCTAssertNotNil(project)
    XCTAssertEqual(project?.personalization.isBacking, false)
    XCTAssertNil(project?.personalization.backing)
    XCTAssertEqual(project?.stats.userCurrency, "EUR")
    XCTAssertEqual(project?.rewardsCount, 4)
    XCTAssertEqual(project?.rewards.count, 5)
    XCTAssertEqual(project?.rewards.first, Reward.noReward)
    XCTAssertNotNil(project?.rewards[1].shippingRulesExpanded)
    XCTAssertEqual(project?.rewards[1].shippingRulesExpanded?.count, 246)
    XCTAssertEqual(project?.rewards[2].shippingRulesExpanded?.count, 1)

    // These properties are only fetched by FetchProjectByParamQuery, but should be passed through to the final project result.
    XCTAssertEqual(project?.extendedProjectProperties?.aiDisclosure?.involvesAi, false)
    XCTAssertEqual(project?.extendedProjectProperties?.risks, "May not deliver")
    XCTAssertEqual(project?.video?.id, 1_267_784)
    XCTAssertEqual(project?.flagging, true)
  }

  func test_fastProjectDetails_returnsAllData() async throws {
    let mockService = MockService(
      fetchGraphQLResponses: [
        (
          GraphAPI.FastFetchProjectPageBaseQuery.self,
          GraphAPI.FastFetchProjectPageBaseQuery.Data.template
        ),
        (
          GraphAPI.FastFetchProjectPageExtendedPropertiesQuery.self,
          GraphAPI.FastFetchProjectPageExtendedPropertiesQuery.Data.template
        )
      ]
    )

    let project = try await self.loadFastProject(using: mockService)

    XCTAssertEqual(project.id, 987)
    XCTAssertEqual(project.name, "The project")

    XCTAssertEqual(project.personalization.isBacking, true)
    XCTAssertNotNil(project.personalization.backing)

    XCTAssertEqual(project.rewards.count, 2)
    XCTAssertEqual(project.rewards.first, Reward.noReward)
    XCTAssertEqual(project.rewards[1].id, 1)

    XCTAssertNotNil(project.video)
    XCTAssertEqual(project.video?.high, "high.mp4")
    XCTAssertNotNil(project.extendedProjectProperties)
    XCTAssertEqual(project.extendedProjectProperties?.risks, "This project has risks.")
    XCTAssertEqual(project.flagging, true)
  }

  func test_fastProjectDetails_returnsErrorIfFirstFetchHasErrors() async throws {
    let mockService = MockService(
      fetchGraphQLResponses: [
        // Intentionally missing the first mock to trigger an error
        (
          GraphAPI.FastFetchProjectPageExtendedPropertiesQuery.self,
          GraphAPI.FastFetchProjectPageExtendedPropertiesQuery.Data.template
        )
      ]
    )

    let errorEnvelope: ErrorEnvelope
    do {
      _ = try await self.loadFastProject(using: mockService)
      XCTFail("Expected error")
      return
    } catch let error as ErrorEnvelope {
      errorEnvelope = error
    }

    XCTAssertEqual(errorEnvelope.errorMessages, ["Unimplemented mock"])
  }

  func test_fastProjectDetails_returnsErrorIfSecondFetchHasErrors() async throws {
    let mockService = MockService(
      fetchGraphQLResponses: [
        (
          GraphAPI.FastFetchProjectPageBaseQuery.self,
          GraphAPI.FastFetchProjectPageBaseQuery.Data.template
        )
        // Intentionally missing the second mock to trigger an error
      ]
    )

    let errorEnvelope: ErrorEnvelope
    do {
      _ = try await self.loadFastProject(using: mockService)
      XCTFail("Expected error")
      return
    } catch let error as ErrorEnvelope {
      errorEnvelope = error
    }

    XCTAssertEqual(errorEnvelope.errorMessages, ["Unimplemented mock"])
  }

  func test_fastProjectDetails_returnsErrorIfBaseParsingFails() async throws {
    let mockService = MockService(
      fetchGraphQLResponses: [
        (
          GraphAPI.FastFetchProjectPageBaseQuery.self,
          // Data that won't parse
          GraphAPI.FastFetchProjectPageBaseQuery.Data.failed
        ),
        (
          GraphAPI.FastFetchProjectPageExtendedPropertiesQuery.self,
          GraphAPI.FastFetchProjectPageExtendedPropertiesQuery.Data.template
        )
      ]
    )

    let errorEnvelope: ErrorEnvelope
    do {
      _ = try await self.loadFastProject(using: mockService)
      XCTFail("Expected error")
      return
    } catch let error as ErrorEnvelope {
      errorEnvelope = error
    }

    XCTAssertEqual(errorEnvelope.ksrCode, .JSONParsingFailed)
  }

  func test_fastProjectDetails_returnsErrorIfExtendedParsingFails() async throws {
    let mockService = MockService(
      fetchGraphQLResponses: [
        (
          GraphAPI.FastFetchProjectPageBaseQuery.self,
          GraphAPI.FastFetchProjectPageBaseQuery.Data.template
        ),
        (
          GraphAPI.FastFetchProjectPageExtendedPropertiesQuery.self,
          // Data that won't parse
          GraphAPI.FastFetchProjectPageExtendedPropertiesQuery.Data.failed
        )
      ]
    )

    let errorEnvelope: ErrorEnvelope
    do {
      _ = try await self.loadFastProject(using: mockService)
      XCTFail("Expected error")
      return
    } catch let error as ErrorEnvelope {
      errorEnvelope = error
    }

    XCTAssertEqual(errorEnvelope.ksrCode, .JSONParsingFailed)
  }
  // Composition is exercised independently in ProjectDetailsFeatureTests.
  private func loadProject(using service: MockService) async throws -> KsApi.Project {
    let data = try await service.projectDetails(param: .id(0), includeStoryRichText: false)
    var project = data.project
    if let backingID = data.backingId {
      let envelope = try await service.projectDetailsBacking(id: backingID)
      project.personalization.backing = envelope.backing
      project.personalization.isBacking = true
    }
    let rewards = try await service.projectDetailsRewards(projectID: project.id)
    project.rewardData.rewards = Array(project.rewardData.rewards.prefix(1)) + rewards
    return project
  }

  private func loadFastProject(using service: MockService) async throws -> KsApi.Project {
    async let base = service.projectDetailsBase(param: .id(0))
    async let extras = service.projectDetailsExtras(param: .id(0), includeStoryRichText: false)
    return try await extras.addExtraProperties(toProject: base)
  }

}

private extension GraphAPI.FastFetchProjectPageExtendedPropertiesQuery.Data {
  static var template: GraphAPI.FastFetchProjectPageExtendedPropertiesQuery.Data {
    let mockExtraProperties = Mock<GraphAPITestMocks.Project>()
    mockExtraProperties.risks = "This project has risks."
    mockExtraProperties.story = "Project story"
    mockExtraProperties.minPledge = 27
    mockExtraProperties.flagging = Mock<GraphAPITestMocks.Flagging>()
    mockExtraProperties.flagging?.id = "fake_id"
    mockExtraProperties.flagging?.kind = .some(.case(.charity))
    mockExtraProperties.video = Mock<GraphAPITestMocks.Video>()
    mockExtraProperties.video?.id = "VmlkZW8tMQ=="
    mockExtraProperties.video?.videoSources = Mock<GraphAPITestMocks.VideoSources>()
    mockExtraProperties.video?.videoSources?.high = Mock<GraphAPITestMocks.VideoSourceInfo>()
    mockExtraProperties.video?.videoSources?.high?.src = "high.mp4"

    let header = Mock<GraphAPITestMocks.RichTextHeader>()
    header.text = "Hello, world"
    mockExtraProperties.storyRichText = Mock<GraphAPITestMocks.RichTextComponent>()
    mockExtraProperties.storyRichText?.items = [
      header
    ]
    mockExtraProperties.isLaunched = true
    mockExtraProperties.prelaunchStoryRichText = Mock<GraphAPITestMocks.RichTextComponent>()
    mockExtraProperties.prelaunchStoryRichText?.items = [
      header
    ]

    return GraphAPI.FastFetchProjectPageExtendedPropertiesQuery.Data(
      project: FastFetchProjectPageExtendedPropertiesQuery.Data.Project.from(mockExtraProperties)
    )
  }

  static var failed: GraphAPI.FastFetchProjectPageExtendedPropertiesQuery.Data {
    return GraphAPI.FastFetchProjectPageExtendedPropertiesQuery.Data(
      project: nil
    )
  }
}

private extension GraphAPI.FastFetchProjectPageBaseQuery.Data {
  static var template: GraphAPI.FastFetchProjectPageBaseQuery.Data {
    let mockProject = GraphAPITestMocks.Project.mock
    mockProject.posts = Mock<GraphAPITestMocks.PostConnection>()
    mockProject.posts?.totalCount = 2

    let mockBacking = GraphAPITestMocks.Backing.mock
    mockProject.backing = mockBacking

    let mockReward = GraphAPITestMocks.Reward.mock
    mockProject.rewards = Mock<GraphAPITestMocks.ProjectRewardConnection>()
    mockProject.rewards?.nodes = [mockReward]

    return GraphAPI.FastFetchProjectPageBaseQuery.Data(
      project: FastFetchProjectPageBaseQuery.Data.Project.from(mockProject)
    )
  }

  static var failed: GraphAPI.FastFetchProjectPageBaseQuery.Data {
    return GraphAPI.FastFetchProjectPageBaseQuery.Data(
      project: nil
    )
  }
}
