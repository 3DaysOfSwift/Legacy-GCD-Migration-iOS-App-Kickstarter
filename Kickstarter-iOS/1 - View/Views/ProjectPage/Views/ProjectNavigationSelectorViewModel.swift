import KsApi
import Observation

public enum NavigationSection: Int, CaseIterable {
  case overview
  case campaign
  case faq
  case risks
  case aiDisclosure
  case environmentalCommitments

  public var displayString: String {
    switch self {
    case .campaign: return Strings.Campaign()
    case .environmentalCommitments: return Strings.Environmental_commitments()
    case .faq: return Strings.Faq()
    case .overview: return Strings.Overview()
    case .aiDisclosure: return Strings.Use_of_ai()
    case .risks: return Strings.Risks()
    }
  }
}

@MainActor
@Observable
public final class ProjectNavigationSelectorViewModel {
  public var onAnimate: ((Int) -> Void)?
  public var onSections: (([NavigationSection]) -> Void)?
  public var onSelect: ((Int) -> Void)?
  private var project: (Project, RefTag?)?
  private var appeared = false
  private var hasTappedNonzero = false
  private var lastTrackedIndex: Int?

  public init() {}

  public func didMoveToSuperview() {
    guard !self.appeared else { return }
    self.appeared = true
    self.onSections?([.overview])
    self.onSelect?(0)
  }

  public func configureNavigationSelector(with properties: (Project, RefTag?)) {
    self.project = properties
    self.onSections?(Self.displayableTabs(for: properties.0))
    self.onSelect?(0)
  }

  public func buttonTapped(index: Int) {
    self.onAnimate?(index)
    self.onSelect?(index)
    if !self.hasTappedNonzero {
      guard index != 0 else { return }
      self.hasTappedNonzero = true
    }
    guard self.lastTrackedIndex != index else { return }
    self.lastTrackedIndex = index
    guard let (project, refTag) = self.project, let context = self.navigationTabContext(index: index) else { return }
    AppEnvironment.current.ksrAnalytics.trackProjectViewed(project, refTag: refTag, sectionContext: context)
  }

  private static func displayableTabs(for project: Project) -> [NavigationSection] {
    let base: [NavigationSection] = [.overview]
    guard let properties = project.extendedProjectProperties, let prelaunch = project.displayPrelaunch,
          !prelaunch else { return featureProjectStoryRichTextEnabled() ? base + [.campaign] : base }
    var sections = base + [.campaign, .faq, .risks]
    if properties.aiDisclosure?.involvesAi == true { sections.append(.aiDisclosure) }
    if !properties.environmentalCommitments.isEmpty { sections.append(.environmentalCommitments) }
    return sections
  }

  private func navigationTabContext(index: Int) -> KSRAnalytics.SectionContext? {
    switch index {
    case 0: return .tabSelected(.overview)
    case 1: return .tabSelected(.campaign)
    case 2: return .tabSelected(.faqs)
    case 3: return .tabSelected(.risks)
    case 4: return .tabSelected(.useOfAI)
    case 5: return .tabSelected(.environmentalCommitments)
    default: return nil
    }
  }
}
