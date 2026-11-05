import KsApi

enum ViewPledgeDestination {
  case native(ManagePledgeViewParamConfigData)
  case web(String)
}

func pledgeDestination(project: Project, backing: Backing) -> ViewPledgeDestination {
  if let order = backing.order, project.personalization.isBacking == true, order.checkoutState == .complete {
    return .web(backing.backingDetailsPageRoute)
  }
  return .native((projectParam: .slug(project.slug), backingParam: .id(backing.id)))
}
