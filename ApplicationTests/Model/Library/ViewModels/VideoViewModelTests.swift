@testable import Kickstarter_iOS
import AVFoundation
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class VideoViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  internal let vm = VideoViewModel(feature: ProjectMediaFeature(makeProvider: {
    AsyncProjectMediaProvider(service: AppEnvironment.current.apiService)
  }))
  internal let addCompletionObserver = VideoRecorder<CMTime>()
  internal let configurePlayerWithURL = VideoRecorder<String>()
  internal let incrementVideoCompletion = VideoRecorder<VoidEnvelope>()
  internal let incrementVideoStart = VideoRecorder<VoidEnvelope>()
  internal let opacityForViews = VideoRecorder<CGFloat>()
  internal let pauseVideo = VideoRecorder<Void>()
  internal let playVideo = VideoRecorder<Void>()
  internal let playButtonHidden = VideoRecorder<Bool>()
  internal let projectImageHidden = VideoRecorder<Bool>()
  internal let projectImageURL = VideoRecorder<String?>()
  internal let seekToBeginning = VideoRecorder<Void>()
  internal let videoViewHidden = VideoRecorder<Bool>()

  let pauseRate = 0.0
  let playRate = 1.0
  let startTime = CMTimeMake(value: 0, timescale: 1)
  let halfwayTime = CMTimeMake(value: 50, timescale: 1)
  let completedThreshold = CMTimeMake(value: 85, timescale: 1)
  let duration = CMTimeMake(value: 100, timescale: 1)

  internal override func setUp() async throws {
    try await super.setUp()
    self.vm.onCompletionBoundary = { self.addCompletionObserver.values.append($0) }
    self.vm.onPlayerURL = { self.configurePlayerWithURL.values.append($0.absoluteString) }
    self.vm.onReportCompletion = { self.incrementVideoCompletion.values.append($0) }
    self.vm.onReportStart = { self.incrementVideoStart.values.append($0) }
    self.vm.onPause = { self.pauseVideo.values.append(()) }
    self.vm.onPlay = { self.playVideo.values.append(()) }
    self.vm.onPlayButtonHidden = { self.playButtonHidden.values.append($0) }
    self.vm.onProjectImageHidden = { self.projectImageHidden.values.append($0) }
    self.vm.onProjectImageURL = { self.projectImageURL.values.append($0?.absoluteString) }
    self.vm.onOpacity = { self.opacityForViews.values.append($0) }
    self.vm.onSeekToBeginning = { self.seekToBeginning.values.append(()) }
    self.vm.onVideoHidden = { self.videoViewHidden.values.append($0) }
  }

  func testAddCompletionObserver() async {
    self.vm.configureWith(project: Project.template)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    self.vm.playButtonTapped()
    self.vm.durationChanged(toNew: self.duration)

    self.addCompletionObserver.assertValues(
      [self.completedThreshold],
      "Observer added to completion threshold."
    )
  }

  func testConfigureVideoWithURL_setsHighURL_WhenHlsIsNil() async {
    let video = .template
      |> Project.Video.lens.hls .~ nil
      |> Project.Video.lens.high .~ "https://sickskatevid.mp4"
    let project = .template |> Project.lens.video .~ video

    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()
    self.vm.playButtonTapped()

    self.configurePlayerWithURL.assertValues([video.high], "Video url emitted.")
  }

  func testConfigureVideoWithURL_setsHlsURL_WhenHlsIsNotNil() async {
    let video = .template
      |> Project.Video.lens.hls .~ "https://sickskatevid.m3u8"
      |> Project.Video.lens.high .~ "https://sickskatevid.mp4"
    let project = .template |> Project.lens.video .~ video

    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()
    self.vm.playButtonTapped()

    self.configurePlayerWithURL.assertValues([video.hls!], "Video url emitted.")
  }

  func testIncrementVideoStats() async {
    await withEnvironment(apiService: MockService()) {
      self.vm.configureWith(project: Project.template)
      self.vm.viewDidLoad()
      self.vm.viewDidAppear()

      self.vm.playButtonTapped()
      self.vm.durationChanged(toNew: self.duration)
      self.vm.rateChanged(toNew: self.playRate, atTime: self.startTime)

      await self.vm.waitForReports()

      self.incrementVideoStart.assertValueCount(1, "Incremented video start count.")

      self.vm.rateChanged(toNew: self.pauseRate, atTime: self.duration)
      await self.vm.waitForReports()
      self.incrementVideoCompletion.assertValueCount(1, "Incremented video complete count.")

      self.vm.rateChanged(toNew: self.pauseRate, atTime: self.startTime)
      self.vm.rateChanged(toNew: self.playRate, atTime: self.startTime)
      await self.vm.waitForReports()
      self.incrementVideoStart.assertValueCount(1, "Video start count not incremented again.")

      self.vm.rateChanged(toNew: self.pauseRate, atTime: self.duration)
      await self.vm.waitForReports()
      self.incrementVideoCompletion.assertValueCount(1, "Video complete count not incremented again.")
    }
  }

  func testPauseVideoWhenViewDidDisappear() async {
    self.vm.configureWith(project: Project.template)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    // Leave the project magazine without starting video.
    self.vm.viewWillDisappear()
    self.vm.viewDidDisappear(animated: true)
    self.pauseVideo.assertDidNotEmitValue("Video not paused by view navigation.")
    XCTAssertEqual([], self.segmentTrackingClient.events, "No tracking events occur.")

    // Go back to the project and start playing the video.
    self.vm.viewDidAppear()
    self.vm.playButtonTapped()
    self.vm.durationChanged(toNew: self.duration)
    self.vm.rateChanged(toNew: self.playRate, atTime: self.startTime)
    self.pauseVideo.assertDidNotEmitValue("Video not paused by view navigation.")

    // Player pauses the video.
    self.vm.rateChanged(toNew: self.pauseRate, atTime: self.halfwayTime)
    self.pauseVideo.assertDidNotEmitValue("Video not paused by view navigation.")

    // Leave the project magazine.
    self.vm.viewWillDisappear()
    self.vm.viewDidDisappear(animated: true)
    self.pauseVideo.assertValueCount(1, "Video pauses when view disappears.")
  }

  func testProjectImageAndOverlayVisibility() async {
    self.vm.configureWith(project: Project.template)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    self.playButtonHidden.assertValues([false])
    self.projectImageHidden.assertValues([false])
    self.videoViewHidden.assertValues([true])

    self.vm.playButtonTapped()
    self.vm.durationChanged(toNew: self.duration)
    self.vm.rateChanged(toNew: self.playRate, atTime: self.startTime)

    self.playVideo.assertValueCount(1)
    self.playButtonHidden.assertValues([false, true])
    self.projectImageHidden.assertValues([false, true], "Overlaid views hidden when video starts.")
    self.videoViewHidden.assertValues([true, false])

    self.vm.rateChanged(toNew: self.pauseRate, atTime: self.halfwayTime)
    self.playButtonHidden.assertValues([false, true])
    self.projectImageHidden.assertValues([false, true], "Overlaid views still hidden on pause.")

    self.vm.rateChanged(toNew: self.pauseRate, atTime: self.duration)
    self.playButtonHidden.assertValues([false, true, false])
    self.projectImageHidden.assertValues([false, true, false], "Overlaid views reappear at end.")
    self.videoViewHidden.assertValues([true, false, true])
  }

  func testProjectImageEmits() async {
    let project = Project.template

    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    self.projectImageURL.assertValues([project.photo.full])
    self.projectImageHidden.assertValues([false])
    self.videoViewHidden.assertValues([true])
  }

  func testProjectWithNoVideo() async {
    let project = .template
      |> Project.lens.video .~ nil

    self.vm.configureWith(project: project)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    self.configurePlayerWithURL.assertValueCount(0)
    self.addCompletionObserver.assertValues([])
    self.playButtonHidden.assertValues([true])
    self.projectImageHidden.assertValues([false])
    self.videoViewHidden.assertValues([true])
  }

  func testSeekPlayerToBeginning() async {
    self.vm.configureWith(project: Project.template)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    self.vm.playButtonTapped()
    self.vm.durationChanged(toNew: self.duration)
    self.vm.rateChanged(toNew: self.playRate, atTime: self.startTime)

    self.vm.crossedCompletionThreshold()
    self.vm.rateChanged(toNew: self.pauseRate, atTime: self.duration)

    self.seekToBeginning.assertValueCount(1)
  }

  func testTrackVideoPlayback() async {
    self.vm.configureWith(project: Project.template)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    XCTAssertEqual([], self.segmentTrackingClient.events)

    self.vm.playButtonTapped()
    self.vm.durationChanged(toNew: self.duration)

    self.vm.rateChanged(toNew: self.playRate, atTime: self.startTime)

    self.vm.rateChanged(toNew: self.pauseRate, atTime: self.halfwayTime)

    self.vm.rateChanged(toNew: self.playRate, atTime: self.halfwayTime)

    XCTAssertEqual([
      "Video Playback Started",
      "Video Playback Started"
    ], self.segmentTrackingClient.events)
    XCTAssertEqual("project", self.segmentTrackingClient.properties.last?["context_page"] as? String)
    XCTAssertEqual(100, self.segmentTrackingClient.properties.last?["video_length"] as? Int)
    XCTAssertEqual(50, self.segmentTrackingClient.properties.last?["video_position"] as? Int)

    self.vm.crossedCompletionThreshold()

    self.vm.crossedCompletionThreshold()

    self.vm.rateChanged(toNew: self.pauseRate, atTime: self.duration)
    self.seekToBeginning.assertValueCount(1)

    // Play video again.
    self.vm.playButtonTapped()
    self.vm.rateChanged(toNew: self.playRate, atTime: self.startTime)

    self.pauseVideo.assertDidNotEmitValue("Video not paused by view navigation.")

    XCTAssertEqual([
      "Video Playback Started",
      "Video Playback Started",
      "Video Playback Started"
    ], self.segmentTrackingClient.events)
    XCTAssertEqual("project", self.segmentTrackingClient.properties.last?["context_page"] as? String)
    XCTAssertEqual(100, self.segmentTrackingClient.properties.last?["video_length"] as? Int)
    XCTAssertEqual(0, self.segmentTrackingClient.properties.last?["video_position"] as? Int)
  }

  func testTrackVideoCompletionViaScrubbing() async {
    self.vm.configureWith(project: Project.template)
    self.vm.viewDidLoad()
    self.vm.viewDidAppear()

    self.vm.playButtonTapped()
    self.vm.durationChanged(toNew: self.duration)

    self.vm.rateChanged(toNew: self.playRate, atTime: self.startTime)

    // Scrub video through to completion.
    self.vm.rateChanged(toNew: self.pauseRate, atTime: self.halfwayTime)
    self.vm.rateChanged(toNew: self.playRate, atTime: self.completedThreshold)
  }

  func testViewTransition() async {
    self.vm.configureWith(project: Project.template)

    self.opacityForViews.assertValueCount(0)

    self.vm.viewDidLoad()

    self.opacityForViews.assertValues([0.0])

    self.vm.viewDidAppear()

    self.opacityForViews.assertValues([0.0, 1.0], "Fade in controls after view appears.")
  }
}

final class VideoRecorder<Value> {
  var values: [Value] = []
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, message, file: file, line: line)
  }
}
private extension VideoRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
