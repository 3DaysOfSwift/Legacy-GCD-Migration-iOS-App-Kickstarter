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

## Latest refresh: Stripe confirmation lifetimes — 29 October 2026

StripeConfirmationOperation owns observation of four native setup/payment confirmations.
The SDK retains native processing; one async stream accepts checked status/error values,
not SDK intents. Controller departure/release cancels observation. Session-generation
checks reject obsolete outcomes; duplicate callbacks and equivalent starts deliver once.
Conflicting starts fail explicitly without replacing the active native operation.

Post-campaign Apple Pay retains one context/secret/session and clears ownership before
completion delivery. SDK source routes these delegates through main-thread API/PassKit
completion. Extract ObjectIdentifier, payment-method string and checked status before
MainActor.assumeIsolated; invoke the required SDK completion on its original executor.
STPAuthenticationContext presenter access returns the controller without mutable UI
access. Its PPO dismissal hook follows UIKit/Safari's synchronous main-thread contract.

Final 1,930 selected tests and normal/complete-check builds passed. Helper and
post-campaign controller have zero matching concurrency diagnostics. Pledge retains
23 and PPO three unrelated matching diagnostics. Incremental total 3,030 is not a
comparable full baseline. Primitive inventory remains eight lines/five files.
PaymentSheet flows and older PKPayment token callbacks remain open, along with other
provider graphs and final visual/device/live-operation validation. See sibling
`Migration Evidence/kickstarter-stripe-lifetimes/contract.md` for source evidence.

## Latest refresh: checkout callbacks and mapped payment transport — 29 October 2026

Four checkout/login session observers use the owned synchronous MainActor adapter.
Checkout UI delegates, banners, haptics and video-feed presentation callbacks now
state UI isolation. Post-campaign checkout retains two Stripe SDK conformance
warnings; inspect their native callback contracts and lifetime before bridging them.

Payment cards/remove/store/setup/intent operations convert Apollo selection sets on
the callback executor, returning only checked Sendable snapshots. No generated type
is broadly declared Sendable. Legacy generic callers remain supported through the
original fetch entry point and retain their non-Sendable transfer diagnostics.
The existing lock-protected token/continuation holder remains narrowly unchecked;
this checkpoint adds no unchecked conformance or suppression.

Final selected regression: 1,923 passed; app and complete-check builds succeeded.
Recompiled payment service/Feature emit no matching concurrency warnings. Inventory
remains eight lines/five files (syntax only; shorthand SDK queue arguments are not
counted by this regex). Incremental diagnostics: 3,034, not a comparable full count.
No new visual/device/live-service validation is claimed. See sibling evidence.

## Latest refresh: UIKit and response-value contracts — 29 October 2026

ValueCell/data-source ownership, UI factories and overlay/processing protocols now
state MainActor. Nib entry points use UIKit's main-thread contract. Discovery cards
retain MainActorNotificationObservation for audited main-actor publishers; delivery
is synchronous and complete heterogeneous payloads never cross an actor boundary.
Four new tests cover ordering, cancellation and release (including another actor).
Checkout deinit transfers only its overlay to bounded main-actor cleanup.
Fourteen checked Sendable conformances cover seven value-only response/model files.

1,906 selected tests passed; app build and complete-check diagnostic build succeeded.
Incremental diagnostics remain and are not a full baseline. See current evidence
`../Migration Evidence/kickstarter-uikit-isolation/compiler-diagnostics.json`.
No new visual/device or live-service validation is claimed. Primitive scan: 8/5.

Compatibility clarification: AsyncApolloClient is constructed by public generic
Service.fetch(query:) async, also reachable through default compatibility paths and
fixtures. Concrete migrated Service operations use their native implementations;
no migrated application caller of the generic path was found in this audit. Retain
it pending explicit compatibility/cancellation review, not as "unused" dead code.

## Latest refresh: layout/HTML and compiler contracts — 29 October 2026

The same scoped scan now matches **8 lines in 5 files**:

| Current file | Matches | Disposition |
| --- | ---: | --- |
| KsApi/AsyncApolloClient.swift | 2 | Retained generic compatibility bridge; queue is an SDK argument, but cancellation/unchecked conformance remain legacy audit items. No active application consumers were identified in the prior pass. |
| KsApi/MockService.swift | 1 | Combine delay in mock compatibility code; retain while legacy tests/consumers require it. |
| Framework/Library/UIImageView+URL.swift | 2 | Required AlamofireImage progress queues; per-view receipts, cancellation and UI binding reviewed. |
| Library/Reachability.swift | 2 | SDK callback queue registration/unregistration, retained native context and Feature-owned async consumer. |
| PPOProjectCardViewModel.swift | 1 | Retained 300ms Combine debounce; subscription is owned/cancelled on release. Weak sink fixes retain cycle; writes already belong to Feature. |

Discovery refresh/reload, comments footer, reward-header height and postcard shadows
now use current UIKit layout passes. Report-cell reconfiguration updates one retained
host. DeferredRefreshControl owns/cancels the existing 10ms timer. HTML parsing stays
synchronous on MainActor; UI-only Activity callers now carry that contract. Styling
helpers in the affected files are main-actor-isolated without redesign.

Checked Sendable conformances cover reviewed value-only User/Location nested fields,
ProjectNotification and email-verification envelopes. Complete checking caught an
avatar-loader default-isolation error, corrected with explicit MainActor closure
ownership/default construction. Two subsequent complete-checking builds succeeded.
The final incremental diagnostic run emitted 2,349 unique matching warnings in its
recompiled modules only; it is not a new full baseline. UIKit protocols/lifecycle
hooks, global lens/style state, generated metadata and remaining task-result/provider
transfers still need work. No unchecked conformance or suppression was added.

Final selected tests: 1,787 passed, zero failures/skips; app build passed. Limited demo
sorting/scrolling smoke checks passed. Reference-device snapshots, physical-device and
live-operation validation remain open. Historical inventories below are provenance.

## Latest refresh: project-video observers and images — 29 October 2026

The same scoped primitive scan matches **16 lines in 12 files**. VideoViewController's
queue argument moves into the native adapter as `.main`; this count reduction is not
removal of the required AVPlayer callback mechanism. A retained native source owns
KVO/boundary tokens, emits immutable events to one controller-owned MainActor consumer,
and rejects obsolete boundary generations. Native local-asset playback and release
are tested. Remote video, visual parity and physical-device playback remain open.

ProjectMediaFeature owns native async Kingfisher campaign-image reads per page/URL.
Slot/page identity and datasource source/bounds checks suppress stale delivery.
Global image cancellation is removed. Same WebP/cache behavior is retained.
AlamofireImage's 20 direct helper calls and six reactive bindings were reviewed:
its weak image-view capture, URL/receipt check and per-receipt cancellation remain.
Helpers/bindings state MainActor ownership; required SDK progress queues stay.
The facepile consumer creates fresh views and cancels each when clearing them.
Dependency source review is recorded with locations in the checkpoint case study.

Final integrated verification: 1,758 selected tests and app build passed. Demo launch
showed populated Explore artwork. See the latest ledger and sibling evidence folder.
Historical counts below remain provenance, not current defect totals.

## Latest refresh: permission alerts and connectivity — 29 October 2026

The same primitive regex now matches **17 lines in 13 files**. AppDelegate's delayed
permission block is replaced by owned cancellation/replacement and visible-presenter
checks. Both alert decision/presentation read the named context key. Reachability's
native handle/C context is retained, unregistered on release and bridged through an
AsyncStream to AppLifecycleFeature; its callback queue remains an SDK requirement.
The page helper's six call sites already execute on MainActor, so its blocking queue
hop is removed while synchronous native navigation/completion are retained.
Recounting bf428244f with the exact scoped regex gives 19 lines in 15 files;
the earlier stated 18 was an undercount. The comparable change is 19 to 17,
not 18 to 17. Counts include SDK function names and are not a defect count.
Final checkpoint: 1,748 selected tests and app build passed; populated demo launch
observed on iPhone Air/iOS 26.2. Historical scan counts below remain as provenance.

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
| UI timers — implemented | Toast, copy-link and banner use view-owned tasks. Permission alert has a retained settling task, replacement/cancellation and screen-lifetime guards. | Controlled presentation tests passed; real permission prompts, gestures/VoiceOver/device presentation remain open. |

## Classification of all primitive-matching files

Paths below are relative to the repository. Counts refer to matching lines, not operations.

| File or location | Lines | Classification / next action |
| --- | ---: | --- |
| Kickstarter-iOS/AppDelegate.swift | 1 | Implemented: owned cancellable delay; no queue matches remain. Redirect/config callbacks above do not match queue syntax. |
| KsApi/AsyncApolloClient.swift | 2 | Legacy generic async bridge ignores cancellation; now no application call sites found for generic async Service.fetch after examples migrated. Verify all consumers before removing or hardening compatibility API. Queue parameter itself is an SDK requirement. |
| KsApi/MockService.swift | 1 | Legacy Combine mock delay; not a live request. Keep while compatibility tests/consumers require it. |
| Framework/Library/UIImageView+URL.swift | 2 | AlamofireImage progress queue is a UI SDK boundary. Reviewed: preserve cache/filter/transition; per-view receipt/URL checks, weak capture and cancellation. MainActor helper/binding contract. |
| Library/VideoFeedAudioController.swift | 1 | Implemented: production audio type consolidated; owned stream/reset tasks. |
| Library/UIPageViewController+ThreadSafety.swift | 1 | Implemented: all six callers reviewed; explicit MainActor synchronous forwarding, no queue hop. |
| PPOProjectCardViewModel.swift | 1 | Retained native Combine debounce; upstream Feature owns writes. Weak sink breaks cycle; release suppression is tested. |
| DiscoveryPostcardCell.swift | 1 | Implemented: current descendant geometry in layoutSubviews; no deferred closure. |
| DiscoveryPageViewController.swift | 2 | Implemented: latest pending state applied in UIKit layout callback; animation policy retained. |
| OnboardingView.swift | 2 at baseline | Replaced by appearance-owned ViewModel delivery; no permission callbacks remain in View. |
| Library/String+SimpleHTML.swift | 1 | Implemented: synchronous MainActor parser and UI-only caller contracts; no blocking queue hop. |
| Library/PushRegistration.swift | 1 at baseline | Native async authorization/settings, Feature-owned admitted prompt and cancellable compatibility observer. |
| VideoFeedToastContainerView.swift | 1 | Implemented: view-owned task retains change-triggered policy. |
| PledgeExpandableRewardsHeaderViewController.swift | 1 | Implemented: row measurement in layout callback and current expansion state; child-controller geometry tested. |
| Framework/VideoFeedAudioController.swift | 2 | Deleted duplicate; shared production Library controller now tested. |
| VideoFeedViewController.swift | 8 | Current checkpoint: one observation loop; owned deferred activation and main-queue notification boundaries. |
| Library/UIRefreshControl+StartRefreshing.swift | 1 | Replaced by DeferredRefreshControl: same delay, owned sharing/cancellation and stale-start rejection. |
| VideoFeedVideoPlayer.swift | 3 at baseline | Replaced by retained cancellation-aware timers/native seek; per-item observation guards. Populated playback validation remains open. |
| VideoFeedShareSheetView.swift | 1 | Implemented: SwiftUI-owned confirmation timer. |
| CommentsViewController.swift | 1 | Implemented: UIKit layout callback resizes current footer. |
| MessageBannerView.swift | 1 | Implemented: identity-keyed task; hosted replacement/removal regressions. |
| Library/Reachability.swift | 2 | Implemented: native handle/context retained and unregistered on release; callback queue yields immutable values to Feature-owned consumer. Retained SDK semantics/deprecation, no NWPathMonitor substitution. |
| ReportProjectCell.swift | 1 | Implemented: one retained host updated synchronously; reuse and accessibility tested. |
| VideoViewController.swift | 1 | Implemented: native source owns KVO/boundary tokens; async consumer validates boundary identity, cancellation and release. Queue remains a platform requirement. |
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
