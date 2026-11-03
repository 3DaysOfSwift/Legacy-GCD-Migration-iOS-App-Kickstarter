import KsApi
import Prelude
import ReactiveSwift

@MainActor
public protocol SettingsNewslettersViewModelInputs {
  func didUpdate(user: User)
  func viewDidLoad()
}

@MainActor
public protocol SettingsNewslettersViewModelOutputs {
  var currentUser: Signal<User, Never> { get }
}

@MainActor
public protocol SettingsNewslettersViewModelType {
  var inputs: SettingsNewslettersViewModelInputs { get }
  var outputs: SettingsNewslettersViewModelOutputs { get }
}

@MainActor
public final class SettingsNewslettersViewModel: SettingsNewslettersViewModelType,
  SettingsNewslettersViewModelInputs, SettingsNewslettersViewModelOutputs {
  public init(feature: SettingsFeature? = nil) {
    let feature = feature ?? AppModel.shared.settingsFeature
    let initialUser = self.viewDidLoadProperty.signal
      .flatMap {
        feature.userResult().wrapInOptional().demoteErrors()
      }
      .skipNil()
      .skipRepeats()

    let updatedUser = self.didUpdateUserProperty.signal.skipNil()

    self.currentUser = Signal.merge(initialUser, updatedUser)
  }

  fileprivate let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
  }

  fileprivate let didUpdateUserProperty = MutableProperty<User?>(nil)
  public func didUpdate(user: User) {
    self.didUpdateUserProperty.value = user
  }

  public let currentUser: Signal<User, Never>

  public var inputs: SettingsNewslettersViewModelInputs { return self }
  public var outputs: SettingsNewslettersViewModelOutputs { return self }
}
