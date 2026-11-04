import Foundation
import KsApi
import ReactiveSwift

public protocol ViewPledgeUseCaseInputs {
  func goToPledgeViewTapped()
}

public protocol ViewPledgeUseCaseOutputs {
  var goToNativePledgeView: Signal<ManagePledgeViewParamConfigData, Never> { get }
  var goToPledgeManagementPledgeView: Signal<String, Never> { get }
}

public protocol ViewPledgeUseCaseType {
  var inputs: ViewPledgeUseCaseInputs { get }
  var outputs: ViewPledgeUseCaseOutputs { get }
}

/// Determines the correct destination when viewing a pledge—either routing to the pledge
/// management web view or the native pledge view—based on the backing, order state, and
/// whether the pledge follows the net new backer flow.
/// Triggered when the user taps to manage their pledge or go to backing details.
public final class ViewPledgeUseCase: ViewPledgeUseCaseType,
  ViewPledgeUseCaseInputs,
  ViewPledgeUseCaseOutputs {
  public init(with projectAndBacking: Signal<(Project, Backing), Never>) {
    let destination = projectAndBacking.takeWhen(self.goToPledgeViewTappedProperty.signal)
      .map { pledgeDestination(project: $0.0, backing: $0.1) }
    self.goToPledgeManagementPledgeView = destination.compactMap {
      if case let .web(url) = $0 { return url }
      return nil
    }
    self.goToNativePledgeView = destination.compactMap {
      if case let .native(params) = $0 { return params }
      return nil
    }
  }

  public let goToNativePledgeView: Signal<ManagePledgeViewParamConfigData, Never>
  public let goToPledgeManagementPledgeView: Signal<String, Never>

  public var inputs: ViewPledgeUseCaseInputs { return self }
  public var outputs: ViewPledgeUseCaseOutputs { return self }

  private let goToPledgeViewTappedProperty = MutableProperty(())
  public func goToPledgeViewTapped() {
    self.goToPledgeViewTappedProperty.value = ()
  }
}

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
