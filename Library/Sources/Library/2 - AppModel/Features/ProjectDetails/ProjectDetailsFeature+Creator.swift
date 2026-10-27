import Foundation
import KsApi

extension ProjectDetailsFeature {
  /// Preserves the authenticated request preparation used by the creator bio.
  public func creatorBiographyRequest(projectURL: String) -> URLRequest? {
    guard let url = URL(string: projectURL)?.appendingPathComponent("creator_bio") else { return nil }
    return AppEnvironment.current.apiService.preparedRequest(forURL: url)
  }

  public func isCreatorMessage(request: URLRequest) -> Bool {
    if let navigation = Navigation.match(request),
       case .project(_, .messageCreator, _, _) = navigation { return true }
    return false
  }

  public var creatorMessageRequiresAuthentication: Bool { AppEnvironment.current.currentUser == nil }

  /// Authorization is evaluated for each interaction, not cached at page load.
  public func creatorMessageSubject(projectID: Int, projectName: String) -> MessageSubject? {
    guard !self.creatorMessageRequiresAuthentication else { return nil }
    return .project(id: projectID, name: projectName)
  }
}
