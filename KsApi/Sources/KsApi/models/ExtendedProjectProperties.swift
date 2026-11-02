import Foundation
import GraphAPI
/**
 TODO:
 This model is meant to replace `Project` which has almost been converted to use GraphQL properties.

 We're not replacing it completely right now because it has a lot of large dependencies to other models (`Backing`, `User`, `Reward`).

 Also a lot of `/v1/` endpoints still use this model so we cannot completely clean-up/remove/re-think and adjust in-app functionality to address each property's use-cases.

 This property will eventually replace `Project`, but right now we're using it to build out additional functionality that only comes from GraphQL.
 */

public struct ExtendedProjectProperties: Sendable {
  public var environmentalCommitments: [ProjectTabCategoryDescription]
  public var faqs: [ProjectFAQ]
  public var aiDisclosure: ProjectAIDisclosure?
  public var risks: String
  public var story: ProjectStoryElements
  public var minimumPledgeAmount: Int
  public var projectNotice: String?

  public init(
    environmentalCommitments: [ProjectTabCategoryDescription],
    faqs: [ProjectFAQ],
    aiDisclosure: ProjectAIDisclosure?,
    risks: String,
    story: ProjectStoryElements,
    minimumPledgeAmount: Int,
    projectNotice: String?
  ) {
    self.environmentalCommitments = environmentalCommitments
    self.faqs = faqs
    self.aiDisclosure = aiDisclosure
    self.risks = risks
    self.story = story
    self.minimumPledgeAmount = minimumPledgeAmount
    self.projectNotice = projectNotice
  }
}

public struct ProjectAIDisclosure: Sendable {
  public var id: Int
  public var funding: ProjectTabFundingOptions
  public var generationDisclosure: ProjectTabGenerationDisclosure?
  public var involvesAi: Bool
  public var involvesFunding: Bool
  public var involvesGeneration: Bool
  public var involvesOther: Bool
  public var otherAiDetails: ProjectTabCategoryDescription?
}

public struct ProjectFAQ: Sendable {
  public var answer: String
  public var question: String
  public var id: Int
  public var createdAt: TimeInterval?
}

public struct ProjectStoryElements: Sendable {
  public var htmlViewElements: [HTMLViewElement]
  public var richText: [RichTextElement]?

  public init(
    htmlViewElements: [HTMLViewElement],
    richText: RichTextComponentFragment? = nil
  ) {
    self.htmlViewElements = htmlViewElements
    self.richText = richText?.asRichTextElements()
  }
}

public struct ProjectTabCategoryDescription: Sendable {
  public var description: String
  public var category: ProjectTabCategory
  public var id: Int
}

public struct ProjectTabGenerationDisclosure: Equatable, Sendable {
  public var consent: String?
  public var details: String?
}

public struct ProjectTabFundingOptions: Sendable {
  public var fundingForAiAttribution: Bool
  public var fundingForAiConsent: Bool
  public var fundingForAiOption: Bool
}

public enum ProjectTabCategory: String, Sendable {
  case longLastingDesign = "Long-lasting design"
  case sustainableMaterials = "Sustainable materials"
  case environmentallyFriendlyFactories = "Environmentally friendly factories"
  case sustainableDistribution = "Sustainable distribution"
  case reusabilityAndRecyclability = "Reusability and Recyclability"
  case aiDisclosureOtherDetails
  case somethingElse
}

public enum ProjectTabAIFundingCategory: String {
  case consent
  case attribution
  case option
}
