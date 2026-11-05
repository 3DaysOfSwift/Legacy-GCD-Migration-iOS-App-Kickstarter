import GraphAPI

extension WatchProjectResponseEnvelope {
  /**
   Map `GraphAPI.UnwatchProjectMutation.Data` to a `WatchProjectResponseEnvelope`, otherwise return `nil`
   */
  static func from(_ data: GraphAPI.UnwatchProjectMutation.Data) -> WatchProjectResponseEnvelope? {
    guard let projectFromData = data.watchProject?.project else {
      return nil
    }

    let project = WatchProject.Project(
      id: projectFromData.id,
      isWatched: projectFromData.isWatched,
      watchesCount: projectFromData.watchesCount ?? 0
    )

    return WatchProjectResponseEnvelope(watchProject: WatchProject(project: project))
  }

}
