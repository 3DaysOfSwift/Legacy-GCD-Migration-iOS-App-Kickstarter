#if DEBUG
import Foundation
import GraphAPI
import Prelude

/// Owns the immutable, fictional catalogue used only by the opt-in public demo.
/// Both REST-shaped and GraphQL-shaped responses come from these same projects.
internal struct DemoCatalog {
  let projects: [Project]
  static let pageSize = 6
  static let locations: [Location] = [.brooklyn, .losAngeles, .portland]

  init(referenceDate: Foundation.Date = Foundation.Date()) {
    let concepts = [
      ("Pocket Observatory", "A tabletop guide to the night sky.", "Mira Studio"),
      ("Forest Trails", "A cooperative woodland board game.", "Cedar Games"),
      ("Paper Cities", "An illustrated atlas of imaginary neighbourhoods.", "Paper Lantern"),
      ("Solar Sketchbook", "A field journal for curious outdoor explorers.", "Daylight Workshop"),
      ("Ocean Stories", "A documentary about coastal communities.", "Blue Harbour Films"),
      ("Tiny Garden", "A modular planter for small city balconies.", "Sprout Collective"),
      ("Moonlight Cards", "An illustrated deck for evenings with friends.", "Lunar Press"),
      ("Neighbourhood Sounds", "A collection of original community recordings.", "Open Window")
    ]
    let categories: [Project.Category] = [.art, .games, .filmAndVideo]
    // Capture once per catalogue so pagination stays stable. Tests inject a fixed clock value.
    let referenceTime = referenceDate.timeIntervalSince1970
    projects = (0..<24).map { index in
      let concept = concepts[index % concepts.count]
      var project = Project.template
      project.id = 900_001 + index
      project.slug = "demo-project-\(project.id)"
      project.name = "[Demo] \(concept.0) — Edition \(index / concepts.count + 1)"
      project.blurb = "Fictional demonstration project. \(concept.1)"
      project.creator.id = 910_001 + index
      project.creator.name = "\(concept.2) (Demo)"
      let illustration = "https://images.demo.invalid/project/\(index % concepts.count).png"
      project.photo = Project.Photo(full: illustration, med: illustration,
        size1024x768: illustration, small: illustration)
      let avatar = "https://images.demo.invalid/avatar/\(index % concepts.count).png"
      project.creator.avatar = User.Avatar(large: avatar, medium: avatar, small: avatar)
      project.category = categories[index % categories.count]
      project.location = Self.locations[index % Self.locations.count]
      project.stats.goal = [800, 5_000, 25_000, 150_000][index % 4]
      let fundingPercent = index % 4 == 2 ? 120 : [50, 75, 120, 150][index % 4]
      project.stats.pledged = project.stats.goal * fundingPercent / 100
      project.stats.backersCount = 20 + index * 17
      project.stats.projectCurrency = "USD"
      project.stats.userCurrency = "USD"
      project.stats.staticUsdRate = 1
      project.stats.usdExchangeRate = 1
      project.stats.userCurrencyRate = 1
      project.stats.convertedPledgedAmount = Float(project.stats.pledged)
      project.stats.updatesCount = 0
      project.state = index % 4 == 2 ? .successful : .live
      project.dates.launchedAt = referenceTime - Double(index + 7) * 86_400
      project.dates.deadline = referenceTime + Double(index + 2) * 86_400
      if project.state == .successful { project.dates.deadline = referenceTime - 3 * 86_400 }
      project.dates.stateChangedAt = project.state == .successful
        ? referenceTime - 3 * 86_400 : referenceTime - Double(index + 7) * 86_400
      project.staffPick = index.isMultiple(of: 2)
      project.personalization.isStarred = false
      project.personalization.isBacking = false
      project.personalization.backing = nil
      project.video = nil
      project.tags = []
      project.displayPrelaunch = false
      project.prelaunchActivated = false
      project.urls.web.project = "https://example.invalid/projects/\(project.slug)"
      project.urls.web.updates = "https://example.invalid/projects/\(project.slug)/posts"
      project.redemptionPageUrl = ""
      let reward = Reward.template
        |> Reward.lens.id .~ (920_001 + index)
        |> Reward.lens.title .~ "Demo supporter edition"
        |> Reward.lens.description .~ "Illustrative reward only. No payment or delivery takes place."
        |> Reward.lens.minimum .~ 25
        |> Reward.lens.pledgeAmount .~ 25
        |> Reward.lens.convertedMinimum .~ 25
        |> Reward.lens.limit .~ nil
        |> Reward.lens.remaining .~ nil
        |> Reward.lens.estimatedDeliveryOn .~ (referenceTime + 90 * 86_400)
        |> Reward.lens.rewardsItems .~ []
      project.rewardData.rewards = [reward]
      return project
    }
  }

  var categories: RootCategoriesEnvelope {
    let roots: [Project.Category] = [.art, .games, .filmAndVideo]
    return RootCategoriesEnvelope(rootCategories: roots.map { category in
      Category(analyticsName: category.name, id: graphID("Category", category.id), name: category.name)
    })
  }

  func project(_ param: Param) throws -> Project {
    guard let project = projects.first(where: { $0.id == param.id || $0.slug == param.slug }) else {
      throw ErrorEnvelope.graphError("Demo project not found")
    }
    return project
  }

  func extraProperties(_ param: Param) throws -> ProjectPageExtraProperties {
    let project = try project(param)
    return ProjectPageExtraProperties(
      extendedProjectProperties: ExtendedProjectProperties(
        environmentalCommitments: [],
        faqs: [ProjectFAQ(answer: "No. This is fictional data for development.",
                          question: "Is this a real campaign?", id: project.id)],
        aiDisclosure: nil,
        risks: "Demonstration only. No money is collected and no rewards are delivered.",
        story: ProjectStoryElements(htmlViewElements: [TextViewElement(components: [
          TextComponent(text: project.blurb, link: nil, styles: []),
          TextComponent(text: "Explore this fictional campaign to test navigation, search and filtering. No real funding is accepted.", link: nil, styles: [])
        ])]),
        minimumPledgeAmount: 1,
        projectNotice: project.blurb
      ), video: nil, flagging: false
    )
  }

  func search(_ query: GraphAPI.SearchQuery) throws -> GraphAPI.SearchQuery.Data {
    if query.term.unwrapped == "demo:error" {
      throw ErrorEnvelope.graphError("Simulated demo search failure. Change the search to retry.")
    }
    let term = (query.term.unwrapped ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = projects.filter { project in
      let text = "\(project.name) \(project.blurb) \(project.creator.name)"
      guard term.isEmpty || text.localizedCaseInsensitiveContains(term) else { return false }
      if let categoryID = query.categoryId.unwrapped,
         categoryID != project.category?.id.description,
         categoryID != project.category.map({ graphID("Category", $0.id) }) { return false }
      if let locationID = query.locationId.unwrapped,
         locationID != project.location.map({ graphID("Location", $0.id) }) { return false }
      if let state = query.state.unwrapped?.value {
        if state == .live && project.state != .live { return false }
        if state == .successful && project.state != .successful { return false }
        if state == .upcoming || state == .latePledge { return false }
      }
      // The demo starts signed out, with no saved/followed/personalised results.
      if query.showSavedProjects.unwrapped == true || query.showFollowing.unwrapped == true
        || query.showRecommended.unwrapped == true { return false }
      if query.showProjectsWeLove.unwrapped == true && !project.staffPick { return false }
      if let raised = query.raised.unwrapped?.value {
        let percent = project.stats.percentFunded
        switch raised {
        case .bucket0: if percent >= 75 { return false }
        case .bucket1: if percent < 75 || percent >= 100 { return false }
        case .bucket2: if percent < 100 { return false }
        }
      }
      if let goal = query.goal.unwrapped?.rawValue,
         goal != moneyBucket(project.stats.goal) { return false }
      if let pledged = query.pledged.unwrapped?.rawValue,
         pledged != moneyBucket(project.stats.pledged) { return false }
      return true
    }
    let sorted = matches.sorted { left, right in
      switch query.sort.unwrapped?.value {
      case .endDate: return left.dates.deadline == right.dates.deadline
        ? left.id < right.id : (left.dates.deadline ?? .greatestFiniteMagnitude) < (right.dates.deadline ?? .greatestFiniteMagnitude)
      case .newest: return left.dates.launchedAt == right.dates.launchedAt
        ? left.id < right.id : (left.dates.launchedAt ?? 0) > (right.dates.launchedAt ?? 0)
      case .mostFunded: return left.stats.pledged == right.stats.pledged
        ? left.id < right.id : left.stats.pledged > right.stats.pledged
      case .mostBacked, .popularity: return left.stats.backersCount == right.stats.backersCount
        ? left.id < right.id : left.stats.backersCount > right.stats.backersCount
      default: return left.id < right.id
      }
    }
    let offset: Int
    if let cursor = query.cursor.unwrapped {
      guard let parsed = Int(cursor), (0...sorted.count).contains(parsed) else {
        throw ErrorEnvelope.graphError("Invalid demo pagination cursor")
      }
      offset = parsed
    } else { offset = 0 }
    let count = min(max(query.first.unwrapped ?? Self.pageSize, 1), Self.pageSize)
    let end = min(offset + count, sorted.count)
    let nodes = sorted[offset..<end].map(searchNode)
    return .init(projects: .init(nodes: nodes, totalCount: sorted.count,
      pageInfo: .init(endCursor: end < sorted.count ? String(end) : nil, hasNextPage: end < sorted.count)))
  }

  func discovery(_ params: DiscoveryParams) throws -> DiscoveryEnvelope {
    let page = max(params.page ?? 1, 1)
    guard page <= projects.count + 1 else { throw ErrorEnvelope.graphError("Invalid demo page") }
    let query = GraphAPI.SearchQuery(
      term: .someOrNil(params.query), sort: .none,
      categoryId: .someOrNil(params.category?.id), state: .none, raised: .none,
      locationId: .someOrNil(params.location?.graphID), pledged: .none, goal: .none,
      showRecommended: .someOrNil(params.recommended), showSavedProjects: .someOrNil(params.starred),
      showProjectsWeLove: .someOrNil(params.staffPicks), showFollowing: .someOrNil(params.social),
      first: .some(Self.pageSize), cursor: page == 1 ? .none : .some(String((page - 1) * Self.pageSize)))
    switch params.sort {
    case .endingSoon: query.sort = .some(.case(.endDate))
    case .newest: query.sort = .some(.case(.newest))
    case .most_funded: query.sort = .some(.case(.mostFunded))
    case .most_backed: query.sort = .some(.case(.mostBacked))
    case .popular: query.sort = .some(.case(.popularity))
    default: break
    }
    if let state = params.state, state != .all {
      query.state = .some(GraphQLEnum(rawValue: state.rawValue.uppercased()))
    }
    if let raised = params.percentRaised { query.raised = .some(GraphQLEnum(rawValue: "BUCKET_\(raised.rawValue)")) }
    if let pledged = params.amountRaised { query.pledged = .some(GraphQLEnum(rawValue: "BUCKET_\(pledged.rawValue)")) }
    if let goal = params.goal { query.goal = .some(GraphQLEnum(rawValue: "BUCKET_\(goal.rawValue)")) }
    let response = try search(query)
    let nodes = response.projects?.nodes?.compactMap { $0 } ?? []
    let pageProjects = try nodes.map { try project(.id($0.pid)) }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "example.invalid"
    components.path = "/demo/discovery"
    var nextParams = params
    nextParams.page = page + 1
    components.queryItems = nextParams.queryParams.sorted { $0.key < $1.key }
      .map { URLQueryItem(name: $0.key, value: $0.value) }
    components.queryItems?.append(contentsOf: [
      URLQueryItem(name: "demo_location", value: params.location?.id.description),
      URLQueryItem(name: "demo_raised", value: params.percentRaised?.rawValue.description),
      URLQueryItem(name: "demo_pledged", value: params.amountRaised?.rawValue.description),
      URLQueryItem(name: "demo_goal", value: params.goal?.rawValue.description)
    ].filter { $0.value != nil })
    let nextURL = response.projects?.pageInfo.hasNextPage == true ? (components.string ?? "") : ""
    return DiscoveryEnvelope(projects: pageProjects, urls: .init(api: .init(moreProjects: nextURL)),
                             stats: .init(count: response.projects?.totalCount ?? 0))
  }

  func discovery(paginationURL: String) throws -> DiscoveryEnvelope {
    // The legacy paginator stops on an empty page, not an empty String cursor.
    if paginationURL.isEmpty {
      return DiscoveryEnvelope(projects: [], urls: .init(api: .init(moreProjects: "")), stats: .init(count: 0))
    }
    guard let components = URLComponents(string: paginationURL), components.host == "example.invalid",
          components.path == "/demo/discovery" else {
      throw ErrorEnvelope.graphError("Invalid demo pagination URL")
    }
    let items = components.queryItems ?? []
    func value(_ key: String) -> String? { items.first { $0.name == key }?.value }
    var params = DiscoveryParams.defaults
    params.page = value("page").flatMap(Int.init)
    params.query = value("term")
    params.sort = value("sort").flatMap(DiscoveryParams.Sort.init(rawValue:))
    params.category = categories.rootCategories.first { $0.intID?.description == value("category_id") }
    params.location = Self.locations.first { $0.id.description == value("demo_location") }
    params.state = value("state").flatMap(DiscoveryParams.State.init(rawValue:))
    params.percentRaised = value("demo_raised").flatMap(Int.init).flatMap(DiscoveryParams.PercentRaisedBucket.init(rawValue:))
    params.amountRaised = value("demo_pledged").flatMap(Int.init).flatMap(DiscoveryParams.AmountRaisedBucket.init(rawValue:))
    params.goal = value("demo_goal").flatMap(Int.init).flatMap(DiscoveryParams.GoalBucket.init(rawValue:))
    params.staffPicks = value("staff_picks").flatMap(Bool.init)
    params.starred = value("starred").flatMap(Bool.init)
    params.recommended = value("recommended").flatMap(Bool.init)
    params.social = value("social") == "1"
    return try discovery(params)
  }

  func graphResponse<Q: GraphQLQuery>(for query: Q) throws -> Q.Data {
    let response: any GraphAPI.SelectionSet
    switch query {
    case let searchQuery as GraphAPI.SearchQuery: response = try search(searchQuery)
    case is GraphAPI.DefaultLocationsQuery:
      response = GraphAPI.DefaultLocationsQuery.Data(locations: .init(nodes: Self.locations.map {
        .init(country: $0.country, displayableName: $0.displayableName,
              id: graphID("Location", $0.id), name: $0.name)
      }))
    case let locationsQuery as GraphAPI.LocationsByTermQuery:
      let term = locationsQuery.term.unwrapped ?? ""
      response = GraphAPI.LocationsByTermQuery.Data(locations: .init(nodes: Self.locations.filter {
        term.isEmpty || $0.displayableName.localizedCaseInsensitiveContains(term)
      }.map {
        .init(country: $0.country, displayableName: $0.displayableName,
              id: graphID("Location", $0.id), name: $0.name)
      }))
    default: throw ErrorEnvelope.graphError("This operation is not available in the public demo")
    }
    guard let typedResponse = response as? Q.Data else { throw ErrorEnvelope.couldNotParseJSON }
    return typedResponse
  }

  private func searchNode(_ project: Project) -> GraphAPI.SearchQuery.Data.Projects.Node {
    .init(projectId: graphID("Project", project.id), name: project.name,
      projectState: .case(project.state == .successful ? .successful : .live),
      image: .init(id: graphID("Photo", project.id), url: project.photo.full),
      goal: .init(amount: String(project.stats.goal), currency: .case(.usd), symbol: "$"),
      pledged: .init(amount: String(project.stats.pledged), currency: .case(.usd), symbol: "$"),
      isLaunched: true, projectPrelaunchActivated: false, deadlineAt: project.dates.deadline.map(graphDate),
      projectLaunchedAt: project.dates.launchedAt.map(graphDate), isWatched: false, addOns: .init(totalCount: 0),
      backersCount: project.stats.backersCount,
      category: project.category.map { .init(analyticsName: $0.name, name: $0.name) },
      commentsCount: 0, country: .init(code: .case(.us), name: "United States"),
      creator: .init(id: graphID("User", project.creator.id), createdProjects: .init(totalCount: 1),
                     name: project.creator.name, isBlocked: false, imageUrl: project.creator.avatar.medium),
      currency: .case(.usd), launchedAt: project.dates.launchedAt.map(graphDate), pid: project.id,
      isInPostCampaignPledgingPhase: false, percentFunded: project.stats.percentFunded,
      isPrelaunchActivated: false, projectTags: [], postCampaignPledgingEnabled: false,
      rewards: .init(totalCount: project.rewards.count),
      state: .case(project.state == .successful ? .successful : .live),
      fxRate: 1, usdExchangeRate: 1, posts: .init(totalCount: 0), prelaunchActivated: false,
      url: project.urls.web.project, projectDescription: project.blurb,
      stateChangedAt: graphDate(project.dates.stateChangedAt), projectUsdExchangeRate: 1,
      location: project.location.map { .init(displayableName: $0.displayableName) })
  }

  private func graphID(_ type: String, _ id: Int) -> String {
    Data("\(type)-\(id)".utf8).base64EncodedString()
  }

  private func graphDate(_ timestamp: TimeInterval) -> String {
    // This schema's DateTime scalar is an epoch timestamp encoded as a string.
    String(timestamp)
  }

  private func moneyBucket(_ amount: Int) -> String {
    switch amount {
    case ..<1_000: return "BUCKET_0"
    case ..<10_000: return "BUCKET_1"
    case ..<100_000: return "BUCKET_2"
    case ..<1_000_000: return "BUCKET_3"
    default: return "BUCKET_4"
    }
  }
}
#endif
