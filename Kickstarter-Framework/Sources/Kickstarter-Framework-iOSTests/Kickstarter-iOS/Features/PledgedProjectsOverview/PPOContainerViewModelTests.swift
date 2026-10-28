import Combine
import XCTest

@testable import Kickstarter_Framework
@testable import KsApi
@testable import Library

@MainActor
final class PPOContainerViewModelTests: XCTestCase {
  func testAddressAcknowledgedShowsSuccessAndRefreshesOnce() async {
    let feature = self.feature(MockService(confirmBackingAddressResult: .success(true)))
    let model = PPOContainerViewModel(feature: feature)
    var progress: [PPOActionState] = []
    var banners: [MessageBannerType] = []
    var refreshes = 0
    let banner = model.showBanner.sink { banners.append($0.type) }
    let refresh = model.shouldRefresh.sink { refreshes += 1 }
    defer {
      banner.cancel()
      refresh.cancel()
    }
    model.confirmAddress(addressId: "A", backingId: "B") { progress.append($0) }
    XCTAssertEqual(progress, [.confirmed])
    await feature.waitForOperations()
    XCTAssertEqual(progress, [.confirmed, .succeeded])
    XCTAssertEqual(banners, [.success])
    XCTAssertEqual(refreshes, 1)
  }
  func testAddressNegativeAcknowledgementPreservesProgressAndErrorBanner() async {
    let feature = self.feature(MockService(confirmBackingAddressResult: .success(false)))
    let model = PPOContainerViewModel(feature: feature)
    var progress: [PPOActionState] = []
    var errors = 0
    var refreshes = 0
    let banner = model.showBanner.sink { if $0.type == .error { errors += 1 } }
    let refresh = model.shouldRefresh.sink { refreshes += 1 }
    defer {
      banner.cancel()
      refresh.cancel()
    }
    model.confirmAddress(addressId: "A", backingId: "B") { progress.append($0) }
    await feature.waitForOperations()
    XCTAssertEqual(progress, [.confirmed, .succeeded])
    XCTAssertEqual(errors, 1)
    XCTAssertEqual(refreshes, 0)
  }
  func testAddressFailureDoesNotReportSuccessOrRefresh() async {
    let feature = self.feature(
      MockService(confirmBackingAddressResult: .failure(.couldNotParseJSON)))
    let model = PPOContainerViewModel(feature: feature)
    var progress: [PPOActionState] = []
    var errors = 0
    let banner = model.showBanner.sink { if $0.type == .error { errors += 1 } }
    defer { banner.cancel() }
    model.confirmAddress(addressId: "A", backingId: "B") { progress.append($0) }
    await feature.waitForOperations()
    XCTAssertEqual(progress, [.confirmed])
    XCTAssertEqual(errors, 1)
  }
  func testReceiptFailurePublishesOneErrorAndOneRefresh() async {
    let feature = self.feature(
      MockService(updateRewardReceivedResult: .failure(.couldNotParseJSON)))
    let model = PPOContainerViewModel(feature: feature)
    var errors = 0
    var refreshes = 0
    let banner = model.showBanner.sink { if $0.type == .error { errors += 1 } }
    let refresh = model.shouldRefresh.sink { refreshes += 1 }
    defer {
      banner.cancel()
      refresh.cancel()
    }
    model.updateRewardReceived(backingId: "B", rewardReceived: true)
    await feature.waitForOperations()
    XCTAssertEqual(errors, 1)
    XCTAssertEqual(refreshes, 1)
  }
  func testReceiptSuccessKeepsOptimisticCardWithoutBannerOrRefresh() async {
    let feature = self.feature(MockService(updateRewardReceivedResult: .success(true)))
    let model = PPOContainerViewModel(feature: feature)
    var banners = 0
    var refreshes = 0
    let banner = model.showBanner.sink { _ in banners += 1 }
    let refresh = model.shouldRefresh.sink { refreshes += 1 }
    defer {
      banner.cancel()
      refresh.cancel()
    }
    model.updateRewardReceived(backingId: "B", rewardReceived: false)
    await feature.waitForOperations()
    XCTAssertEqual(banners, 0)
    XCTAssertEqual(refreshes, 0)
  }
  private func feature(_ service: MockService) -> PledgeFeature {
    PledgeFeature(
      sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: service) }),
      makeProvider: { AsyncPledgeProvider(service: service) })
  }
}
