# Platform callback and concurrency audit

Author: Matthew Thomas. Recorded 29 October 2026.
Baseline: c8c5f0747429b65e0d1ea5d1d0b0392dbf333dc6. Migration remains in progress.

## Scope and method

Source review covers Library/Sources/Library, Kickstarter-iOS,
Kickstarter-Framework/Sources/Kickstarter-Framework and KsApi/Sources/KsApi.
Searches covered DispatchQueue, OperationQueue, DispatchGroup, DispatchSemaphore,
Task.detached, URLSession task creation, permission/settings callbacks, remote
configuration, AVAsset loading, player observers and continuations. Test/support,
third-party and generated code are distinguished from active application paths.
Text matching is a starting inventory, not exhaustive proof of callback safety.

The primitive scan matched **40 lines in 25 files**. None matched the Feature
implementation directory. That does not make every Feature concurrency-clean:
complete compiler diagnostics also expose non-Sendable transfer boundaries.

## Remaining owned-operation work

| Area | Evidence and risk | Required outcome |
| --- | --- | --- |
| Email-link redirect — implemented 29 October | AppLifecycleFeature now owns per-route reads; AppDelegateViewModel owns delivery. Native async transport stops at the first redirect and invalidates its session. | Local redirect/non-redirect/cancellation probe passed. Live email-service and visual navigation remain unverified; see latest ledger checkpoint. |
| Root profile avatar — implemented 29 October | ProfileFeature owns shared reads and session/URL validation; RootViewModel owns delivery; an actor handles disk cache and native async transport. | Cache-key compatibility and race regressions are recorded in the latest ledger. Populated-avatar visual/device parity remains unverified. |
| Notification permissions and onboarding | PushRegistration register/settings plus OnboardingView settings/ATT callbacks mutate registration/navigation after callback delivery. | Preserve admitted permission prompt semantics; own and await requests, share equivalent pending work, prevent obsolete onboarding advancement. Keep public demo restrictions. |
| Remote configuration | AppDelegate.fetchAndActivateRemoteConfig and live-update listener remain SDK callbacks. | Retain listener lifetime; bridge activation safely, coalesce appropriate refreshes and deliver the existing notification on its owner. |
| Project-page media preparation | prepareToPlayAudioVideoURL mutates cachedImage from an image callback while AVAsset loads independently; status subscription is locally retained and has no failure/release completion. | Await asset properties with native AVFoundation loading, explicitly own readiness/image lifetime, reject obsolete playback and complete failure paths. Preserve timing/thumbnail fallback intentionally. |
| Video player and audio | VideoFeedVideoPlayer has two 3-second timers and seek callbacks; audio KVO/reset scheduling exists in both Library and framework implementations. | Own/cancel timeout and seek work on reuse/stop; enforce actor isolation, preserve recovery and hardware-switch behavior. Audit the production implementation separately from its similar Library test type. |
| UI timers | Toast, link-copy share sheet, message banner and delayed push alert use unowned delayed blocks. | Bind dismissal/presentation to the current message/screen identity. Preserve VoiceOver duration, animation and existing delays. |

## Classification of all primitive-matching files

Paths below are relative to the repository. Counts refer to matching lines, not operations.

| File or location | Lines | Classification / next action |
| --- | ---: | --- |
| Kickstarter-iOS/AppDelegate.swift | 1 | Delayed permission alert; own presentation lifetime. Redirect/config callbacks above do not match queue syntax. |
| KsApi/AsyncApolloClient.swift | 2 | Legacy generic async bridge ignores cancellation; now no application call sites found for generic async Service.fetch after examples migrated. Verify all consumers before removing or hardening compatibility API. Queue parameter itself is an SDK requirement. |
| KsApi/MockService.swift | 1 | Legacy Combine mock delay; not a live request. Keep while compatibility tests/consumers require it. |
| Framework/Library/UIImageView+URL.swift | 2 | AlamofireImage progress queue is a UI SDK boundary. Preserve cache/filter/transition and assess cancellation per consumer. |
| Library/VideoFeedAudioController.swift | 1 | Reset-flag scheduling in testable duplicate; audit parity with actual framework controller. |
| Library/UIPageViewController+ThreadSafety.swift | 1 | Synchronous main-queue compatibility helper; audit callers before replacing with MainActor contract. |
| PPOProjectCardViewModel.swift | 1 | Retained Combine debounce; upstream Feature owns the write. Preserve latest-toggle semantics; inspect subscription cycle/lifetime. |
| DiscoveryPostcardCell.swift | 1 | Next-layout shadow paths, weak cell capture; UIKit timing boundary. |
| DiscoveryPageViewController.swift | 2 | Deferred refresh animation and table reload; UIKit layout timing, not network work. |
| OnboardingView.swift | 2 | Permission/ATT callback delivery; owned operation work above. |
| Library/String+SimpleHTML.swift | 1 | Synchronous HTML parser main-thread requirement; actor contract and callers need review. Do not replace it with a Task returning later. |
| Library/PushRegistration.swift | 1 | Permission callback then registration; owned operation work above. |
| VideoFeedToastContainerView.swift | 1 | Auto-dismiss timer; cancel/restart for current message. |
| PledgeExpandableRewardsHeaderViewController.swift | 1 | Deferred layout/animation; preserve layout ordering. |
| Framework/VideoFeedAudioController.swift | 2 | KVO delivery and reset-flag turn; explicit controller isolation/lifetime required. |
| VideoFeedViewController.swift | 8 | Observation re-arming, collection reload/activation and session UI updates; next-turn timing is intentional in several sites, verify visible-cell/lifetime guards. |
| Library/UIRefreshControl+StartRefreshing.swift | 1 | 10ms layout workaround; preserve behavior pending visual validation. |
| VideoFeedVideoPlayer.swift | 3 | Recovery/load timers and seek completion; replace unowned timers, guard current item. |
| VideoFeedShareSheetView.swift | 1 | Delayed dismissal after copy; screen-owned timer. |
| CommentsViewController.swift | 1 | Table footer layout pass; UIKit scheduling boundary. |
| MessageBannerView.swift | 1 | VoiceOver-sensitive dismissal; current banner identity required. |
| Library/Reachability.swift | 2 | SystemConfiguration requires callback queue. Existing local SCNetworkReachability reference lifetime needs explicit ownership review; replacing its network semantics blindly is not a migration. |
| ReportProjectCell.swift | 1 | Deferred hosting-view setup; reuse/ordering review. |
| VideoViewController.swift | 1 | AVPlayer boundary observer requires queue; verify observer-token removal and item identity. |
| ProjectPageViewController.swift | 1 | Media readiness Combine subscription; active operation needs replacement, as above. |

## Callback mechanisms that can legitimately remain

Apple delegates, UIKit completion handlers, AVPlayer/KVO observers and Apollo,
AlamofireImage, Stripe, social-login and remote-config SDK callbacks may remain at
platform boundaries. They must have documented executor, cancellation, identity and
terminal-completion rules. Presence of a callback is not itself a defect. The
existing cancellation-aware Apollo bridge uses a narrow lock around terminal state;
its lock is not a substitute for Feature isolation. The DiscussionFeature's checked
continuation is admission control for bounded writes, not a legacy network wrapper.
The four previously documented cold advertising producers remain inactive.

## Complete compiler diagnostics

An app build in **Swift 5 language mode**, using Apple Swift 6.2.3 and
`-strict-concurrency=complete -warn-concurrency`, succeeded. The baseline log contains
**3,726 unique matching concurrency diagnostics** (file, line, column, message):

| Module | Unique diagnostics |
| --- | ---: |
| Kickstarter-Framework | 1,659 |
| Library | 901 |
| KsApi | 656 |
| Generated GraphAPI | 379 |
| KDS | 126 |
| Kickstarter-iOS | 3 |
| RichPushNotifications | 2 |

This is a scoped diagnostic baseline, not 3,726 proven races or a Swift 6 build.
It includes actor annotations, shared globals/static values, generated Apollo
metadata and non-Sendable task/service results. Migrated Feature ownership alone
has not resolved these compiler boundaries. Do not suppress the audit with broad
unchecked Sendable declarations or by weakening the diagnostic setting.

The first correction keeps the example's Apollo payload in a MainActor-owned result
slot, with Task<Void, Never> used solely for completion. Discovery entry points now
state their MainActor contract, and the native REST response helper explicitly
inherits caller isolation (`nonisolated(nonsending)`, supported by the pinned compiler).
URLSession still suspends for network I/O. Follow-up compile emitted no diagnostic
for DeveloperExamplesFeature. Other first-party/generated warnings remain.

Local evidence: sibling Migration Evidence/kickstarter-platform-audit. Raw compiler
logs stay in /private/tmp. Repository build settings and Swift language mode were
not silently changed. Final validation still requires diagnostic remediation,
broader regression, reference-device snapshots, simulator/device journeys and
explicit live-service limits. No migration finish time is recorded yet.

## Simulator integration and remaining visual gates

Inspection of the public demo on iPhone Air / iOS 26.2 found the pagination
sentinel stalled after six rows. Its appearance preceded the initial page. The
shared list now owns its waiter with `.task(id: data.count)` and the example
drives sentinel presence from its actual loading/cursor state. Both consumers'
Features coalesce equivalent requests. The demo then advanced to eighteen rows;
terminal state is unit-tested, but terminal scrolling and refresh gestures were
not verified visually. Rich-text loading reaches the existing error presentation
because the demo lacks that query fixture. Populated rendering is still unverified.

The snapshot suites require iPad mini / iOS 18.6, absent from the installed runtime
inventory. Do not label iOS 26.2 smoke checks as reference snapshot parity. Physical
device and live-service checks remain open.
