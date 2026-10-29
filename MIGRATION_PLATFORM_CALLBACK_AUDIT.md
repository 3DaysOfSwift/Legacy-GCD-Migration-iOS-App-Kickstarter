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

## 29 October refresh after media/UI timer and feed-observer work

The current worktree scan matches **18 lines in 15 files**, using
`DispatchQueue|OperationQueue|DispatchGroup|DispatchSemaphore|Task.detached`
across the four first-party roots above. This differs from the original broader
searches; retain the original 40-line baseline as historical evidence, not a
like-for-like percentage improvement. VideoFeed has no matches for these primitives.
Project media preparation, consolidated production audio, player cleanup and the
three transient-message timers have verified ledger checkpoints. The feed observer
now has one owned event loop and re-arms only the changed output; activation has a
cancellable owner plus visibility/background/share/scroll guards. Its current test
outcome is recorded in the latest ledger checkpoint.

The table below retains baseline line counts for traceability. Completed rows are
marked; remaining queue arguments still require consumer/SDK contract review.

## Remaining owned-operation work

| Area | Evidence and risk | Required outcome |
| --- | --- | --- |
| Email-link redirect — implemented 29 October | AppLifecycleFeature now owns per-route reads; AppDelegateViewModel owns delivery. Native async transport stops at the first redirect and invalidates its session. | Local redirect/non-redirect/cancellation probe passed. Live email-service and visual navigation remain unverified; see latest ledger checkpoint. |
| Root profile avatar — implemented 29 October | ProfileFeature owns shared reads and session/URL validation; RootViewModel owns delivery; an actor handles disk cache and native async transport. | Cache-key compatibility and race regressions are recorded in the latest ledger. Populated-avatar visual/device parity remains unverified. |
| Notification permissions and onboarding — implemented 29 October | AppLifecycleFeature owns admitted prompts; native settings reads and appearance-owned onboarding observers reject obsolete completion. | 248 selected regressions/app build passed; actual system-prompt/device behavior remains open. |
| Remote configuration — implemented 29 October | Native Firebase async activation, per-client shared operation and replacement guards; listener retained/removed on reconfiguration. | Log-only listener behavior preserved. SDK cache changes cannot be retracted; live Firebase validation remains open. |
| Project-page media — implemented | Feature-owned native loading, cancellable KVO readiness and optional WebP thumbnail read; per-page/slot identity. | 377 selected tests/app build recorded; remote media and device parity remain open. |
| Video player and audio — implemented | One production audio controller owns callback stream/reset tasks; player owns seeking/timers/observations. Synchronous release regression covers the observed isolated-deinit toolchain crash. | Physical-device routing, populated playback and visual parity remain open. |
| UI timers — three implemented; push alert remains | Toast, copy-link and banner use view-owned tasks; hosted banner replacement/removal tests pass. AppDelegate permission alert still has a delayed block. | Finish alert lifetime and validate gestures/VoiceOver/device presentation. |

## Classification of all primitive-matching files

Paths below are relative to the repository. Counts refer to matching lines, not operations.

| File or location | Lines | Classification / next action |
| --- | ---: | --- |
| Kickstarter-iOS/AppDelegate.swift | 1 | Delayed permission alert; own presentation lifetime. Redirect/config callbacks above do not match queue syntax. |
| KsApi/AsyncApolloClient.swift | 2 | Legacy generic async bridge ignores cancellation; now no application call sites found for generic async Service.fetch after examples migrated. Verify all consumers before removing or hardening compatibility API. Queue parameter itself is an SDK requirement. |
| KsApi/MockService.swift | 1 | Legacy Combine mock delay; not a live request. Keep while compatibility tests/consumers require it. |
| Framework/Library/UIImageView+URL.swift | 2 | AlamofireImage progress queue is a UI SDK boundary. Preserve cache/filter/transition and assess cancellation per consumer. |
| Library/VideoFeedAudioController.swift | 1 | Implemented: production audio type consolidated; owned stream/reset tasks. |
| Library/UIPageViewController+ThreadSafety.swift | 1 | Synchronous main-queue compatibility helper; audit callers before replacing with MainActor contract. |
| PPOProjectCardViewModel.swift | 1 | Retained Combine debounce; upstream Feature owns the write. Preserve latest-toggle semantics; inspect subscription cycle/lifetime. |
| DiscoveryPostcardCell.swift | 1 | Next-layout shadow paths, weak cell capture; UIKit timing boundary. |
| DiscoveryPageViewController.swift | 2 | Deferred refresh animation and table reload; UIKit layout timing, not network work. |
| OnboardingView.swift | 2 at baseline | Replaced by appearance-owned ViewModel delivery; no permission callbacks remain in View. |
| Library/String+SimpleHTML.swift | 1 | Synchronous HTML parser main-thread requirement; actor contract and callers need review. Do not replace it with a Task returning later. |
| Library/PushRegistration.swift | 1 at baseline | Native async authorization/settings, Feature-owned admitted prompt and cancellable compatibility observer. |
| VideoFeedToastContainerView.swift | 1 | Implemented: view-owned task retains change-triggered policy. |
| PledgeExpandableRewardsHeaderViewController.swift | 1 | Deferred layout/animation; preserve layout ordering. |
| Framework/VideoFeedAudioController.swift | 2 | Deleted duplicate; shared production Library controller now tested. |
| VideoFeedViewController.swift | 8 | Current checkpoint: one observation loop; owned deferred activation and main-queue notification boundaries. |
| Library/UIRefreshControl+StartRefreshing.swift | 1 | 10ms layout workaround; preserve behavior pending visual validation. |
| VideoFeedVideoPlayer.swift | 3 at baseline | Replaced by retained cancellation-aware timers/native seek; per-item observation guards. Populated playback validation remains open. |
| VideoFeedShareSheetView.swift | 1 | Implemented: SwiftUI-owned confirmation timer. |
| CommentsViewController.swift | 1 | Table footer layout pass; UIKit scheduling boundary. |
| MessageBannerView.swift | 1 | Implemented: identity-keyed task; hosted replacement/removal regressions. |
| Library/Reachability.swift | 2 | SystemConfiguration requires callback queue. Existing local SCNetworkReachability reference lifetime needs explicit ownership review; replacing its network semantics blindly is not a migration. |
| ReportProjectCell.swift | 1 | Deferred hosting-view setup; reuse/ordering review. |
| VideoViewController.swift | 1 | AVPlayer boundary observer requires queue; verify observer-token removal and item identity. |
| ProjectPageViewController.swift | 1 | Implemented: Feature-owned native media preparation; stale rows rejected. |

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
