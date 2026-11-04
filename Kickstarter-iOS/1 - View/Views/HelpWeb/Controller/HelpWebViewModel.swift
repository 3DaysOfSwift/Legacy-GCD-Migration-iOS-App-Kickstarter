import Foundation
import KsApi

@MainActor
internal final class HelpWebViewModel {
  private var helpType: HelpType?

  func configureWith(helpType: HelpType) {
    self.helpType = helpType
  }

  func requestForViewDidLoad() -> URLRequest? {
    guard let url = self.helpType?.url(withBaseUrl: AppEnvironment.current.apiService.serverConfig.webBaseUrl) else {
      return nil
    }
    return AppEnvironment.current.apiService.preparedRequest(forURL: url)
  }
}
