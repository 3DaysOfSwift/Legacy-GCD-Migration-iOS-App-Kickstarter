@testable import Kickstarter_iOS
import Experimentation
@_exported import Foundation
import KsApi

import ReactiveSwift
import XCTest

@MainActor
final class ValueRecorder<Value> {
  private(set) var values: [Value] = []
  var lastValue: Value? { self.values.last }

  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    self.assertValueCount(0, message, file: file, line: line)
  }
}

extension ValueRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
  func assertValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    self.assertValues([expected], message, file: file, line: line)
  }
  func assertLastValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.last, expected, message, file: file, line: line)
  }
}

@MainActor
internal enum TestSchedulerContext {
  static var current: DateScheduler = QueueScheduler.main
}

@MainActor
extension XCTestCase {
  // Pushes an environment onto the stack, executes a closure, and then pops the environment from the stack.
  func withEnvironment(_ env: Environment, body: () -> Void) {
    AppEnvironment.pushEnvironment(env)
    body()
    AppEnvironment.popEnvironment()
  }

  // Pushes an environment onto the stack, executes a closure, and then pops the environment from the stack.
  func withEnvironment(
    apiService: ServiceType = AppEnvironment.current.apiService,
    apiDelayInterval: DispatchTimeInterval = AppEnvironment.current.apiDelayInterval,
    applePayCapabilities: ApplePayCapabilitiesType = AppEnvironment.current.applePayCapabilities,
    application: UIApplicationType = UIApplication.shared,
    appTrackingTransparency: AppTrackingTransparencyType = AppEnvironment.current.appTrackingTransparency,
    assetImageGeneratorType: AssetImageGeneratorType.Type = AppEnvironment.current.assetImageGeneratorType,
    cache: KSCache = AppEnvironment.current.cache,
    calendar: Calendar = AppEnvironment.current.calendar,
    config: Config? = AppEnvironment.current.config,
    cookieStorage: HTTPCookieStorageProtocol = AppEnvironment.current.cookieStorage,
    coreTelephonyNetworkInfo: CoreTelephonyNetworkInfoType = AppEnvironment.current.coreTelephonyNetworkInfo,
    countryCode: String = AppEnvironment.current.countryCode,
    currentUser: User? = AppEnvironment.current.currentUser,
    currentUserEmail: String? = AppEnvironment.current.currentUserEmail,
    currentUserPPOSettings: PPOUserSettings? = AppEnvironment.current.currentUserPPOSettings,
    currentUserServerFeatures: Set<ServerFeature>? = AppEnvironment.current.currentUserServerFeatures,
    dateType: DateProtocol.Type = AppEnvironment.current.dateType,
    debounceInterval: DispatchTimeInterval = AppEnvironment.current.debounceInterval,
    device: UIDeviceType = AppEnvironment.current.device,
    isVoiceOverRunning: @escaping () -> Bool = AppEnvironment.current.isVoiceOverRunning,
    ksrAnalytics: KSRAnalytics = AppEnvironment.current.ksrAnalytics,
    language: Language = AppEnvironment.current.language,
    launchedCountries: LaunchedCountries = AppEnvironment.current.launchedCountries,
    locale: Locale = AppEnvironment.current.locale,
    mainBundle: NSBundleType = AppEnvironment.current.mainBundle,
    pushRegistrationType: PushRegistrationType.Type = AppEnvironment.current.pushRegistrationType,
    remoteConfigClient: RemoteConfigClientType? = AppEnvironment.current.remoteConfigClient,
    scheduler: DateScheduler = TestSchedulerContext.current,
    statsigClient: StatsigClientType? = AppEnvironment.current.statsigClient,
    ubiquitousStore: KeyValueStoreType = AppEnvironment.current.ubiquitousStore,
    userDefaults: KeyValueStoreType = AppEnvironment.current.userDefaults,
    uuidType: UUIDType.Type = AppEnvironment.current.uuidType,
    body: () -> Void
  ) {
    let previousScheduler = TestSchedulerContext.current
    TestSchedulerContext.current = scheduler
    defer { TestSchedulerContext.current = previousScheduler }
    self.withEnvironment(
      Environment(
        apiService: apiService,
        apiDelayInterval: apiDelayInterval,
        applePayCapabilities: applePayCapabilities,
        application: application,
        appTrackingTransparency: appTrackingTransparency,
        assetImageGeneratorType: assetImageGeneratorType,
        cache: cache,
        calendar: calendar,
        config: config,
        cookieStorage: cookieStorage,
        coreTelephonyNetworkInfo: coreTelephonyNetworkInfo,
        countryCode: countryCode,
        currentUser: currentUser,
        currentUserEmail: currentUserEmail,
        currentUserPPOSettings: currentUserPPOSettings,
        currentUserServerFeatures: currentUserServerFeatures,
        dateType: dateType,
        debounceInterval: debounceInterval,
        device: device,
        isVoiceOverRunning: isVoiceOverRunning,
        ksrAnalytics: ksrAnalytics,
        language: language,
        launchedCountries: launchedCountries,
        locale: locale,
        mainBundle: mainBundle,
        pushRegistrationType: pushRegistrationType,
        remoteConfigClient: remoteConfigClient,
        statsigClient: statsigClient,
        ubiquitousStore: ubiquitousStore,
        userDefaults: userDefaults,
        uuidType: uuidType
      ),
      body: body
    )
  }

  // MARK: Async

  // Async fixtures share the UI-owned environment. Keep stack mutation on the
  // same actor as their bodies, including when resuming after an await.
  // Pushes an environment onto the stack, executes a closure, and then pops the environment from the stack.
  @MainActor
  func withEnvironment(_ env: Environment, body: @MainActor () async -> Void) async {
    AppEnvironment.pushEnvironment(env)
    await body()
    AppEnvironment.popEnvironment()
  }

  // Pushes an environment onto the stack, executes a closure, and then pops the environment from the stack.
  @MainActor
  func withEnvironment(
    apiService: ServiceType = AppEnvironment.current.apiService,
    apiDelayInterval: DispatchTimeInterval = AppEnvironment.current.apiDelayInterval,
    applePayCapabilities: ApplePayCapabilitiesType = AppEnvironment.current.applePayCapabilities,
    application: UIApplicationType = UIApplication.shared,
    appTrackingTransparency: AppTrackingTransparencyType = AppEnvironment.current.appTrackingTransparency,
    assetImageGeneratorType: AssetImageGeneratorType.Type = AppEnvironment.current.assetImageGeneratorType,
    cache: KSCache = AppEnvironment.current.cache,
    calendar: Calendar = AppEnvironment.current.calendar,
    config: Config? = AppEnvironment.current.config,
    cookieStorage: HTTPCookieStorageProtocol = AppEnvironment.current.cookieStorage,
    coreTelephonyNetworkInfo: CoreTelephonyNetworkInfoType = AppEnvironment.current.coreTelephonyNetworkInfo,
    countryCode: String = AppEnvironment.current.countryCode,
    currentUser: User? = AppEnvironment.current.currentUser,
    currentUserEmail: String? = AppEnvironment.current.currentUserEmail,
    currentUserPPOSettings: PPOUserSettings? = AppEnvironment.current.currentUserPPOSettings,
    currentUserServerFeatures: Set<ServerFeature>? = AppEnvironment.current.currentUserServerFeatures,
    dateType: DateProtocol.Type = AppEnvironment.current.dateType,
    debounceInterval: DispatchTimeInterval = AppEnvironment.current.debounceInterval,
    device: UIDeviceType = AppEnvironment.current.device,
    isVoiceOverRunning: @escaping () -> Bool = AppEnvironment.current.isVoiceOverRunning,
    ksrAnalytics: KSRAnalytics = AppEnvironment.current.ksrAnalytics,
    language: Language = AppEnvironment.current.language,
    launchedCountries: LaunchedCountries = AppEnvironment.current.launchedCountries,
    locale: Locale = AppEnvironment.current.locale,
    mainBundle: NSBundleType = AppEnvironment.current.mainBundle,
    pushRegistrationType: PushRegistrationType.Type = AppEnvironment.current.pushRegistrationType,
    remoteConfigClient: RemoteConfigClientType? = AppEnvironment.current.remoteConfigClient,
    scheduler: DateScheduler = TestSchedulerContext.current,
    statsigClient: StatsigClientType? = AppEnvironment.current.statsigClient,
    ubiquitousStore: KeyValueStoreType = AppEnvironment.current.ubiquitousStore,
    userDefaults: KeyValueStoreType = AppEnvironment.current.userDefaults,
    uuidType: UUIDType.Type = AppEnvironment.current.uuidType,
    body: @MainActor () async -> Void
  ) async {
    let previousScheduler = TestSchedulerContext.current
    TestSchedulerContext.current = scheduler
    defer { TestSchedulerContext.current = previousScheduler }
    await self.withEnvironment(
      Environment(
        apiService: apiService,
        apiDelayInterval: apiDelayInterval,
        applePayCapabilities: applePayCapabilities,
        application: application,
        appTrackingTransparency: appTrackingTransparency,
        assetImageGeneratorType: assetImageGeneratorType,
        cache: cache,
        calendar: calendar,
        config: config,
        cookieStorage: cookieStorage,
        coreTelephonyNetworkInfo: coreTelephonyNetworkInfo,
        countryCode: countryCode,
        currentUser: currentUser,
        currentUserEmail: currentUserEmail,
        currentUserPPOSettings: currentUserPPOSettings,
        currentUserServerFeatures: currentUserServerFeatures,
        dateType: dateType,
        debounceInterval: debounceInterval,
        device: device,
        isVoiceOverRunning: isVoiceOverRunning,
        ksrAnalytics: ksrAnalytics,
        language: language,
        launchedCountries: launchedCountries,
        locale: locale,
        mainBundle: mainBundle,
        pushRegistrationType: pushRegistrationType,
        remoteConfigClient: remoteConfigClient,
        statsigClient: statsigClient,
        ubiquitousStore: ubiquitousStore,
        userDefaults: userDefaults,
        uuidType: uuidType
      ),
      body: body
    )
  }
}
