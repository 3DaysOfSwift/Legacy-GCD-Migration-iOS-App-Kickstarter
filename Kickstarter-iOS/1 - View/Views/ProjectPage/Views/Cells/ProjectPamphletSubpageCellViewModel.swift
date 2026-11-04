import KDS
import KsApi
import Observation
import UIKit

@MainActor
@Observable
public final class ProjectPamphletSubpageCellViewModel {
  public init() {}
  public private(set) var countLabelText: String?
  public private(set) var labelText: String?
  public private(set) var topSeparatorViewHidden = false
  public private(set) var separatorViewHidden = false

  public func configureWith(subpage: ProjectPamphletSubpage) {
    self.topSeparatorViewHidden = subpage.position != .first
    self.separatorViewHidden = subpage.position == .last
    guard subpage.isComments || subpage.isUpdates else { return }
    self.labelText = subpage.isComments ? Strings.project_menu_buttons_comments() : Strings.project_menu_buttons_updates()
    self.countLabelText = Format.wholeNumber(subpage.count ?? 0)
  }
}

public enum ProjectPamphletSubpageCellPosition {
  case first
  case middle
  case last
}

extension ProjectPamphletSubpageCellPosition: Equatable {}
public func == (lhs: ProjectPamphletSubpageCellPosition, rhs: ProjectPamphletSubpageCellPosition) -> Bool {
  switch (lhs, rhs) {
  case (.first, .first), (.middle, .middle), (.last, .last):
    return true
  default:
    return false
  }
}

public enum ProjectPamphletSubpage {
  case comments(Int?, ProjectPamphletSubpageCellPosition)
  case updates(Int?, ProjectPamphletSubpageCellPosition)
  case reportProject(ProjectPamphletSubpageCellPosition)

  public var count: Int? {
    switch self {
    case let .comments(count, _): return count
    case let .updates(count, _): return count
    case .reportProject: return nil
    }
  }

  public var position: ProjectPamphletSubpageCellPosition {
    switch self {
    case let .comments(_, position): return position
    case let .updates(_, position): return position
    case let .reportProject(position): return position
    }
  }

  public var isComments: Bool {
    switch self {
    case .comments: return true
    default: return false
    }
  }

  public var isUpdates: Bool {
    switch self {
    case .updates: return true
    default: return false
    }
  }

  public var isReportProject: Bool {
    switch self {
    case .reportProject: return true
    default: return false
    }
  }
}

extension ProjectPamphletSubpage: Equatable {}
public func == (lhs: ProjectPamphletSubpage, rhs: ProjectPamphletSubpage) -> Bool {
  switch (lhs, rhs) {
  case let (.comments(lhsCount, lhsPos), .comments(rhsCount, rhsPos)):
    return lhsCount == rhsCount && lhsPos == rhsPos
  case let (.updates(lhsCount, lhsPos), .updates(rhsCount, rhsPos)):
    return lhsCount == rhsCount && lhsPos == rhsPos
  case let (.reportProject(lhsPos), .reportProject(rhsPos)):
    return lhsPos == rhsPos
  default:
    return false
  }
}
