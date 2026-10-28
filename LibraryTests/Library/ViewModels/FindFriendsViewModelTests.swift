@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import UIKit.UIActivity
import XCTest

@MainActor
final class FindFriendsViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = FriendsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
    makeProvider: {
      precondition(AppEnvironment.current.apiService is MockService)
      return AsyncFriendsProvider(service: AppEnvironment.current.apiService)
    }, sleep: { _ in })
  private lazy var vm: FindFriendsViewModelType = FindFriendsViewModel(feature: self.feature)

  let friends = TestObserver<[User], Never>()
  let goToDiscovery = TestObserver<DiscoveryParams, Never>()
  let showErrorAlert = TestObserver<AlertError, Never>()
  let showFacebookConnect = TestObserver<Bool, Never>()
  let showFollowAllFriendsAlert = TestObserver<Int, Never>()
  let showLoadingIndicatorView = TestObserver<Bool, Never>()
  let stats = TestObserver<FriendStatsEnvelope, Never>()
  let statsSource = TestObserver<FriendsSource, Never>()

  override func setUp() {
    super.setUp()

    MainActor.assumeIsolated {
      self.vm.outputs.friends.map { $0.0 }.observe(self.friends.observer)
      self.vm.outputs.goToDiscovery.observe(self.goToDiscovery.observer)
      self.vm.outputs.showErrorAlert.observe(self.showErrorAlert.observer)
      self.vm.outputs.showFacebookConnect.map { $0.1 }.observe(self.showFacebookConnect.observer)
      self.vm.outputs.showFollowAllFriendsAlert.observe(self.showFollowAllFriendsAlert.observer)
      self.vm.outputs.showLoadingIndicatorView.observe(self.showLoadingIndicatorView.observer)
      self.vm.outputs.stats.map { env, _ in env }.observe(self.stats.observer)
      self.vm.outputs.stats.map { _, source in source }.observe(self.statsSource.observer)
    }
  }

  override func tearDown() async throws {
    self.feature.reset()
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  private func advanceFriends(by interval: DispatchTimeInterval = .seconds(0)) async {
    await self.feature.waitForOperations()
    await self.scheduler.advance(by: interval)
    await self.feature.waitForOperations()
    await self.scheduler.advance()
  }

  func testSource() async {
    self.vm.inputs.configureWith(source: FriendsSource.findFriends)
    self.vm.inputs.viewDidLoad()

    self.vm.inputs.configureWith(source: FriendsSource.discovery)
    self.vm.inputs.viewDidLoad()

    self.vm.inputs.configureWith(source: FriendsSource.settings)
    self.vm.inputs.viewDidLoad()
  }

  func testGoToDiscovery() async {
    let params = DiscoveryParams.defaults
      |> DiscoveryParams.lens.social .~ true
      |> DiscoveryParams.lens.sort .~ .magic

    withEnvironment(currentUser: User.template) {
      self.vm.inputs.configureWith(source: FriendsSource.findFriends)
      self.vm.inputs.viewDidLoad()

      self.goToDiscovery.assertValueCount(0)

      self.vm.inputs.discoverButtonTapped()

      self.goToDiscovery.assertValues([params], "Go to Discovery emits with 'Friends Backed' params")
    }
  }

  func testFriends_WithFacebookConnectedUser() async {
    await withEnvironment(currentUser: User.template |> \.facebookConnected .~ true) {
      self.vm.inputs.configureWith(source: FriendsSource.settings)

      self.friends.assertValueCount(0, "Friends does not emit")
      self.showFacebookConnect.assertValueCount(0, "Facebook connect does not emit")

      self.vm.inputs.viewDidLoad()

      self.showLoadingIndicatorView.assertValues([true])

      await self.advanceFriends()

      self.showLoadingIndicatorView.assertValues([true, false])
      self.friends.assertValueCount(1, "Friends emit")
      self.showFacebookConnect.assertValues([false])

      self.vm.inputs.willDisplayRow(30, outOf: 10)

      self.showLoadingIndicatorView.assertValues([true, false])
      self.friends.assertValueCount(1, "Friends value has not changed")
      self.showFacebookConnect.assertValues([false], "Show Facebook Connect value has not changed")

      await self.advanceFriends()

      self.showLoadingIndicatorView.assertValues([true, false])
      self.friends.assertValueCount(2, "Friends emits again")
      self.showFacebookConnect.assertValues([false], "Show Facebook Connect value has not changed")
    }
  }

  func testFriends_WithNonFacebookConnectedUser() async {
    await withEnvironment(currentUser: User.template) {
      self.friends.assertValueCount(0, "Friends does not emit")
      self.showFacebookConnect.assertValueCount(0, "Facebook connect does not emit")

      self.vm.inputs.configureWith(source: FriendsSource.discovery)

      self.showFacebookConnect.assertValueCount(0, "Show Facebook Connect does not emit")

      self.vm.inputs.viewDidLoad()

      await self.advanceFriends()

      self.friends.assertValueCount(0, "Friends does not emit")
      self.showFacebookConnect.assertValues([true], "Show Facebook Connect")

      AppEnvironment.updateCurrentUser(User.template |> \.facebookConnected .~ true)
      self.vm.inputs.findFriendsFacebookConnectCellDidFacebookConnectUser()

      self.showLoadingIndicatorView.assertValues([true])

      await self.advanceFriends()

      self.showLoadingIndicatorView.assertValues([true, false])
      self.friends.assertValueCount(1, "Friends emit after Facebook Connected")
      self.showFacebookConnect.assertValues([true, false], "Hide Facebook Connect")

      self.vm.inputs.willDisplayRow(20, outOf: 10)

      self.showLoadingIndicatorView.assertValues([true, false])
      self.friends.assertValueCount(1, "Friends value has not changed")
      self.showFacebookConnect.assertValues([true, false], "Show Facebook Connect value has not changed")

      await self.advanceFriends()

      self.showLoadingIndicatorView.assertValues([true, false])
      self.friends.assertValueCount(2, "Friends emits again")
      self.showFacebookConnect.assertValues([true, false], "Show Facebook Connect value has not changed")
    }
  }

  func testFacebookConnectedUser_needsReconnect() async {
    let needsReconnectUser = User.template
      |> \.facebookConnected .~ true
      |> \.needsFreshFacebookToken .~ true

    await withEnvironment(currentUser: needsReconnectUser) {
      self.vm.inputs.configureWith(source: FriendsSource.findFriends)

      self.vm.inputs.viewDidLoad()

      await self.advanceFriends()

      self.showFacebookConnect.assertValues([true])
      self.stats.assertValueCount(0)
    }
  }

  func testStats_WithFacebookConnectedUser() async {
    await withEnvironment(currentUser: User.template |> \.facebookConnected .~ true) {
      self.vm.inputs.configureWith(source: FriendsSource.settings)

      self.stats.assertValueCount(0)
      self.statsSource.assertValueCount(0)

      self.vm.inputs.viewDidLoad()

      await self.advanceFriends()

      self.stats.assertValueCount(1)
      self.statsSource.assertValues([FriendsSource.settings])
    }
  }

  func testStats_WithNonFacebookConnectedUser() async {
    await withEnvironment(currentUser: User.template) {
      self.vm.inputs.configureWith(source: FriendsSource.settings)

      self.stats.assertValueCount(0)
      self.statsSource.assertValueCount(0)

      self.vm.inputs.viewDidLoad()

      await self.advanceFriends()

      self.stats.assertValueCount(0, "Stats should not emit if user isn't FB Connected")
      self.statsSource.assertValueCount(0)
    }
  }

  func testStats_WithNeedsReconnectUser() async {
    let facebookConnectedNeedsReconnectUser = User.template
      |> \.facebookConnected .~ true
      |> \.needsFreshFacebookToken .~ true

    await withEnvironment(currentUser: facebookConnectedNeedsReconnectUser) {
      self.vm.inputs.configureWith(source: FriendsSource.settings)

      self.stats.assertValueCount(0)
      self.statsSource.assertValueCount(0)

      self.vm.inputs.viewDidLoad()

      await self.advanceFriends()

      self.stats.assertValueCount(0, "Stats should not emit if needs facebook reconnect")
      self.statsSource.assertValueCount(0)
    }
  }

  func testFollowAllFriendsFlow() async {
    let friendsResponse = FindFriendsEnvelope.template
    let user = User.template
      |> \.facebookConnected .~ true

    await withEnvironment(apiService: MockService(fetchFriendsResponse: friendsResponse), currentUser: user) {
      self.vm.inputs.configureWith(source: FriendsSource.settings)
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.willDisplayRow(0, outOf: 2)

      await self.advanceFriends()

      self.friends.assertValues([friendsResponse.users], "Initial friends load.")

      self.vm.inputs.findFriendsStatsCellShowFollowAllFriendsAlert(friendCount: 1_000)

      self.showFollowAllFriendsAlert.assertValues([1_000], "Show Follow All Friends alert with friend count")

      self.vm.inputs.findFriendsStatsCellShowFollowAllFriendsAlert(friendCount: 1_000)

      self.showFollowAllFriendsAlert.assertValues([1_000, 1_000])

      self.vm.inputs.confirmFollowAllFriends()
    await self.feature.waitForOperations()

      // Test the 2 second "Follow all" debounce.
      await self.advanceFriends(by: .seconds(1))

      self.friends.assertValues([friendsResponse.users, []], "Friend list clears.")

      await self.advanceFriends(by: .seconds(1))

      self.friends.assertValues([friendsResponse.users, [], friendsResponse.users], "Updated friends emit.")
    }
  }

  func testLoaderIsAnimating_WithFacebookConnectedUser() async {
    await withEnvironment(currentUser: User.template |> \.facebookConnected .~ true) {
      self.vm.inputs.configureWith(source: FriendsSource.settings)

      self.showLoadingIndicatorView.assertValueCount(0, "Loader is hidden")

      self.vm.inputs.viewDidLoad()

      self.showLoadingIndicatorView.assertValues([true])

      await self.advanceFriends()

      self.showLoadingIndicatorView.assertValues([true, false])

      self.vm.inputs.willDisplayRow(30, outOf: 10)

      self.showLoadingIndicatorView.assertValues([true, false])

      await self.advanceFriends()

      self.showLoadingIndicatorView.assertValues([true, false])
    }
  }

  func testLoadedMoreFriendsReporting() async {
    await withEnvironment(currentUser: .template |> \.facebookConnected .~ true) {
      self.vm.inputs.configureWith(source: FriendsSource.settings)
      self.vm.inputs.viewDidLoad()
      await self.advanceFriends()

      // This call should NOT trigger next page request and reporting
      self.vm.inputs.willDisplayRow(5, outOf: 10)
      await self.advanceFriends()

      // This call should trigger next page request and reporting
      self.vm.inputs.willDisplayRow(8, outOf: 10)
      await self.advanceFriends()
    }
  }

  func testLoaderIsAnimating_WithNonFacebookConnectedUser() async {
    await withEnvironment(currentUser: User.template) {
      self.vm.inputs.configureWith(source: FriendsSource.settings)

      self.showLoadingIndicatorView.assertValueCount(0, "Loader is hidden")

      self.vm.inputs.viewDidLoad()

      self.showLoadingIndicatorView.assertDidNotEmitValue()

      await self.advanceFriends()

      self.showLoadingIndicatorView.assertDidNotEmitValue()
    }
  }

  func testFacebookErrorAlerts() async {
    self.vm.inputs.configureWith(source: FriendsSource.discovery)

    self.showFacebookConnect.assertValueCount(0, "Show Facebook Connect does not emit")

    self.vm.inputs.viewDidLoad()

    await self.advanceFriends()

    self.showFacebookConnect.assertValues([true], "Show Facebook Connect")

    let alertTokenFail = AlertError.facebookTokenFail

    self.vm.inputs.findFriendsFacebookConnectCellShowErrorAlert(alertTokenFail)

    self.showErrorAlert.assertValues([alertTokenFail])

    let errorAccountTaken = ErrorEnvelope(
      errorMessages: ["This Facebook account is already linked to another Kickstarter user."],
      ksrCode: .FacebookConnectAccountTaken,
      httpCode: 403,
      exception: nil
    )

    let alertAccountTaken = AlertError.facebookConnectAccountTaken(envelope: errorAccountTaken)

    self.vm.inputs.findFriendsFacebookConnectCellShowErrorAlert(alertAccountTaken)

    self.showErrorAlert.assertValues([alertTokenFail, alertAccountTaken])

    let errorEmailTaken = ErrorEnvelope(
      errorMessages: [
        "The email associated with this Facebook account is already registered to another Kickstarter user."
      ],
      ksrCode: .FacebookConnectEmailTaken,
      httpCode: 403,
      exception: nil
    )

    let alertEmailTaken = AlertError.facebookConnectEmailTaken(envelope: errorEmailTaken)

    self.vm.inputs.findFriendsFacebookConnectCellShowErrorAlert(alertEmailTaken)

    self.showErrorAlert.assertValues([alertTokenFail, alertAccountTaken, alertEmailTaken])
  }
}
