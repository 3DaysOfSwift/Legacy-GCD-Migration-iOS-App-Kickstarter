# CFA migration ledger

Author: Matthew Thomas. Updated 29 October 2026.

## Required final migration report

Matthew Thomas requested transparent timing, model attribution and outcome
statistics on 28 October 2026. This is part of migration completion.

Keep the reporting data in sibling `Migration Evidence/kickstarter-report-metrics.json`.
The final report must contain:

- Start and finish dates/times with timezone and evidence for each. Separate
  repository/demo preparation, architecture implementation and final validation.
  An earliest commit is a verified checkpoint, not proof of the actual start.
- Calendar elapsed duration between explicitly named boundaries. Report active
  agent time, human effort, waiting and interruptions separately only when measured;
  never equate calendar elapsed time with continuous model execution.
- Model display name, reasoning setting, tool/client and any documented changes
  by phase. Exact backend model IDs, token totals and costs require reliable
  metadata; do not infer them from UI labels or invent missing usage.
- Baseline/final revision, feature coverage, remaining exceptions, migration
  commits and changed files/lines, separating production, tests, docs and fixtures.
  Diff volume is descriptive, not a quality or productivity score.
- Comparable before/after build and test outcomes, unique tests in the final run,
  added regression scenarios, failures/rework and warnings. Do not sum repeated
  test runs as unique coverage or compare differently scoped suites as a gain.
- Human interventions, environment blockers and recoveries, plus measured waiting
  when available. Include unsuccessful attempts as well as successful checkpoints.
- Behavior/visual/device/live-service and concurrency validation, with explicit
  limits. Explain which findings are backed by mocks versus real integration.

Current evidence anchors: baseline commit ecd4da688 at 2026-10-26T14:18:04+07:00;
Search baseline commit 192fa9148 at 2026-10-26T16:42:07+07:00.
Actual kickoff time is not established; preparation predates the first anchor.
User-supplied screenshots show GPT-6 Astra with High reasoning, but do not prove
the model used for every phase. Finish time and final duration remain unset.

Record finish only after the agreed app-wide completion/validation gates are
resolved and the final report explicitly states any accepted limitations.
A successful feature checkpoint does not finish the app-wide migration.
Do not publish the report or upload logs/usage data without authorization.

## Latest verified checkpoint

### View-owned banner, toast and copy-link delays — 29 October 2026

Message-banner dismissal is a SwiftUI task keyed by banner identity; a replacement
cannot be dismissed by its predecessor. Removal cancels the task. Existing four-
second/default and ten-second/VoiceOver policies remain. Save-error toasts retain
change-triggered three-second dismissal, including the original initial-content
behavior. Copy-link confirmation retains its 2.5-second delay. Both now cancel on
view removal. No text, layout, colors or sharing destinations were changed.

Two new hosted SwiftUI runtime tests passed: replacement survives the old deadline
and still auto-dismisses at its own deadline; removing the view leaves the former
binding untouched. No failures/skips. App build succeeded with zero errors and 381
reported warnings on this framework recompilation, including existing design-system
deprecations, preview warnings and generated asset-name collisions. This is not
comparable to the preceding incremental build's two warnings. One test compilation
attempt incorrectly tried to override a read-only accessibility environment value;
the tests now assert the actual simulator setting instead. No runtime test failures.

Results: /private/tmp/kickstarter-ui-timers-tests-repair.xcresult and
/private/tmp/kickstarter-ui-timers-build.xcresult. Prior media checkpoint has 377
passing selected tests; those suites were not redundantly rerun for these three
view-only timer changes. Toast/share-sheet gestures, VoiceOver, visual parity and
physical-device behavior remain unverified. Snapshot guards are unchanged.
Evidence: sibling Migration Evidence/kickstarter-ui-timers.

Next: video-feed observation/rebinding and deferred UIKit activation, then remaining
platform callbacks and broader app-wide validation. Migration remains in progress;
visual/device and live-operation gates remain open.

### Previous verified checkpoint

### Project-page media preparation and audio callbacks — 29 October 2026

ProjectMediaFeature owns native asset preparation per page/slot. Equivalent pending
requests share; replacement/exit cancels work and rejects late results. Optional
WebP thumbnails retain existing cache behavior without delaying playback. Readiness
uses a cancellable KVO stream and reads the current status because the observed
AVFoundation notifications supplied nil typed change payloads. Changed/removed rows
reject old media results. The existing player cells and audio policy are preserved.

The duplicated audio controller is consolidated into the production Library type.
Volume/mute callbacks feed an owned event stream; observer replacement, dismissal
and release terminate it. Reset tasks check generation and dismissal. Synchronous
release tests exposed a crash in the toolchain's isolated-deinit runtime path; audio
and video-player cleanup now cancel tasks and perform finite resource cleanup by
value. Player task/observer bookkeeping is excluded from UI observation.

**129 Library + 248 framework = 377 selected tests passed**, zero failures/skips;
**12 new regressions** include local PCM readiness, missing-media failure, cancellation,
sharing/retry, stale rows, audio rebinding/reset/release and synchronous player release.
App build passed with zero errors/two existing warnings. Library/build evidence:
/private/tmp/kickstarter-media-preparation-audio.ZwB1cO; final framework evidence:
/private/tmp/kickstarter-media-audio-framework-repair/update-detail.xcresult.

Three compile attempts failed and were repaired. Four runtime runs failed: the first
had seven isolated-deinit crashes and one readiness timeout, two diagnostic runs
retained the timeout, and a framework run exposed an invalid newly added row fixture.
The final framework rerun changed only that test fixture; prior Library/build results
remain applicable. No human terminal commands were required. Evidence: sibling
Migration Evidence/kickstarter-media-preparation-audio. Physical audio behavior,
remote media, visual/device parity and live operations remain unverified.

Next: remaining UI timers/platform callbacks and app-wide concurrency/regression
validation. Migration remains in progress.

### Previous verified checkpoint

### Video-feed playback lifetimes — 29 October 2026

VideoFeedVideoPlayer and its playback UI state now have explicit MainActor ownership.
Startup/recovery timers are retained cancellable Tasks; stop, replacement and release
invalidate them. Repeated stall notifications share the first three-second recovery
window. Failure remains once per item. Native async seek retains an owned waiter;
new seek, pause, stop and replacement suppress obsolete completion, preventing an
old loop/scrub from resuming a paused or reused item. Current seek failures still
reach the existing recovery UI. Progress observation is installed per item and
removed on stop/reuse; queued callbacks check item/generation identity.

**36 Library + 222 framework = 258 selected tests passed**, zero failures/skips;
**seven new regressions** cover seek supersession, pause/stop/release, stale recovery,
replacement and once-only failure with repeated stalls. App build passed with zero
errors/two existing warnings (Frameworks search path and Crashlytics outputs).
Results: /private/tmp/kickstarter-video-player-lifetime.v1YnLP. Evidence: sibling
Migration Evidence/kickstarter-video-player-lifetime.

Two earlier compile attempts exposed actor isolation gaps in playback state and
snapshot-test callers. Those callers are now MainActor-isolated. The nonvisual
playback-state suite opts out of reference-device requirements; the actual video
snapshot suite retains its guard and was compiled, not run. No runtime test failures
or human terminal commands. Controlled seek/sleep tests and synthetic notifications
do not verify populated playback, native seeking timing, decoder/network recovery,
physical-device audio or visual parity. Existing UI, watch counter semantics and
three-second policy are retained; invalid-duration seek completion is now async.

Next: project-page asset/thumbnail readiness, audio-session callbacks and remaining
UI timers, then broader app-wide concurrency/regression and visual/device checks.
Migration remains in progress; live operations remain unverified.

### Previous verified checkpoint

### Notification permissions, onboarding and remote configuration — 29 October 2026

AppLifecycleFeature owns admitted notification/ATT prompts. Equivalent pending
requests share; distinct notification option sets serialize. Grant registers for
remote notifications once per admitted request. Closing a screen stops its observer,
not a system prompt already displayed. Native notification settings reads and the
existing ATT wrapper preserve authorization and advertising-identifier side effects.
Onboarding now constructs its own ViewModel inline and owns subscriptions per
appearance; exit/advance invalidates pending completion and prevents late navigation.
Existing page content, analytics, login behavior and already-authorized behavior remain.

Remote configuration uses Firebase's native async activation. Same-client pending
refreshes share; replacement rejects old completion. AppDelegate retains the realtime
listener and removes it on reconfiguration. The listener remains log-only, preserving
existing behavior. SDK activation itself cannot be undone after cancellation;
obsolete application delivery is suppressed. Public-demo integration guards remain.

**40 Library + 208 framework = 248 selected tests passed**, zero failures/skips;
**seven new regressions** cover prompt sharing/order/observer cancellation, tracking
retry, remote-client replacement/failure/retry and onboarding exit/rebinding. App
build passed with zero errors and two existing warnings (missing Frameworks search
path and Crashlytics outputs). Result: /private/tmp/kickstarter-permission-config.3FDIUE.
Two earlier compilation attempts failed: method placement, then missing test-only
MockService import. Both corrected; no runtime test failures or human test commands.
Only two nonvisual onboarding suites opt out of the reference-simulator guard;
snapshot suites retain it. Evidence: sibling Migration Evidence/kickstarter-permission-config.

System prompt/device behavior and live Firebase activation remain unverified.
Next: media lifetimes, remaining platform callbacks and app-wide concurrency/regression
validation. Migration remains in progress; visual/device and live operations stay open.

### Previous verified checkpoint

### Root-tab avatar ownership — 29 October 2026

ProfileFeature owns shared avatar reads and validates session generation, account,
URL and operation identity before returning bytes. RootViewModel now depends on
ProfileFeature (which exposes its shared SessionFeature) and owns an awaitable image
waiter. Logout and tab rebuilding invalidate delivery; the controller rechecks its
current tab data before rendering. RootTabBarViewController no longer reads files
or starts URLSession tasks. ProfileAvatarStore serializes disk cache access on an
actor and uses native cancellable URLSession transport with session invalidation.

The existing hash-based cache filename, cache-first lookup, atomic best-effort write,
silent failure and image shaping/border helpers are retained. Cached images now
arrive asynchronously like downloads, after tab styling; a placeholder may briefly
appear on a cache hit. Canceling one UI waiter leaves shared cache fill intact;
logout/reset cancels the Feature read. No account mutation or live-service check.

**15 Library + 208 framework = 223 selected tests passed**, zero failures/skips;
**eight new regressions** cover session replacement, changed avatar URL, reset,
failure/retry, cache hit/write, logout and rebuilt tab index. App build passed:
zero errors/one warning reported in the final incremental build. Counts differ
from earlier checkpoints because the Library selection is now Profile-focused.
Results: /private/tmp/kickstarter-root-avatar.VE29mN. Evidence: sibling Migration
Evidence/kickstarter-root-avatar.

Two compile attempts failed in test setup: generated Task name collision, then a
controlled-request helper absent from the framework test target. Both corrected.
No runtime test failures or human terminal commands. Populated-avatar visual parity,
reference snapshots and physical-device validation remain open. Next: permission/
onboarding and remote-configuration ownership, media lifetimes and remaining
app-wide concurrency diagnostics. Migration remains in progress.

### Previous verified checkpoint

### Owned email-link redirects — 29 October 2026

AppDelegate no longer creates an unowned data task or receives URLSession redirects.
AppDelegateViewModel routes the intent to AppLifecycleFeature and owns its delivery
waiter. The Feature shares equivalent pending URLs and invalidates replaced routes,
session changes and resets. A newer ordinary navigation cancels the presentation
waiter synchronously, including requests not yet started. The stateless URLSession
delegate declines following; native async transport returns the first redirect's
Location and invalidates its session on all exits. Failures/no redirect stay silent.
No UI, navigation matching or persistence redesign.

**19 Library + 206 framework = 225 selected tests passed**, zero failures/skips,
including four new redirect cases. App build passed: zero errors/two existing
warnings. A separate native transport probe against a temporary loopback HTTP server
verified first-redirect resolution, no redirect following, ordinary-response nil and
cancellation. It did not contact the email service. Results:
/private/tmp/kickstarter-email-redirect.xzonfm. Evidence: sibling Migration
Evidence/kickstarter-email-redirect.

Two compile attempts failed before correction: capturing self before all ViewModel
outputs were initialized, then accessing actor-owned cleanup state from deinit.
No runtime test failures or human terminal commands. The final code retains cleanup
on its owner. Live email-service integration, rendered navigation, reference snapshots
and physical-device validation remain open. Next: root-tab avatar loading, then
permissions/configuration/media ownership and broader concurrency remediation.

### Previous verified checkpoint

### Platform audit and pagination integration — 29 October 2026

The platform callback audit is recorded in `MIGRATION_PLATFORM_CALLBACK_AUDIT.md`.
Complete concurrency diagnostics in Swift 5 mode expose unresolved isolation and
non-Sendable boundaries across first-party/generated code. The initial inventory
contains 3,726 unique matching diagnostics; this is not a proven race count or a
successful Swift 6 migration. DeveloperExamplesFeature's diagnosed transfers were
corrected by retaining Apollo payloads on MainActor and using completion-only tasks.
Discovery transport now explicitly preserves caller isolation. The follow-up
complete-checking compile emits no warning for this Feature; app-wide findings remain.

Simulator inspection caught an integration bug missed by command-level tests: the
pagination sentinel appeared before the first page and never retriggered. PaginatingList
now uses a row-owned task keyed by item count; the example exposes its real terminal
state instead of leaving pagination enabled forever. The demo progressed beyond six
to eighteen rows before the sentinel moved below the visible viewport. The final-page
spinner/no-extra-request contract has a new regression test. Full terminal scrolling
and pull-to-refresh have not been visually verified. Rich-text demo loading terminates
in the existing error UI because that query has no public-demo fixture; populated
rich-text rendering and navigation remain visually unverified.

After isolation changes, **1,639 selected tests passed** again (1,340 Library,
205 framework, 94 API), zero failures/skips. After the shared-list correction,
**38 Library + 206 framework = 244 targeted tests passed**, including one new
terminal-state regression; zero failures/skips. Both app builds passed with zero
errors/two existing warnings. These are overlapping runs, not 1,883 unique tests.
Results: /private/tmp/kickstarter-developer-examples.1XVMcS and
/private/tmp/kickstarter-platform-audit.cvcinu. Evidence is in sibling
Migration Evidence/kickstarter-platform-audit. No failed compile/test runs or human
terminal commands; one edit-script mismatch caused no source write and one redundant
unchanged diagnostic build. The visual inspection found the pagination defect above.

Reference snapshots require iPad mini / iOS 18.6; only iOS 26.2 is installed.
The reference-device guard was not bypassed. No physical-device, populated media,
account-write or payment completion is claimed. Migration remains in progress.

### Earlier checkpoint in this stage

### Beta pagination and rich-text examples — 29 October 2026

DeveloperExamplesFeature now owns both developer screens' requests, pagination and
rich-text list caching. ViewModels bind observed snapshots, retain lookup lifetime,
and never access services. Both Views own their ViewModel inline. Native discovery
and cancellation-aware Apollo endpoints replace the examples' Combine/generic async
requests. Initial versus refresh parameters, append semantics, nullable responses,
status text, error output and cached return navigation are preserved. Empty next
pages no longer wait indefinitely; editing a submitted slug or closing a screen
rejects late navigation and errors.

**1,340 Library + 205 framework + 94 API = 1,639 selected tests passed**, zero
failures/skips. There are **20 new regression cases**; the increase also includes
17 existing Paginator cases newly selected. Focused run: 31 passed. App build:
zero errors/two existing warnings. No failed compile/test attempt or human terminal
command in this checkpoint. Results: /private/tmp/kickstarter-developer-examples.7P18BF.
Evidence: sibling Migration Evidence/kickstarter-developer-examples.

### Remaining implementation and validation

1. Platform callbacks: the audit found remaining owned-operation work in email-link
   redirects, root-tab avatar loading, notification permissions/onboarding, remote
   configuration and project media preparation. Video timeouts and UI scheduling
   also require lifetime review. SDK-mandated callback queues are separate from
   business-task migration; primitive text counts are not defect totals.
2. Complete concurrency diagnostics and broader regression, then reference-device
   snapshots, simulator/physical-device journeys and live-service gates. Keep the
   four inactive advertising producers inactive. No live payments or account writes
   have been verified.
3. Final evidence-backed report: start/finish boundaries, model attribution, attempts,
   human intervention and validation limits. Finish time remains unset.

**Migration remains in progress.**

### Previous verified checkpoint

### Startup, deep links and shared creator blocking — 29 October 2026

AppLifecycleFeature owns startup and complete destination requests. The previous
checkpoint passed 1,602 selected tests and app build, with 18 new regression cases.
Evidence: sibling Migration Evidence/kickstarter-app-lifecycle.

### Creator draft editing and images — 28 October 2026

CreatorDraftsFeature owns draft reads and ordered per-project/account saves,
uploads and image deletions. Native REST/URLSession transport preserves routes,
authentication, form fields and response decoding. Multipart preparation runs off
the UI actor and invalid input fails instead of trapping. Public demo rejects
creator operations. Repeated pending edits share; changed edits queue; closing an
observer cannot undo an admitted write. Session changes suppress old delivery and
queued dispatch. Preview/Close results retain their action; a later upload cannot
restore a deleted image. Current attachments now drive Preview validation, and
unsupported video deletion uses the existing failure UI rather than fatalError.

Baseline: **29 original tests passed**. Focused: **40 tests passed**. Final:
**1,294 Library + 199 framework + 91 API = 1,584 passed**, zero failures/skips.
**14 new draft regression cases** (10 Feature/lifetime, 4 API/multipart), in
addition to the four attribution cases added in the preceding checkpoint.
App build succeeded with zero errors/two existing warnings.
Results: /private/tmp/kickstarter-creator-drafts.qsqpXw.
Evidence: sibling Migration Evidence/kickstarter-creator-drafts.
Two compile attempts failed: shared REST helper visibility, then use of an internal
API error constructor from Library. Both corrected; no failed runtime test run or
human command intervention. The retained UpdateDraftViewModel currently has no
application constructor call found; tests do not establish editor reachability or
live upload behavior. Visual/device and live-service validation remain open.

### Previous checkpoint

### Project attribution — 28 October 2026

ProjectDetailsFeature now owns the native attribution mutation. The first event
for a page route is retained (including failure), repeated callbacks share it,
and different pages remain independent. Admitted writes settle after dismissal;
a session change before dispatch prevents sending under a replacement account.
The event name, project ID, optional properties and existing no-retry behavior
are retained. Presentation does not await or react to this analytics result.
AppModel now explicitly supplies this owner with the shared SessionFeature.

**128 focused tests passed**, zero failures/skips, including four new attribution
cases and **29 original creator-draft baseline tests**. App build succeeded with
zero errors/two existing warnings. No compile/test failures or human intervention.
Results: /private/tmp/kickstarter-attribution-draft-baseline.xcresult and
/private/tmp/kickstarter-attribution-build.xcresult. Evidence: sibling
Migration Evidence/kickstarter-attribution. This focused count is not comparable
to the previous 1,537-test integrated run and is not added to it.

Audit finding: third-party advertising callers in Thanks, ProjectPage,
PledgePaymentMethods and RewardsCollection construct cold producers without
starting them. Preserve this existing inactive behavior; enabling new tracking
requires a separate explicit product decision. It is not a migrated live event.

Remaining named implementation: creator UpdateDraft editing/images. Then app-wide
concurrency, broader regression, visual/device and live-service checks.
**The app-wide migration remains in progress.**

### Previous checkpoint

### Curated and post-backing recommendations — 28 October 2026

RecommendationsFeature owns both request policies through native awaitable APIs.
Onboarding queries categories concurrently, retains duplicates and shuffles the
combined results. Thanks resolves the root category, tries recommended/similar/
staff-picked sources in order, excludes the backed project, and stops at three
unique alternatives. Results retain their originating category. Duplicate pending
route inputs share; changed inputs, close/release and session changes invalidate
late outcomes. AppModel shares the existing SettingsFeature/SessionFeature with
this owner, preserving newsletter behavior and all screen layouts/navigation.

Baseline: **24 original tests passed**. Final: **1,251 Library + 199 framework +
87 API = 1,537 passed**, zero failures/skips. **14 new regression cases** (12
Feature/lifetime, 2 API). App build: zero errors, two existing warnings.
Results: /private/tmp/kickstarter-recommendations.JA9C5a.
Evidence: sibling Migration Evidence/kickstarter-recommendations.
One focused test run passed 36 and failed 1: a new test expected the leaf category
rather than the preserved parent category. Corrected that expectation. No compile
failures or human terminal intervention. The CuratedProjects logic suite alone
opts out of the snapshot reference-device gate. Visual/live checks remain open.

Remaining named implementation: project attribution and creator UpdateDraft
editing/images. Then app-wide concurrency, broader regression, visual/device and
live-service validation. **The app-wide migration remains in progress.**

### Previous checkpoint

### Saved projects, reporting and account fields — 28 October 2026

Ordinary save buttons now share ProjectMediaFeature's native watch/unwatch queue
and transient cache with the video feed. Session-generation and latest-intent
checks protect writes, rollback and delayed presentation. Reused cells discard
unadmitted debounced taps; admitted writes settle independently of observation.
The 500ms debounce, login prompts, haptics, notifications, counts and analytics remain.
AppModel supplies the shared SessionFeature to this owner.

ProjectReportingFeature owns option/email reads and ordered report submissions.
The form's read/observation tasks stop on disappearance; duplicate pending reports
share and changed reports queue. No automatic retry is added. Missing context now
produces the existing error banner instead of force-unwrapping. The existing Send
loading control is active during submission and retry is restored on failure.
Account fields now use SettingsFeature's shared async read, retaining refresh and
presentation decisions. Navigation construction stays in the controller rather
than a factory injected into the ViewModel. No screen layout or storage redesign.
Native Apollo cancellation is retained at the SDK boundary; public demo rejects
reporting and save mutations rather than presenting mock success as a live write.

Baseline: **30 original tests passed**. Final: **1,232 Library + 199 framework +
84 API = 1,515 tests passed**, zero failures/skips. **22 new regression cases**
(11 reporting, 6 media/save, 2 settings, 3 API). App build succeeded with zero
errors and the two existing Crashlytics-script and Frameworks-path warnings.
Final results: /private/tmp/kickstarter-project-actions.ChCP0M.
Evidence: sibling Migration Evidence/kickstarter-project-actions.

Four integration compile attempts failed: missing test await, navigation-helper
actor isolation, async test setup isolation, and snapshot-helper actor annotations.
One focused test failed because its unsave fixture supplied only a save response;
the fixture now supplies the intended unsave response with its assertion unchanged.
Snapshot tests retain their reference-device gate and were not part of this run.
All commands were run by the agent; no human terminal intervention was required.

Remaining named implementation paths: CuratedProjects/Thanks recommendations,
project attribution, and UpdateDraft editing/images. App-wide concurrency,
broader regression, visual/device and live-service validation remain open.
**The app-wide migration is still in progress.**

### Previous checkpoint

### Friends and following — 28 October 2026

FriendsFeature owns Find Friends list/statistics reads, pagination, and the ordered
follow/unfollow/follow-all command queue shared with Activity. Native service calls
reuse the existing route, cursor and request-body contracts. AppModel composes one
owner with SessionFeature; tests inject independent owners.

Equivalent pending requests share; distinct writes execute in account order without
automatic retry. Disposing observation cannot undo an admitted write. Replaced
sessions (including the same user ID) cannot commit old results or cache state.
Independent list/statistics reads preserve their separate failure behavior; refresh
supersedes pagination, released screens suppress late results, and empty pages stop.
Reads begun after writes wait for them. Follow-all invalidates older pages; its
existing two-second UI refresh delay now checks the originating session again.
Reused cells reject a different friend's completion. Both screens consult one
transient following cache; no persistence, screens, branding or identifiers change.
The fictional demo rejects follow mutations.

Baseline: **25 original tests passed**. Their assertions remain, with explicit async
waits. Final: **1,190 Library + 192 framework + 79 API = 1,461 tests passed**, zero
failures/skips; **23 new regression cases** (19 Feature/adapter lifetime cases and
four native API cases). App build succeeded with zero errors and two existing
warnings: Crashlytics script outputs and missing Frameworks search path.

Results: /private/tmp/kickstarter-friends.7Nq5rA (Library, framework, app build) and
/private/tmp/kickstarter-friends-api.PKLF7C (API). Only an API-test assertion changed
between these runs: compare statistics fields instead of requiring Equatable.
Evidence: sibling Migration Evidence/kickstarter-friends.

Four compile attempts failed while integrating tests: Xcode group identifier,
fallible producer observer, throwing environment fixture, and API fixture equality.
All were corrected; no executed test run failed. The earlier focused run passed 43
before two final cases were added. Repeated runs are not additive coverage.
No human command execution was required. The three newly selected logic-only suites
opt out of the snapshot reference-device gate; global snapshot checks are unchanged.

**One implementation group remains:** residual project, creator and account actions
(saved projects, recommendations, attribution, draft updates, reporting and account
reads). Then app-wide concurrency, broader regression and visual/device validation.
**App-wide migration remains in progress; live payments/follow operations remain unverified.**



### Pledge-manager navigation and reward add-ons — 28 October 2026

PledgeFeature now owns the pledge-manager project/update pair as one sequential
read. Equivalent pending reads share; changed destinations, screen closure and
session replacement suppress obsolete navigation. Route versions also guard
publication after a completed read's awaiting observer resumes.

RewardsFeature owns both standard and fast add-on requests, eligibility, shipping
and availability policy. It shares AppModel's SessionFeature. Independent screen
routes share equivalent pending work, replace changed input, and cancel on release.
The native APIs reuse the existing pure GraphQL mappers and cancellation boundary.
API delay is inside the async task, so account/cancellation checks cover it too.
The UI adapter keeps results paired with their requesting project/reward/shipping
configuration. Quantities, amounts, bonus support, errors and navigation retain
existing behavior. Invalid fast-query countries now throw instead of asserting.

The unused RewardsUseCase enrollment helper had no callers and was removed.
Active enrollment remains in ProjectDetailsFeature; login-gating tests remain.
No screens, branding, persistence or identifiers were redesigned.

Baseline: 33 original tests passed (14 pledge-manager, 15 add-on selection,
4 rewards login-gating). Final: **1,146 Library + 192 framework + 75 API = 1,413
passed**, zero failures/skips; **15 new regression cases**. App build succeeded
with zero errors and two existing warnings: Crashlytics outputs and missing
Frameworks search path. Results: /private/tmp/kickstarter-reward-addons.3rR5sc.
Evidence: sibling Migration Evidence/kickstarter-reward-addons.

Six unsuccessful compile attempts corrected nullable API/mock signatures, XCTest
actor setup, observer APIs, an overly broad route-guard edit and immutable fixture
construction. No executed test run failed. An earlier integrated run passed 1,412;
the final deferred-session test and guard raised this to 1,413. These repeated runs
are not additive coverage. No human command execution was required. Only the two
newly included logic-only suites opt out of the snapshot reference-device gate.

Two implementation groups remain: friends/following and residual project, creator
and account actions. Then app-wide concurrency, broader regression and visual/device
validation. **App-wide migration remains in progress; live payments remain unverified.**

### Pledged-project overview, address/receipt and payment plans — 28 October 2026

PledgedProjectsFeature owns overview pagination and tier selection, with independent
screen routes, shared pending requests, cancellation and account-generation guards.
The existing card parser/models move to Library; formatting, order, analytics and
screen layout remain. Paginator.Results is retained only as a snapshot type.
Refresh awaits the actual request and terminal pagination returns immediately.

PledgeFeature now owns address confirmations and GraphQL receipt writes using the
existing ordered account queue. One receipt result observer drives the banner and
refresh; the prior two-subscriber pipeline could execute the same write twice.
Negative acknowledgements retain their existing presentation semantics. Disposing
observation never undoes an admitted write; no automatic retry is introduced.
Payment-plan reads use independent cancellable routes and retain the exact project
associated with each response, preventing prior installments from being paired
with a newer project. Public demo rejects address/receipt mutations.

Baseline: 25 original tests passed. Final: **1,114 Library + 192 framework + 72 API
= 1,378 tests passed**, zero failures/skips. Includes 18 new cases (seven overview,
five pledge ownership, five container, one project/plan coherence). App build passed
with zero errors and two existing warnings: Crashlytics outputs and missing
Frameworks search path. Results: /private/tmp/kickstarter-pledged-overview.IALRLa.
Evidence: sibling Migration Evidence/kickstarter-pledged-overview.

Five compile attempts corrected integration/type/test registration issues. The
first integrated run passed 1,108/1,113; five parent pledge tests needed to await
plan completion before asserting. Business assertions remain. Pending duplicate
appearance now asserts one loading sequence; the original test comment already
required this. The logic-only payment-plan suite opts out of the reference-device
gate; visual suites remain intact. No human command execution was required.

No application callers remain for legacy overview, address confirmation, GraphQL
receipt or payment-plan service methods (compatibility APIs remain). Pledge-manager
project/update reads, add-ons, friends/following and residual actions remain, followed
by app-wide validation. **Migration remains in progress.** Live payments and other
server mutations, physical-device/visual parity and strict-concurrency sign-off
remain unverified.


### Backing management and checkout completion — 28 October 2026

PledgeFeature now owns managed project/backing reads and post-campaign checkout
creation, validation and completion. The existing screen bindings remain. REST
project data, GraphQL rewards/pledge-over-time metadata and the backing query retain
their data composition and fields. Backing's legacy producer and native caller share
one pure mapper. The initial-project screen cache and 300ms refresh animation remain.
Artificial combined-project latency now has one response delay instead of two;
production default remains zero.

Read routes are independent, share equivalent pending requests and reject superseded
or released responses. Session changes cancel reads. A refresh waits for preceding
writes and uses the write-admission version to avoid joining older pending data.
Checkout commands use the existing account-generation ordered queue: equivalent
pending inputs share; distinct commands remain ordered; failures never auto-retry.
Disposal does not undo an admitted mutation. Old account/caller outcomes are filtered.
Native APIs preserve nullable inputs, validation valid/messages and raw completion
response semantics. Public demo rejects checkout operations.

Baseline: 63 original ManagePledge/PostCampaignCheckout tests passed. Final:
**1,090 Library + 165 framework + 72 API = 1,327 tests passed**, zero failures/skips.
All 22 PledgeFeature cases confirmed, including ten new cases. App built with zero
errors and one existing Crashlytics script-output warning. Results:
/private/tmp/kickstarter-checkout.GBHb8b. Evidence: sibling Migration Evidence/
kickstarter-checkout. No human command execution required.

Rework recorded: two compile attempts corrected type qualification/test observer APIs.
Adapter run passed 73/75; focused run passed 84/85. Checkout assertions now await
completion. One original retry fixture omitted backing data; it now explicitly fails
both requests and asserts two errors/header events, retaining successful retry and
animation checks. Its intermediate single-header assertion failed in a targeted run
before correction. Other screen business assertions remain. Only the nonvisual
ManagePledge suite newly opts out of the snapshot-device guard.

No application callers remain for the migrated legacy checkout and managed-backing/
rewards request methods. Compatibility declarations remain. Live Stripe/Apple Pay/
3DS, server-accepted changes and physical-device/visual parity remain unverified.
Swift 5 builds are not full strict-concurrency validation.

Five implementation groups remain open, with the first two reduced. Next: PPO
pledged-project pagination, address/receipt writes and payment-plan loading, followed
by the remaining entries in [the work inventory](MIGRATION_REMAINING_WORK.md).
App-wide migration remains IN PROGRESS.

## Earlier verified checkpoints

### Pledge creation, updates, cancellation and receipt — 28 October 2026

AppModel now owns PledgeFeature alongside PaymentsFeature and the shared session.
PledgeViewModel, CancelPledgeViewModel and ManageViewPledgeRewardReceivedViewModel
use awaitable native service commands through presentation-only result adapters.
No application callers remain for legacy createBacking/updateBacking/cancelBacking/
backingUpdate methods; compatibility service signatures remain.

Distinct commands execute in account-generation admission order. Equivalent
pending tails share, while true/false/true receipt toggles remain three commands.
This deliberately serializes unrelated pledge writes within the same account too.
A failure allows the next command to proceed without automatic retry. Disposing a
screen observation does not abandon an admitted mutation. Cancellation and old
sessions suppress both successful and failed delivery; queued obsolete commands
never call the provider. Already sent mutations settle. New account generations
have independent queues. Pending sharing is not server idempotency.

Input payloads, Apple Pay/SCA checkout responses, loading/errors/navigation and
analytics remain unchanged. The existing cancellation GraphQL contract sends only
the backing ID; the optional cancellation note was already omitted and remains so.
All four mutations are rejected by the public-demo service.

Baseline: **88 original screen tests passed**. Their existing assertions remain,
with async fixture lifetimes explicitly awaited. Three nonvisual suites alone opt
out of the snapshot-device gate. Two initial compile attempts caught missing await
in test scheduler calls and optional chaining on nonoptional Checkout.Backing;
both were corrected. A focused run passed 100 tests. A final canceled-caller failure
case was then added alongside the successful-result case.

Final: **1,038 Library + 165 framework + 65 API = 1,268 tests passed**, zero
failures/skips. All twelve PledgeFeature cases individually confirmed. App built
with zero errors and one existing Crashlytics script-output warning. Results:
/private/tmp/kickstarter-pledges.kHYs2O. Evidence: sibling Migration Evidence/
kickstarter-pledges. No human command execution was needed for this checkpoint.

Live payments, server-accepted pledge changes, Apple Pay/3DS, physical-device and
visual parity remain unverified. These tests use controlled providers and fixtures.
The migration still uses Swift 5 mode; this is not strict-concurrency completion.

**Five implementation groups remain open**, at different stages and sizes:
pledge/backing management, checkout/payment plans, reward add-ons, friends/following,
and residual project/creator/account actions. See [remaining work inventory](MIGRATION_REMAINING_WORK.md)
for concrete paths and final validation gates. No percentage is inferred from test
counts or groups. Next: backing reads/PPO and checkout creation/validation/completion.

App-wide migration remains IN PROGRESS.

### Payment methods and Stripe intents — 28 October 2026

Stored-card reads, addition/deletion and Stripe setup/payment intent creation now
run through one AppModel-owned PaymentsFeature and native async service methods.
The existing Stripe adapter is an output-only UIKit compatibility boundary.
There are no remaining application callers of the migrated legacy card/intent
request methods. Existing service signatures remain for compatibility.

Equivalent pending intents share one request; different contexts/checkouts keep
their identities. Card writes are admitted in order, with equivalent pending
tails shared. Failed writes do not retry or block the next command. Screen
disposal stops delivery without abandoning an admitted write. Card reloads wait
for admitted writes and refetch if another write overtakes a read. Session
generations gate commands, completion and delayed presentation. Demo payments
are rejected. Native card queries bypass cache to reflect confirmed changes.

Existing screens, card availability/order, optimistic deletion/rollback, error
copy, Stripe configuration and the missing stripeCardId workaround remain.
Payment amount formatting, Checkout-ID base64 encoding, context and nullable
marketing input are preserved. The legacy GraphQL payment-intent mapping does
not send backingId; this checkpoint retains that wire contract.

Baseline: 69 original payment-screen tests passed. Those three nonvisual suites
alone opt out of the snapshot-device gate. Final: 938 Library + 165 framework +
44 API = **1,147 tests passed**, zero failures/skips; all ten new PaymentsFeature
cases individually confirmed. App build succeeded with zero errors and one
reported existing Crashlytics script-output warning in this incremental build.
Results: /private/tmp/kickstarter-payments.HBdEzT.
Evidence: sibling Migration Evidence/kickstarter-payments.

Unsuccessful attempts are retained. Compile integration needed qualified input
types and explicit actor isolation. A focused run passed 77/80 with two fixture
crashes and one presentation assertion failure. Temporary test environments were
ending before their async work; fixtures now await owned work before exit and
retain the established synchronous XCTest setup order. The test guard prevented
live requests. The next run passed 79/80. The remaining test omitted its card-list
fixture: the native mock correctly failed instead of the old mock's silent empty
producer, canceling payment-sheet presentation. Supplying the intended card-list
response preserved the original assertions; the integrated run then passed.

No live Stripe/account mutation, 3DS/Apple Pay authorization, actual charge or
authenticated visual/device parity is verified. Creating an intent is not proof
of completing payment. Server idempotency is not established; no automatic retry
is introduced. Post-campaign checkout creation/validation/completion and pledge
mutation ownership remain legacy and are the next stage.

Remaining work:
1. Pledge create/update/cancel, checkout validation/completion, backing management,
   reward-received writes and payment-plan loading.
2. Remaining application request/dispatch audit and full regression.
3. App-wide concurrency validation, authenticated visual/physical-device journeys,
   live-service validation and the final evidence/timing report.

App-wide migration remains IN PROGRESS.

### Messaging — 28 October 2026

Mailbox pagination, message search, thread/backing reads, sending and read status
now execute through one AppModel-owned MessagingFeature and native async service
methods. AppDelegate message links use the same owner. Blocking reuses the
existing DiscussionFeature. No application caller remains on the migrated legacy
message request methods; compatibility signatures remain in KsApi.

Preserved existing UI, navigation, message ordering, recipient/error copy,
mailbox refresh clearing, concatenated pages and empty-page sentinel.
Search cancels on every changed/cleared query before debounce; late results and
errors cannot refill cleared results or stop a newer request's loading indicator.
Hidden searches cannot start after disappearance. Distinct sends queue per
destination; equivalent pending tails share. Disposing a dialog removes delivery
without abandoning an admitted write. Session generations gate reads, writes and
delayed presentation. Public demo rejects account messaging operations.

Baseline: all 36 original nonvisual messaging tests passed. Only those four
suites opt out of the reference-simulator gate. Original assertions are retained
with isolated Features and explicit async/presentation synchronization.
Final: 859 Library + 165 framework + 39 API = 1,063 passed, zero failures/skips.
All 15 new MessagingFeature cases were individually confirmed in xcresult.
The app built with zero errors and two existing warnings (missing legacy
Frameworks search path and Crashlytics script outputs).
Results: /private/tmp/kickstarter-messaging.Bxc7BY.
Evidence: sibling Migration Evidence/kickstarter-messaging.

Earlier verification caught initialization/setup isolation issues and four new
fixture failures: the existing MessageThread.lens.id setter always returns zero.
Tests now construct distinct IDs directly; unrelated production lenses were not
changed. One integrated run also exposed two email-verification tests advancing
their scheduler before awaiting the async command, but not afterward. All three
verification-result tests now await work then advance presentation; their
original success/error assertions are unchanged. Failed artifacts are retained.

Remaining work:
1. Payment-method loading/addition/deletion and Stripe setup/payment intent ownership.
2. Pledge creation/update/cancellation, backing management and reward-received writes.
3. Remaining application request/dispatch audit, full regression, strict concurrency,
   authenticated visual/physical-device journeys and live-service validation.

No live message/account/payment writes or rendered/device parity were validated.
App-wide migration remains IN PROGRESS.

### Project-notification settings — 28 October 2026

Project notification lists and switch saves now use native async service methods
under the existing SettingsFeature. Per-notification queues preserve distinct
on/off/on intents and share equivalent pending tails. Disposed/reused cells stop
presentation without abandoning admitted writes. Confirmed responses alone update
the existing cache/key. Replaced sessions cannot cache or publish late success
or failure, including through the existing presentation delay.

The existing screens, combined email/mobile switch and error strings remain.
An intentional rapid-edit correction restores the last confirmed value on error,
rather than a previous speculative tap. Reads wait for admitted writes and reject
results overtaken by a new edit. The public demo rejects these account operations.
No application caller remains on fetchProjectNotifications/updateProjectNotification;
legacy signatures remain for compatibility.

Baseline: six original list/cell tests passed. Two nonvisual suites opt out of the
snapshot device gate and now use signed-in isolated fixtures and explicit awaits.
Final: 808 Library + 164 framework + 36 API = 1,008 passed, zero failures/skips;
app build succeeded with zero errors and one existing Crashlytics script warning.
Eight new Feature/presentation cases and two native route/decoder tests ran.
Results: /private/tmp/kickstarter-project-notifications.r7xOYr.
Evidence: sibling Migration Evidence/kickstarter-project-notifications.

Coverage audit caught the new test file missing from the Xcode test target:
the earlier 34-test focused and 1,000-test integrated runs did NOT include those
eight cases. Added explicit project membership, reran verification and checked
all eight named results. Earlier successful commands are retained as incomplete
coverage, not proof that the new scenarios passed.

Remaining plan:
1. Messaging: mailbox/thread pagination, search, thread/backing lookup,
   mark-as-read and sending; preserve cancellation, retries and session ownership.
2. Pledge/payment/backing: remaining checkout mutations, payment-method management,
   backing edits/cancellation and related workflows.
3. Audit remaining application request/dispatch boundaries; full regression,
   app-wide strict concurrency, visual/physical-device and live-service gates.

The next audit identified four messaging ViewModels still invoking legacy APIs.
No live message/account/payment mutation or rendered/device validation was run.
App-wide migration remains IN PROGRESS.

### Shared root/Activity badge ownership — 28 October 2026

Root and Activity now share the SessionFeature badge command. One execution
commits the returned count into the latest current user; delayed controller
notifications never re-save an old whole-user payload. Old-session results are
suppressed through presentation delays. Badge completion invalidates stale user
snapshots while independent email/setup metadata requests continue.

Baseline: 24 original Root tests passed. Six new scenarios cover shared single
commit, current preferences, explicit retry, stale reads, independent setup,
old-session notification suppression and silent UI save failures.
Final: 794 Library + 164 framework + 34 API = 992 passed, zero failures/skips;
app build succeeded with zero errors and two existing warnings (Crashlytics
outputs and missing legacy Frameworks path).
Results: /private/tmp/kickstarter-root-badge.0zGMvZ.
Evidence: sibling Migration Evidence/kickstarter-root-badge.

An earlier run passed 991 tests and built. The next run passed 793 Library tests
but crashed in RewardsCollectionViewModelTests during AppEnvironment.popEnvironment.
The crash stack shows the async fixture helper mutating its shared stack on a
background executor. Two Rewards tests also started second location requests
without awaiting them before fixture release. Async fixture helpers now run on
MainActor, and those tests drain the second requests. Ten repeated Rewards runs
and the final integrated run passed. The exact allocator-level abort cause is
not proven; failed-run evidence is retained. No test parallelism was disabled.

Existing tab UI, navigation, optimistic badge clearing and silent save-error
behavior remain. Root's nonvisual tests alone opt out of the snapshot device
gate. The now-unused reactive badge helper remains for compatibility.
Next: project-notification settings, messaging, then pledge/payment/backing.
No live mutation, full-suite, app-wide strict-concurrency or rendered/physical
device validation is claimed. App-wide migration remains IN PROGRESS.

### Account writes and session refresh — 28 October 2026

Email/password creation and changes, currency, verification sends and Facebook
connection now use directly awaitable SettingsFeature commands and native async
service adapters. They share the existing preference queue: equivalent pending
tails share; distinct edits remain ordered. Confirmed account fields merge into
the latest session user instead of replaying stale preference snapshots.
Admitted writes survive observer disposal; no automatic mutation retry is added.

SessionFeature owns setup persistence and guards refresh success AND failure
against session/read generations. An obsolete unauthorized response cannot log
out a replacement account. Authenticated lifecycle refresh explicitly permits
legacy token-only restoration; ordinary refresh does not create a login.
Email-verification links have a separate ordered token lane, work while signed
out and never establish a session. AppDelegate and the Facebook cell no longer
persist delayed whole-user results. The main Settings screen uses the same
guarded refresh, retaining its cached-user-first presentation.

Baseline: 37 original account-screen tests and 11 original Settings screen tests
passed before their respective production changes. The existing Facebook suite
was discovered later (its filename contains Faceook), adapted and run afterward;
it is not claimed as pre-change evidence. Five account suites and Settings opt
out of the snapshot reference-device gate only because they are nonvisual.
Business assertions remain; tests now await Feature completion.

Final: 790 Library + 138 framework + 34 API = 962 passed, zero failures/skips;
app build succeeded, zero errors, three warnings (Crashlytics output declaration,
missing legacy Frameworks search path, extension/app build-number mismatch).
Seventeen added Feature scenarios cover sharing, ordered writes, failures/retry,
disposed observers, account replacement, read/write overlap, setup persistence
and token-only restoration. Three development compile failures were corrected
and retained in the case study. Intermediate 945- and 951-test runs also passed.
Results: /private/tmp/kickstarter-account-writes.6Wlp03.
Evidence: sibling Migration Evidence/kickstarter-account-writes.

Next: root activity badge ownership, messaging and project-notification
reads/writes, then pledge/payment/backing. Existing reactive presentation and
unmigrated service signatures remain compatibility boundaries. Settings retains
its existing controller factory; moving that navigation plumbing is not part
of this checkpoint. No live account mutations, visual/physical-device validation,
full-suite or app-wide strict-concurrency sign-off. App-wide migration IN PROGRESS.

### Social login, signup, OAuth and password reset — 28 October 2026

Initial Facebook login, Apple login, Facebook signup and OAuth now join the
existing AuthenticationFeature. Apple/OAuth token and user requests are sequential
within one attempt; only the complete current pair can establish a session.
Controllers no longer persist credentials. SessionFeature is the sole application
caller of AppEnvironment.login (test fixtures excluded). Existing UI is retained.
OAuth tracks its login event once before persistence to preserve analytics identity.

Password reset has an independent command lane: equivalent pending emails share,
changed emails supersede presentation, and reset never logs in or cancels login.
Cancellation cannot undo a server-accepted signup/reset; no automatic retry is added.
OAuth's static subscription bag is replaced by a screen-owned browser/redirect task.
Cancellation/release suppresses late callbacks and session commits. Public demo
rejects these account operations. Legacy service signatures remain for compatibility;
the migrated application callers no longer use them.

Baseline: 53 of 55 original tests passed; two OAuth tests exceeded their existing
10ms callback timeout. Those tests now directly await the command. Four logic-only
suites opt out of the snapshot device gate; visual suites remain unchanged.
Original business assertions are preserved except reset loading expectations,
which now require loading then stopped rather than the synchronous mock's inverted
sequence. Malformed Apple user IDs fail instead of leaving loading active. Apple
uses one final artificial-delay boundary (default zero), not one per request stage.

Final: 725 Library + 127 framework + 34 API = 886 passed, zero failures/skips;
app build succeeded with zero errors and two existing warnings. Thirteen added
Feature/OAuth lifetime cases and three native request-preparation cases protect
sharing, cancellation, partial failure, stale replies, consent, PKCE, temporary
token headers and pre-login analytics. Development compile failures and the
baseline timing failures are retained in the evidence, not counted as passes.
Results: /private/tmp/kickstarter-auth-flows.PCLOfp.
Evidence: sibling Migration Evidence/kickstarter-auth-flows.

Next: remaining account writes (email/password/currency/verification and account
connections) and legacy AppDelegate current-user refresh, then messaging/project
notifications and pledge/payment/backing. Live social/browser authorization,
physical-device/visual parity, full-suite and app-wide strict-concurrency sign-off
remain open. App-wide migration remains IN PROGRESS.

### Email login and two-factor authentication — 28 October 2026

AppModel now composes AuthenticationFeature with the existing SessionFeature.
Email login and email/Facebook two-factor verification/resend use native async
service requests. SessionFeature commits credentials/user through the existing
AppEnvironment store before presentation; the two controllers no longer re-save
completion payloads. Routes, encoding, storage keys, UI and notification effects
remain unchanged. AppDelegate notification callbacks explicitly enter on main.

Equivalent pending attempts share transport. Changed credentials/code supersede
only their operation. Resend and verification remain independent; resend never
establishes a session. Cancelled/disposed callers, obsolete attempts and replaced
sessions cannot commit, even if transport ignores cancellation. Failed attempts
preserve the current session and retry is explicit. No live authentication ran.

Baseline: all 21 original Login/TwoFactor tests passed at the previous checkpoint.
Final: 657 Library + 127 framework + 31 API = 815 tests passed, zero failures/skips;
app build succeeded with zero errors and two existing warnings. Ten new controlled
AuthenticationFeature cases and two native decoder cases protect the boundary.
Results: /private/tmp/kickstarter-authentication.juTwNe.
Evidence: sibling Migration Evidence/kickstarter-authentication.

An earlier integrated run passed 655 tests and aborted in the previously recorded
Discovery lifecycle test. Repetition reproduced it after four passes. That test
now drains lifecycle-triggered work before restoring its environment, and suite
teardown cancels/awaits retained work. All original assertions remain. Ten repeated
runs and both subsequent integrated runs passed. This fixes an observed lifetime
gap; the XCTest/Swift task-deallocation abort's exact root cause is not established.
Failed runs are retained in evidence rather than represented as clean passes.

Next authentication boundary: initial Facebook/LoginTout and Apple login, signup,
OAuth and reset-password flows. Remaining account writes, legacy AppDelegate
current-user refresh, messaging/project notifications and pledge/payment/backing
also remain. App-wide strict-concurrency, full-suite, physical-device and visual
validation are NOT complete. App-wide migration remains IN PROGRESS.

### Remaining preference entry points — 27 October 2026

Thanks newsletter signup and notification-setting deep links now use the same
SettingsFeature queue as the settings screens. All 18 notification URL names map
to individual edits. Unknown names preserve the legacy unchanged-user save;
signed-out links do not save. No app caller remains on reactive updateUserSelf.

Thanks no longer persists its completion again. AppDelegate separates an already
committed preference notification from legacy user-refresh payloads; its callback
reads current session data rather than replaying a delayed command snapshot.
The existing user-identification and user-updated notification effects remain.
The app-delegate's legacy user-refresh/authentication paths are not yet migrated.

Baseline: 16 Thanks and 118 AppDelegate tests passed before production changes.
After: 647 Library + 127 framework + 29 API = 803 tests passed, zero failures/skips;
app built successfully with two existing warnings. The Library run includes 21
unchanged Login/TwoFactor tests as the next authentication baseline.
Results: /private/tmp/kickstarter-preference-entrypoints.ITOvsu.
Six added tests protect URL mapping, cross-entry-point ordering, failure,
signed-out/unknown links and no delayed whole-user replay.
Evidence: sibling Migration Evidence/kickstarter-preference-entrypoints.

No UI redesign or live account mutation. Thanks recommendations, authentication,
other account writes, messaging and payment/backing workflows remain, as do
full-suite, strict-concurrency and physical-device/visual validation.
App-wide migration remains IN PROGRESS.

### Settings preference reads/writes and account-safe persistence — 27 October 2026

AppModel now composes SettingsFeature with the shared SessionFeature. Six
settings ViewModels use native async account reads and ordered preference writes:
privacy/following/recommendations, notification toggles/digest frequency, and
newsletters including subscribe-all. Existing UIKit controls and navigation remain.

Changed intents queue; equivalent pending tails share. On/off/on retains order.
Edits apply to the authoritative session user at dispatch, not an old cell
snapshot. Confirmed preference fields commit before the next queued save starts.
There is no second user cache. Disposed observation/cancelled waiters do not
abandon admitted writes; failures remain failures and retries are explicit.
Signed-out, wrong-account and obsolete-session commands cannot dispatch or publish.

Settings, Profile and Activity persistence now goes through SessionFeature,
not deferred controller callbacks. Read revision checks extend through Profile's
presentation delay; badge completion merges its count into the latest user.
Recommendations keep optimistic switch feedback but persist only confirmed
preferences, eliminating speculative whole-user writes and rollback overwrites.
AppEnvironment remains the credential/current-user store; its keys are unchanged.

55 original settings tests passed before production edits. Original expectations
are retained, with explicit signed-in fixtures and async waits. Thirteen new
SettingsFeature tests and a delayed-Profile regression protect the new boundary.
Final integrated verification: 606 Library + seven framework + 29 API = 642
passed, zero failures/skips; app build succeeded with two existing warnings.
Results: /private/tmp/kickstarter-settings-preferences.famRTj.
An earlier unchanged integrated run passed 605 tests but aborted in
DiscoveryPageViewModelTests/testActivitySampleWithLifecycle. The crash stack
entered XCTest/Swift task deallocation; its root cause is not established.
The full rerun passed without modifying source. Compile/test-harness corrections
and the abort are retained in sibling Migration Evidence/kickstarter-settings-preferences.

Remaining shared-endpoint writers: ThanksViewModel's games-newsletter signup and
AppDelegateViewModel's notification-setting deep link still use updateUserSelf.
Route these through SettingsFeature before claiming app-wide preference-write
serialization. Project-specific notifications, email/password/account deletion,
authentication/credential ownership, messaging and payment/backing workflows
also remain. Full-suite, strict-concurrency, authenticated device/visual gates
are still open; no live account writes or populated-screen parity are claimed.
App-wide migration remains IN PROGRESS; this is a bounded verified checkpoint.

### Activity/Profile loading and shared account reads — 27 October 2026

AppModel now composes ActivityFeature, ProfileFeature and one shared SessionFeature.
Activity owns ordered/deduplicated history, pagination and survey reads. Profile
owns independently paged backed/saved collections and concurrent header reads.
The existing UIKit ViewModels retain presentation, navigation and analytics;
their reactive request/pagination chains have been replaced by awaitable work.

Equivalent requests share. Refresh supersedes pagination, reset rejects late
successes/errors, and login/logout invalidates both tabs even when the next user
has the same ID. Account identity is checked after suspension. Signed-out Profile
commands do not request private collections. Admitted badge writes are not
cancelled by navigation/session changes, but cannot update a newer account.

A project-save event explicitly invalidates older header reads; ordinary repeated
appearances share. Successful REST/GraphQL header values combine regardless of
completion order, correcting the legacy graph-first lost-update race. Individual
fields still publish independently; a failure does not publish a partial combined
session update. AppEnvironment remains the credential/persistence authority:
authentication and full session-storage migration are NOT complete.

573 tests passed: 537 Library, seven framework and 29 API, zero failures/skips.
App build succeeded with two pre-existing warnings.
Results: /private/tmp/kickstarter-account-tabs.f1QiDO.
24 original ViewModel tests passed before changes; all original expected values
remain. Sixteen controlled Feature tests cover sharing, adverse completion order,
failure/retry, independent tabs, reset, logout and same-account session changes.
Intermediate compile failures, one missing async wait and missing test-target
membership were corrected and recorded, not omitted from evidence.
Evidence: sibling Migration Evidence/kickstarter-account-tabs.

Next: account/settings ownership using this shared session dependency, then
authentication/persistence, messaging/notification and pledge/payment/backing
workflows. The final app-wide inventory, strict-concurrency, full regression,
authenticated/device and visual gates remain open. No live badge/account/payment
mutation or populated authenticated-screen visual parity is claimed.
App-wide migration remains IN PROGRESS; this is a verified bounded checkpoint.

### Video-feed loading and save/watch — 27 October 2026

ProjectMediaFeature now owns route-scoped observable feed data, native async
loading, saved-project reconciliation, optimistic save state and rollback.
The ViewModel retains presentation, login intent, mute state and paging analytics.
Equivalent reads share; released routes and changed accounts reject stale results.
The original 30-item query, initial-load publication order, first impression and
separate fetchedItems reload signal are preserved. Saves never force a reload.

Watch/unwatch commands execute in order per account/project; equivalent pending
states share and unrelated projects proceed independently. Screen disposal does
not cancel admitted writes. Only the latest visible intent can roll back and
show the existing error toast. Queued old-account writes do not dispatch, and
uncertain remote mutations never retry automatically.

528 tests passed: 497 Library, seven framework and 24 API; zero failures/skips.
App build succeeded with the two existing Crashlytics/search-path warnings.
Results: /private/tmp/kickstarter-video-feed.gHPMre.
The original 18 ViewModel tests passed before changes; 40 focused tests passed
after the initial patch. Seven new controlled Feature tests cover read sharing,
late responses, write ordering, failure/retry, navigation/account changes and
observation publication. One intermediate test-helper compile failure was fixed
without weakening assertions. No live watch mutation or visual parity claimed.
Evidence: sibling Migration Evidence/kickstarter-video-feed.

Next: Activity/Profile loading and shared account/session ownership, followed by
remaining account/settings/messaging/notification and pledge/payment/backing flows.
Final gates remain: complete ownership/GCD inventory, strict-concurrency diagnostics,
full regression, representative device/integration and visual validation.
Core browsing boundaries are substantially migrated; app-wide migration remains
IN PROGRESS. Passing focused tests is not a whole-app completion percentage.

### Discussion posting, retry and blocking — 27 October 2026

Comments, replies and the legacy comment dialog now execute mutations through
DiscussionFeature and native async Service operations. Stable attempt identity
shares duplicate calls; distinct posts use five concurrent slots with FIFO
admission. Failed attempts can be explicitly retried; uncertain writes never
retry automatically. Screen disposal stops delivery but does not cancel an
admitted mutation. Block targets execute independently. Account changes suppress
obsolete results and stop queued/delayed old-account work before dispatch.

Optimistic replacement IDs, failed text, one-second transitions, three-second
retry-success display, block notifications and analytics remain. Reactive
producers are retained only as UIKit presentation adapters, not network owners.
The dialog's existing early optimistic dismissal remains a documented legacy
behavior. No ViewModel-to-ViewModel helper calls remain in this slice.

499 tests passed: 472 integrated Library, seven framework update-detail and
20 API tests, zero failures/skips. App build succeeded with two existing warnings.
Results: /private/tmp/kickstarter-discussion-writes.FuQBU3.
Ten new controlled Feature tests cover sharing, capacity, independent writes,
failure/retry, lifetime, account changes and cancelled waiters. The baseline
passed 61 tests; eight dialog tests initially crashed at the inherited snapshot
device guard, then all eight passed after a nonvisual-suite-only opt-out.
No original assertion removed. No live comment/block submitted or visual parity
claimed. Evidence: sibling Migration Evidence/kickstarter-discussion-writes.

Remaining plan, in order: video-feed read/save/watch ownership; remaining
Activity/Profile and session/account domains; pledge/payment/backing workflows;
then app-wide ownership inventory, concurrency diagnostics, full regression and
representative device/integration validation. Six concrete Features now exist,
but that is not a completion percentage: unconverted transactional domains are
substantial. App-wide migration remains IN PROGRESS.

### Previous discussion reads and playback counters

Discussion read execution and project-video counters now have concrete AppModel
owners: DiscussionFeature and ProjectMediaFeature. 454 integrated tests passed
with zero failures/skips, followed by a successful app build:
`/private/tmp/kickstarter-discussion-media.ga9kgf`.

The boundary includes project/update comment pages, backward reply pagination,
update links in the update list/detail screens, project-context lookups and
independent video start/completion reports. Providers use native async REST and
the existing cancellation-aware Apollo bridge. Features retain request identity,
cursors, tasks and account checks; screen routes release independently.
Equivalent pending reads share, refresh/changed inputs supersede only their route,
and canceled or obsolete responses cannot publish. Counter writes never
automatically retry an uncertain server outcome.

Existing UI, WebKit policy, keyboard/navigation, playback threshold, analytics,
optimistic posting/retry/blocking and branding remain unchanged. A missing
GraphQL envelope still finishes silently, distinct from a valid empty page.
The existing reply retry test caught an extra clear before the first successful
reply count; the Feature now preserves the original emission order. All original
assertions remain. Baseline: 71 existing ViewModel tests passed. Intermediate
compiler/test-harness corrections and the one failed retry assertion are retained
in sibling Migration Evidence/kickstarter-discussion-media.

Seven update-detail navigation tests passed in
/private/tmp/kickstarter-discussion-update-detail-third.xcresult; 19 discussion,
update and service decoder tests passed in
/private/tmp/kickstarter-discussion-api.xcresult. Both have zero failures/skips.
The framework scheme's stale deleted-target references now point at its package
targets. Search/comments/replies controller test classes are MainActor so the
package compiles against isolated ViewModels; their snapshot guards remain.
Agent smoke observed demo overview → Campaign → overview. This demo route exposes
no populated discussion/update/video flow, so no visual parity or live-counter
claim is made. No comment, block, watch or payment mutation was submitted.

Remaining: comment posting/retry and blocking ownership, video-feed loading and
watch/save operations, then shared session/account and transactional flows.
Activity/Profile and other legacy domains remain open. These reads do not
complete the app-wide migration; strict concurrency, full live/device/visual
validation and transaction verification remain separate gates.

### Previous shipping and creator checkpoint

Shipping-location loading and creator interaction policy now use the existing
RewardsFeature and ProjectDetailsFeature owners. 377 combined tests passed,
zero failures/skips, followed by an app build in
/private/tmp/kickstarter-shipping-interactions.82bZbI.
Five existing location model/GraphQL adapter tests also passed in
/private/tmp/kickstarter-shipping-locations-api.xcresult (zero failures/skips).
Agent smoke observed demo overview → Rewards ($25 supporter edition, one reward)
→ overview → Creator → overview. No transaction submitted. The digital demo does
not exercise the shipping picker, and live creator-page content was not verified;
fixture tests protect shipping selection/error and creator messaging behavior.

The shipping request captures its service, shares equivalent in-flight work,
replaces changed project/backing inputs and rejects obsolete/account-mismatched
responses. Each selector has an independent lifetime. Default selection remains
backing → server-configured country → US → first destination → nil. Digital
rewards avoid the API; failures remain errors and retain prior successful state.
The ViewModel keeps shimmer, localized errors, picker presentation and its
300 ms selection-dismissal debounce. No controller or layout changed.

Creator biography request preparation and current-session message authorization
now belong to ProjectDetailsFeature. WebKit policy/navigation remains synchronous
presentation work; no artificial async task was added.

Baseline shipping: nine existing tests passed. Seven creator tests crashed in
synthetic WebKit frame deallocation. Plain test data no longer fabricates native
WKFrameInfo/WKNavigationAction objects; actual WebKit events are still retained.
The underlying event/frame properties are optional for synthetic data; the sole
production event consumer retains its target-frame security-origin check through
optional access. Expanded tests exposed another raw WKFrameInfo in the pledge-web
helper; it now uses the plain-data initializer. Creator, updates and pledge-web
assertions all pass unchanged. A new default-country test fixture was corrected
to configure the server country, not device country. Failures are retained in
sibling Migration Evidence/kickstarter-shipping-interactions.

Remaining project boundaries: update/comment loading, media and block/watch
interactions, then shared session and transactional flows. Existing tests of a
legacy adapter do not mean that adapter has been migrated. App-wide migration,
strict-concurrency and full live/device/visual validation remain IN PROGRESS.

### Previous rewards and related-project checkpoint

Rewards-screen and related-project reads now use CFA-owned async execution.
324 combined Search/Explore/Project-detail/Rewards/composition tests passed,
zero failures/skips, followed by a successful app build:
/private/tmp/kickstarter-rewards-related.VmZxNu.
Two existing sorted-reward decoder tests also passed:
/private/tmp/kickstarter-rewards-sorted-decoder.xcresult.
Six existing NoRewardInserterTests passed separately in
/private/tmp/kickstarter-no-reward-insertion.xcresult (zero failures/skips).

RewardsFeature owns independent screen routes, in-flight sharing, latest-country
replacement, account identity, visibility filtering and No Reward insertion
policy. The existing API returns a complete sorted list: no cursor, pageInfo or
next-page UI action exists. No new pagination contract was invented.
ProjectDetailsFeature owns independent related-project requests; the former
use case is now a presentation/navigation adapter, not a reactive executor.
Both use the existing cancellation-aware Apollo bridge and captured service.

An additional failed-country-refresh regression preserves the last successful
cards with their original shipping context instead of relabelling them with the
failed request's country. Existing scroll, selection and analytics assertions
remain. Only nonvisual suites opt out of the snapshot reference-device guard.
The initial baseline guard trap and intermediate compiler corrections are
retained in sibling Migration Evidence/kickstarter-rewards-related.

Final demo smoke: Pocket Observatory overview → Rewards (supporter edition,
$25, one reward) → overview → Campaign. No transaction submitted. Public demo
does not implement related-project cards; fixture tests cover loaded cards,
navigation and errors, but no visual recommendation-card claim is made.
No controller/layout/branding/identifier changed. Strict concurrency, live API,
full accessibility/snapshot/device validation and app-wide migration remain open.

Next connected boundary: shipping-location loading and remaining project
interactions (creator/media/comments/updates), followed by shared session and
transactional flows. This checkpoint completes these reads, not the whole app.

### Previous project-detail checkpoint

Project-detail loading is now connected through ProjectDetailsFeature in AppModel.
293 combined Search/Explore/Project-detail/composition tests passed with zero
failures/skips, followed by a successful app build:
/private/tmp/kickstarter-project-details.90zCaO.
An additional 11 existing API fetcher/backing-decoder tests passed in
/private/tmp/kickstarter-project-details-api.xcresult. Runtime: iPhone Air, iOS 26.2,
Xcode 26.2, Swift 5 language mode. This is not full-app or strict-concurrency sign-off.

The Feature owns per-route snapshots, loading/error state and request identity.
Standard loading preserves enrollment → project → optional backing → rewards;
the fast experiment runs base/extras as structured parallel children. Equivalent
in-flight loads share completion; post-mutation refresh replaces pending reads.
Account changes/cancellation prevent late publication. Each stacked project page
has an independent scope, released when its view model is destroyed.

The existing cancellable Apollo bridge is now CancellableGraphQLRequest and is
shared with Search; no reactive producer is wrapped to implement async loading.
The public legacy ProjectPageFetcher API remains for compatibility/reference
tests, but the running project page no longer calls it. Remaining reactive
project-page execution includes related projects, user blocking and pledge/media
adapters, not the migrated detail/backing/rewards dependency chain.

Baseline: all 75 existing page/analytics tests passed. Their assertions remain.
Async tests exposed previously undrained recommendation mock errors; explicit
pending fixtures isolate the old assertion boundary, with a separate test proving
recommendation errors still update the selected campaign. Twelve Feature tests
cover ordering, sharing, failure/retry, parallel dependencies, account changes,
independent routes, forced refresh and stale results. Evidence and compile/test
corrections are recorded in sibling Migration Evidence/kickstarter-project-details.

Simulator smoke on the verified build: Pocket Observatory overview loaded;
Campaign and FAQ opened; Rewards showed the demo supporter edition; returning
preserved the FAQ page. No pledge/payment submitted. No UI source changed.

Next connected boundary: rewards-screen loading/pagination and related-project
requests, then remaining project interactions. Preserve transaction ordering;
payments, authentication and app-wide completion remain separate open milestones.

### Previous Explore checkpoint

Final Explore continuation: 205 focused tests passed, zero failures/skips, and
the app built in /private/tmp/kickstarter-discovery-async.RzwK5t. DiscoveryFeature
now owns selected filter state and recommendation defaults as well as async work.
The existing view models retain screen readiness, visibility/navigation and
presentation ordering; those UI adapters are not separate domain executors.

Project requests include account identity when deciding whether work can be
shared. Another account cannot join an old request or reuse its cursor; late
project/activity responses are ignored after an account change. These guards
do not constitute a shared-session migration or a complete authentication audit.
Three new tests cover recommendation/selection policy and account changes.

On the final demo build, the agent selected Games and observed Forest Trails
with the All Games Projects header, then restored All Projects and observed
Pocket Observatory again. Earlier four-feed/detail-return smoke remains valid
for that checkpoint. No pixel comparison, manual pagination/refresh, live API
or full signed-in journey is claimed.

Next implementation boundary is project-detail loading and its dependency
chain, inventoried below. Explore has a verified automated implementation
checkpoint; full visual/accessibility/device/compiler gates remain open.

### Explore async ownership checkpoint

Explore async ownership is now verified: 202 focused Search/Explore tests passed,
zero failures/skips, followed by a successful app build. Results:
/private/tmp/kickstarter-discovery-async.vlaCu9. This includes all 55 pre-existing
Explore logic tests (assertions preserved), 13 new Discovery Feature/transport
tests, and the Search regression suites. The first Explore integration run passed
66 tests in /private/tmp/kickstarter-discovery-integration-01.xcresult.

DiscoveryFeature is composed in AppModel and owns independent Magic/Popular/
Newest/Ending Soon request identities, result/cursor/error state, refresh,
pagination and activity-sample tasks. The existing Service now exposes native
URLSession async methods using its existing session/authentication/error decoding;
the legacy methods remain for unmigrated callers. No second cache or session
owner was introduced. Equivalent work shares completion; forced refresh replaces
pending work; stale completions cannot append or stop a newer request.

Agent Simulator smoke on the built demo observed all four feeds, Paper Cities
detail from Ending Soon, and return to the same selected feed/cards. A drag
intended as pull-to-refresh opened the card instead, so manual refresh is NOT
claimed verified. Automated refresh/pagination tests passed. No visual source,
target identifier, storage format or production analytics configuration changed.

The filter/recommendation and account-context continuation is verified above.
Retained presentation/navigation/analytics signals are not themselves unfinished
request executors. Manual full journeys, snapshots, live APIs, complete compiler
isolation audit and the rest of the app remain open.

### Previous verified Search checkpoint

Search close-out and Explore's unchanged logic baseline passed 189 tests with
zero failures/skips, followed by a successful app build on iPhone Air / iOS 26.2.
Results: /private/tmp/kickstarter-query-admission.7z1aJ3. The earlier 188-test run
found one genuine request-identity bug: legacy DiscoveryParams equality omits
four GraphQL filters. Search now adds those fields to its request-sharing check;
global legacy equality is unchanged. One regression test exercises replacement,
sharing and stale-result rejection for all four fields. No test was weakened.

Search's automated implementation checkpoint is verified. Manual/snapshot and
complete strict-concurrency validation remain open; this is not app completion.
Explore is now the active implementation boundary. Historical pending notes below
are superseded by this result. Session auto-review now permits local Xcode tests;
do not ask the developer to run routine verification commands.

## Progress dashboard — 27 October 2026

**Overall: browsing/project interactions plus Activity/Profile reads have verified checkpoints.**
AppModel composes nine concrete Features, including the shared SessionFeature.
No top-level product area has passed every manual/snapshot/strict-concurrency exit
gate. The latest combined checkpoint passed 573 tests plus an app build.
Bounded earlier Simulator journeys are recorded above; authenticated tabs are fixture-tested.
Test counts are coverage evidence, not a percentage of the full application.

| Area / milestone | Evidence-backed status | Remaining exit criteria |
| --- | --- | --- |
| Runnable public-demo baseline and evidence capture | Working baseline established | Keep synthetic data distinct from live-service validation |
| Search request ownership, transport, cancellation and pagination | Implemented; focused tests passed | Final concurrency/compiler audit and broader integration |
| Search filter policy and category/location lookups | Implemented; focused tests and bounded earlier UI smoke | Repeat relevant UI journeys on final Search build |
| Search lifecycle, analytics, query admission and filters | Consolidated automated checkpoint verified, including GraphQL filter identity regression | Bounded final UI smoke, snapshots and strict-concurrency audit; retain output-only compatibility |
| Explore / discovery | Connected Feature owns filters/defaults, four feed states, async requests, pagination and activity samples; 205-test combined checkpoint and bounded smoke passed | Full snapshots, signed-in/live journeys, accessibility/device checks and compiler isolation audit |
| Project-detail loading, backing and rewards dependencies | Connected Feature and cancellation-aware API operations; existing page/analytics assertions and new concurrency tests passed | Live authenticated validation, full UI/compiler audit |
| Rewards-screen loading and related-project requests | CFA async owners connected; combined regression/build and bounded rewards smoke passed | Related-card visual/live validation; shipping-location loader and broader compiler/UI audit |
| Media, updates/comments and project interactions | Read, posting/retry/blocking, playback counters and ordered watch/save checkpoints verified | Live mutation/populated visual checks, remaining interaction inventory and compiler audit |
| Activity and Profile loading | Concrete tab owners; pagination, surveys and header requests verified | Authenticated/device/visual validation and integration with remaining account workflows |
| Shared account/session, settings and authentication | Shared read execution, badge clearing and session invalidation implemented; AppEnvironment still owns credentials | Settings writes, authentication, persistence/security and broader account integration |
| Pledged projects and transactional flows | Legacy execution remains outside migrated project read dependencies | Shared backing state, ordering/idempotency, cancellation, retry and storage guarantees |
| App-wide integration and support flows | Not completed | Root/lifecycle/deep links, notifications, reachability, shared transport/storage, wider tests |

Do not publish a percentage yet: feature sizes differ greatly and the full
callback/reactive/shared-state inventory is not complete. A grep count or the
number of green unit tests is not a work-completion measure.

### Remaining execution plan

1. **Search automated close-out is verified.** Retain result/banner/UI compatibility
   adapters; no further cosmetic reactive rewrites are prerequisites. Continue
   broader UI/snapshot/concurrency checks without confusing these with unfinished
   Search request ownership.
2. **Explore/discovery implementation checkpoint verified.** Its 55 existing logic tests passed unchanged
   assertions on the new async Feature route. Four independent feeds, native
   URLSession transport, refresh/pagination and activity snippets are connected.
   Selection/default policy is now in the same Feature; UI readiness/navigation
   stays screen-local. Continue integration/visual gates while moving on to the
   connected project-detail boundary.
3. **Project routes.** Map project detail fetching, prelaunch, media, rewards,
   creator information, comments and updates. Separate navigation/presentation
   from shared project state. Exact sub-feature boundaries follow that inventory,
   not folder names alone.
4. **Shared account/session, then Profile/settings/authentication.** Establish one
   authoritative session and persistence owner before migrating consumers that
   rely on signed-in identity. Preserve keychain/storage and login/logout effects.
5. **Activity/pledges and transactional flows.** Migrate read-only activity and
   backing projections, then mutations with explicit ordering, duplicate safety,
   retries, cancellation and rollback. Demo fixtures cannot establish real payment
   correctness; authenticated/live validation needs separate safe arrangements.
6. **Cross-feature integration and residual work.** Audit root tab composition,
   launch/deep links, notifications, media/reachability callbacks and shared network/
   persistence owners throughout the above stages, then complete remaining routes
   such as messaging, friends, onboarding and support/settings variants. Do not
   defer a shared dependency that blocks an earlier feature.
7. **Completion review.** Reconcile the full mechanism inventory, remove obsolete
   adapters/dead code, verify target membership and supported toolchains, run wider
   tests and UI/accessibility/device checks, and review the recorded case studies.
   A passing Search suite alone cannot satisfy this gate.

Steps 2–6 are dependency-informed sequencing, not equal-sized phases or a time
estimate. Each feature exits only with its behaviour contract, authoritative
ownership, directly awaitable model work, cancellation/overlap protection,
passing appropriate build/tests and explicit manual/integration evidence.
Preserve UI, identifiers and stored data throughout; no redesign is implied.

### Project-detail entry inventory — next connected boundary

ProjectPageViewModel has 62 existing input/output tests, with tracking in
ProjectPageViewModel_TrackingTests. Its load graph is triggered by first load,
login, successful backing, manage-pledge return and retry. Initial cached project
preview is distinct from the fresh result; preserve that distinction.

ProjectPageFetcher has two paths: the instant-pledge flag selects parallel base
and extended-property fetches joined into one project; otherwise project loading
conditionally fetches a backing before rewards and retains the no-reward option.
RewardsUseCase.addUserToSecretRewardGroupIfNeeded precedes those reads, and source
already warns that it may run too frequently. Do not silently reorder, repeat or
remove that mutation as a concurrency optimisation. Rich-text flags, errors,
loading, retry, ref tags and analytics must be characterised together.

These are source observations, not a migrated Project Feature or a new runtime
baseline. No project-detail implementation or test expectations were changed.

### Source evidence for this scope

AppModel currently stores searchFeature and discoveryFeature. RootViewModel.generateViewControllers
selects discovery, search and profile, plus signed-in pledged-project/activity or
signed-out activity when the floating-tab flag is off. DiscoveryPageViewModel
now forwards page and activity commands to DiscoveryFeature; ActivitiesViewModel
still calls reactive paginate and apiService; ProjectPageViewModel
still contains reactive fetching. Profile/account and many additional routes are
not connected through migrated AppModel Features.

Reconnaissance also found callbacks/queues in AppDelegate, OAuth, reachability,
video/audio, discovery controllers and UI helpers. This is a starting inventory,
not proof that every match needs replacement: SDK callback-queue arguments and
test code must be distinguished from application-owned work. Review protected
state, delivery/ordering, lifetime, errors and cancellation before each conversion.

## Scope and first boundary

Search is the first selected feature because its existing tests exercise query
replacement, filters, paging, loading, navigation metadata and analytics.
The baseline is committed at `192fa9148ebec7409c9245354b206d344edc1e50`.
Request ownership and filter selection/reset/query composition are extracted.
Search page transport, result-delay timing and pagination now use Feature-owned
async tasks. Public search/page commands await publication and cleanup. The live
UIKit bridge synchronously admits that same operation to preserve immediate UI
events; it retains the returned task instead of installing a reactive executor.

**Migration status: IN PROGRESS, not complete.** Search is only partially migrated.
Completed checkpoints below are historical evidence, not app-wide completion.

- Completed: Search request ownership; filter decisions; cancellable Apollo bridge;
  directly awaitable first-page/pagination commands with shared in-flight work.
- Last verified checkpoint: selection state/direct query construction and six
  query/lifecycle/analytics characterisation tests; 123 tests and app build passed.
- Latest verified slice: explicit query/lifecycle inputs, pagination threshold,
  and appearance/card-click analytics; 124 tests and app build passed.
- Latest verified analytics slice: explicit result-completion pairing, including
  three empty/error/pagination regression tests; 127 tests and app build passed.
- Latest verified presentation slice: direct filter-pill commands and lookup
  subscriptions with explicit ownership; 130 tests and app build passed.
- Current unverified close-out: explicit query admission with per-screen selection
  readiness and removal of the unused signal-query overload. Expected 133 tests
  plus app build. Two obsolete projection-only tests are replaced by two live-route
  reset/duplicate-request tests; native query tests no longer require a signal.
- Remaining Search work: consolidated runtime/type-check verification and
  behaviour-contract/manual/snapshot gates, not an open-ended adapter rewrite.
- The single verification script also selects 55 existing non-visual Explore
  tests to establish its baseline: 188 expected total, then the app build.
  Only those two logic suites opt out of the snapshot reference-device guard;
  no global test guard or visual suite was changed.
- Remaining app work: inventories and migration of Explore, Activity/pledges,
  Profile/authentication and shared state/transport/persistence. Do not create
  placeholder Features or declare these routes migrated.
- Completion requires evidence for all in-scope features, lifecycle/task ownership,
  compatibility and appropriate concurrency/build/test validation—not merely a
  green Search checkpoint. Before continuing, read this status and the contract.

Current project-request route:
`SearchViewController → SearchViewModel → AppModel.searchFeature → AsyncSearchProjectsProvider → Service.fetchSearchPage → Apollo`.
SearchFeature owns selection policy and native category/location lookup tasks;
AsyncSearchLookupProvider uses the existing Service and KSCache boundaries.
The native lookup changes have automated test/build and bounded manual verification.
The subsequent orphan cleanup also passed a fresh 111-test run and app build.
SearchFiltersUseCase is now a screen presentation adapter.

Target route:
`SearchViewController → SearchViewModel → AppModel.shared.searchFeature → search provider → existing API transport`.

The concrete SearchFeature will own query/filter decisions, result collection,
pagination cursor, request identity, overlap policy and retained errors. Its
ViewModel will own presentation, navigation intent, sheet state and screen task
handles. The provider will own GraphQL translation and transport/error semantics.
AppModel will construct the concrete Feature; it will not retain a ViewModel,
transport or navigation state. Preserve the existing category cache owner rather
than adding a second cache/store. Keep the UIKit screen and storyboard intact.

Do not create unused target types just to draw an architecture diagram. Introduce
the connected feature slice once baseline results support comparison.

## Actual top-level tab ownership map

| Existing tab/route | Existing screen / ViewModel | Intended owner | Current state |
| --- | --- | --- | --- |
| Explore / discovery | Discovery controllers / DiscoveryViewModel | AppModel.discoveryFeature / DiscoveryFeatureTests | Implementation checkpoint verified; final app-wide gates open |
| Activity (legacy tab variants) | ActivitiesViewController / ActivitiesViewModel | AppModel.activityFeature / ActivityFeatureTests | History/surveys/session-aware async loading verified; UI composition unchanged |
| Pledged projects and activity (signed in) | Pledged-project/activity flow | Ownership to map with shared pledge state | Legacy; not an empty placeholder Feature |
| Search | SearchViewController / SearchViewModel | AppModel.searchFeature / SearchFeatureTests | Automated implementation checkpoint verified; final app-wide gates open |
| Profile (signed in/out variants) | BackerDashboard controllers / ViewModels | AppModel.profileFeature / ProfileFeatureTests | Header/backed/saved reads verified; authentication/settings remain open |

`RootViewModel.generateViewControllers` omits Activity when the floating-tab
flag is enabled. Preserve this actual flag/session-dependent composition. A tab
is not permission to duplicate shared user, pledge or project state.

## Search concurrency inventory (not an app-wide inventory)

| Mechanism and source | Existing guarantee or limitation | Planned ownership/replacement | Required protection |
| --- | --- | --- | --- |
| `SearchViewModel` combineLatest query/filter signals | Any change rebuilds full request parameters | SearchFeature owns query/filter domain state | BEH-S04/S05; all filters and reset behaviour |
| Former `ksr_debounce`, environment scheduler, firstRequest flag | First request has zero debounce; later replacements delay successful results, not request admission | Replaced for Search with cancellable result delay and injected test clock | First-load, rapid/slow typing, cancelled delay |
| Former Search `paginate` outer switchMap | New query replaces prior result stream | Replaced with Feature-owned latest-query task + request identity check | Adverse-order old/new completion, including cancellation-ignoring provider |
| Former Search `paginate` inner switchMap, mutable cursor | Cursor-based append | Replaced: equivalent in-flight pages share completion; query replacement supersedes pages | Pagination overlap/interleaving and no-cursor tests |
| Former Search `paginate` delayed materialised results | Injectable API latency; spinner terminates on error | Replaced: injected delay/provider gates + Feature state/error/identity-checked cleanup | Failure, cleanup and retry tests |
| Former Search `ApolloClient+RAC.fetch` | Ignored Apollo cancellable | Search now uses cancellation-aware provider/bridge; other consumers remain legacy | Transport cancellation and exactly-once completion race tests |
| `AsyncApolloClient.fetch` | Existing checked-continuation API also ignores cancellable; @unchecked Sendable is pre-existing | Audit before reuse, including GraphQL errors/nil data | No assumption that native-looking async API preserves reactive error policy |
| Category cache and FetchCategoriesUseCase | Cached category read, conditional remote load | Preserve one authoritative cache/provider owner | Cached/uncached/failure checks |
| FetchLocationsUseCase switchMap | Replacement for non-empty location query; empty text separately emits [] | Feature-owned latest-location-query operation | Clear-query/late-result race characterisation needed |
| Reachability/feature flag streams | Banner presentation updates; not a search data request | Preserve existing compatibility adapter until separately migrated | BEH-S11 |
| Search analytics signal combinations | Visit/query/card events depend on timing and result/page signals | Preserve tested event contract through injected tracking dependency | BEH-S09; local fake, no external events |

AppModel, SearchFeature, its provider and SearchViewModel are MainActor-isolated.
SearchFeature retains one identified request Task, not a reactive subscription.
AsyncSearchProjectsProvider only awaits the transport. Search output signals are
a compatibility projection, never request executors. Generic paginate remains
for other consumers; app-wide queues, callbacks, persistence and other features
still require their own inventories.

## Baseline environment and commands

- Xcode 26.2 (17C52); iPhone Air Simulator, iOS 26.2.
- Library package uses Swift tools 6.2 with Swift 5 language mode; project
  configurations also specify Swift 5. No explicit strict-concurrency or default
  actor-isolation setting found in the inspected project file. A completed
  Swift 6/complete-concurrency validation is not claimed.
- Public demo commit: `5ad48326904a4033e1b06ab21cb0942c51b077fe`.
- Initial command used `Library-ios` and failed scheme lookup. `xcodebuild -list`
  reports the correct spelling `Library-iOS`; the on-disk filename is misleading.
- The corrected run repeatedly trapped in `TestCase.preferredSimulatorCheck`,
  line 111, before Search assertions: the helper requires iPad mini (A17 Pro),
  iOS 18.6. Available runtimes contain iOS 26.2 only. Stopped the crash loop;
  xcodebuild exited 73 after interrupted-result-bundle finalisation failed.
  `/private/tmp/kickstarter-search-baseline-tests-2.xcresult` is incomplete.
- Added an explicit non-visual-suite opt-out for SearchViewModelTests,
  SearchFiltersUseCaseTests and PaginateTests. All other suites retain the
  snapshot reference-device guard. No behavioural assertion was removed or
  converted to a skip; parallelism was not disabled.

Focused run: **passed, 67 tests, zero failures**, exit 0. The result bundle's
metrics and action status were checked with `xcresulttool`. The run reports 189
warnings; this is not a warning-free build, full-suite pass or snapshot validation.
The new initial-error/recovery characterisation passed without changing the
existing behaviour assertions.

```sh
xcodebuild -project Kickstarter.xcodeproj -quiet -scheme Library-iOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=705FC8E7-21E4-4E27-818E-AE9723290C56' \
  -derivedDataPath /private/tmp/kickstarter-cfa-baseline-derived-data \
  -disableAutomaticPackageResolution \
  -only-testing:LibraryTests/SearchViewModelTests \
  -only-testing:LibraryTests/SearchFiltersUseCaseTests \
  -only-testing:LibraryTests/PaginateTests \
  -resultBundlePath /private/tmp/kickstarter-search-baseline-tests-3.xcresult \
  test CODE_SIGNING_ALLOWED=NO
```

## Next migration gates

1. Non-visual baseline established: 67 tests passed, including initial failure
   and recovery. Characterise additional uncovered interleaving paths alongside
   the replacement; keep failures recorded rather than rewriting expectations.
2. Request ownership, filter selection/reset and query composition are now
   connected through SearchFeature. Category/location lookup collaborators remain
   reactive; their existing cache ownership and presentation are preserved.
3. Native Search execution is now connected and tested (checkpoint below).
   Next migrate category/location lookup execution; characterise empty-query/late
   location completion before changing it. Reactive selection and presentation
   adapters remain explicit follow-on work.
4. Compare all contract requirements, run relevant regression/snapshot suites
   on their supported runtime, and manually verify search/filter/detail/recovery.
5. Commit verified milestones and pin the external case-study record. Do not
   call the full app migrated while other features or these gates remain open.

## Search request-ownership checkpoint

- Concrete MainActor SearchFeature owns requests, collected projects, count,
  loading and retained errors. AppModel exposes only this migrated Feature.
  SearchViewModel accepts a narrow Feature dependency; its live default resolves
  inside the actor-isolated initializer. Tests build isolated feature graphs.
- GraphQL query mapping moved into the Model feature folder. The provider resolves
  the current API environment at request time, preserving account/demo selection.
- Generic reactive pagination, debounce and event ordering remain in use.
  Newest-query subscription disposal is preserved; physical Apollo cancellation,
  shared equivalent page execution and directly awaitable commands are NOT done.
- UIScheduler is the explicit main-queue compatibility boundary. State observers
  assert MainActor isolation there. This is not complete Swift 6 safety validation.
- Composition starts no request. Search remains demand-loaded on its existing
  lifecycle; no artificial launch task was introduced. Full AppModel lifecycle
  alignment awaits the app-wide migration.
- UIKit, storyboard, card equality, navigation and analytics expectations remain
  unchanged. Errors are retained by the Feature without inventing new error UI.

Verification on 26 October 2026:

1. Test attempt 1 failed compilation: generic cursor inference required an explicit
   return type. A Swift 5 actor-isolated default-argument warning was also corrected.
2. Attempt 2 failed compilation: new tests required the existing fixture helper
   import and testable KsApi access. No assertion was weakened.
3. Attempt 3 passed: **74 tests, zero failures**, exit 0, xcresult action succeeded.
   Original 67 regression tests plus six Feature and one AppModel test. This run
   reports 1,783 warnings across the dependency/project build; not warning-free.
4. Debug Kickstarter iOS Simulator build passed, exit 0. Not a Release/device build.
5. Agent smoke-tested discovery, Forest search (three results), empty search,
   Cancel returning to discovery, Newest sort selection, Paper Cities detail and
   return to Search. Sort selection was observed, not an ordering comparison.
   The existing restricted-creator demo banner remains a fixture limitation.

The passing test command is the baseline command above with these extra selections
and a fresh result bundle:

```sh
-only-testing:LibraryTests/SearchFeatureTests \
-only-testing:LibraryTests/AppModelTests \
-resultBundlePath /private/tmp/kickstarter-search-feature-tests-3.xcresult
```

App build: same project, Debug destination and derived data; scheme
`Kickstarter iOS`, action `build CODE_SIGNING_ALLOWED=NO`, result bundle
`/private/tmp/kickstarter-search-feature-build-1.xcresult`.

Local draft evidence: sibling `Migration Evidence/kickstarter-search-request-ownership`.
It records failed attempts, passing checks and screenshots; it is not a reviewed
precedent or part of the app commit. Full suite, snapshots, real devices,
VoiceOver, live APIs and transport cancellation remain unverified.

## Filter selection checkpoint

SearchFilterSelection owns selection/reset rules and is privately mutated through
SearchFeature commands. SearchFeature builds query parameters and owns the legacy
category/location lookup collaborators. SearchFiltersUseCase only translates
pills/modals and projects selection into the existing SearchFilters UI model.
The screen's query text remains presentation input; the Feature interprets it.
The existing category cache is reused, not copied into a second store.

Baseline: e2ec966d87c2f356a90b8fd6328bc3eeb151622d (74 passing tests).
Focused test runs use the prior five-suite command with fresh result bundles:

- filters-tests-1: 74 tests, 8 failures. Initial query observer placement changed
  page-view analytics ordering. Corrected production event wiring; old assertions
  were not weakened.
- filters-tests-2: original 74 passed.
- filters-tests-3: 77 tests, two new test expectations failed. Original mapping
  intentionally encodes an unselected toggle as nil (no filter), not false
  (exclude matching projects). Corrected the new tests to the existing mapping.
- filters-tests-4: **77 passed, zero failures**, exit 0. Includes three direct
  Feature selection/reset tests. Result bundles are under /private/tmp with the
  prefix kickstarter-search-. Builds remain warning-heavy; no full-suite claim.

No visual files, strings or navigation were changed. A fresh rendered check is
still pending at this filter-only checkpoint; the following async checkpoint
will repeat the app build and Simulator journey. Lookup cancellation and the
generic reactive pagination pipeline are still separate migration work.

## Cancellation-aware Search transport checkpoint

Filter checkpoint: `00ffa766990859699f64c1f482aef4f4a0ff39f0`.
The live AppModel now selects AsyncSearchProjectsProvider. Its async fetchPage
calls the Search-specific Service.fetchSearchPage requirement. Production Service
uses SearchQueryRequest to bridge Apollo's cancellable; existing mocks use a
default async implementation. Unrelated GraphQL operations are unchanged.

- A subscription owns one retained Task. Replacement/disposal cancels it; the
  production bridge cancels Apollo's token and resumes the await with cancellation.
- PendingSearchQuery uses a narrowly documented NSLock-protected unchecked
  Sendable boundary. Terminal completion is exactly once, including cancellation
  before continuation/token registration and duplicate/late callbacks. Cancellation,
  continuation resumption and token release occur outside the lock.
- GraphQL errors still take precedence over partial data; missing data and
  transport errors retain the legacy Search parse-error mapping. Cancellation is
  interruption, not a new user-visible error.
- The existing debounce operator delays results rather than request admission.
  Its behaviour and pagination/analytics pipeline remain unchanged. Feature
  commands are not yet directly awaitable and equivalent pages do not yet share
  completion. Category/location requests retain their legacy implementation.

Verification, 26 October 2026, Xcode 26.2, iPhone Air Simulator iOS 26.2:

- async-tests-1: 86 passed, zero failures. Added the end-to-end replacement/token
  cancellation test; async-tests-2: 87 passed, zero failures.
- After moving token release outside the lock, async-tests-3: **87 passed, zero
  failures**, exit 0; xcresult action succeeded. The incremental run reports two
  warnings; earlier broader dependency recompilation reported 2,331 warnings.
- Use the five-suite filter command plus
  `-only-testing:LibraryTests/SearchRequestCancellationTests`, with result bundle
  `/private/tmp/kickstarter-search-async-tests-3.xcresult`. Same Debug configuration,
  derived data and simulator; shareable destination spelling is
  `platform=iOS Simulator,name=iPhone Air,OS=26.2` (local identifier omitted).
- Kickstarter iOS Debug Simulator build passed, exit 0, result bundle
  `/private/tmp/kickstarter-search-async-build-1.xcresult`; app installed/launched.
- Agent smoke: discovery cards; Forest query returns three results; Games category
  narrows to one; clearing resets category and discovery; Zzznomatch displays the
  existing no-results message. Existing sheet/cards/tab presentation retained.

Coverage boundary: original ViewModel/filter/pagination suites still use the
legacy deterministic provider. New tests exercise the async provider through the
Feature and controlled transport callbacks/tokens. They do not establish every
async ViewModel/analytics interleaving or real-network cancellation. No full suite,
snapshot comparison, physical device, VoiceOver or complete Swift 6 check claimed.
No UI implementation files were changed. Local unreviewed draft evidence lives in
sibling `Migration Evidence/kickstarter-search-filters-async`; no push/publication.
## Awaitable Search pagination checkpoint (26 October 2026)

Baseline: `0b40a80879803655bd432e5510d7388ce013dbb3` (87 tests).
This section supersedes earlier checkpoints' statements that Search pagination
is reactive or that baseline screen tests use LegacySearchProjectsProvider.

- `await search(parameters:)` and `await loadNextPage()` wait for the actual
  operation, including result delay, state publication and loading cleanup.
  They do not merely enqueue a signal. Errors remain retained Feature state.
- Feature owns parameters, cursor, accumulated cards, count, request identity and
  task. Equivalent in-flight first pages/pages join the same task; new queries
  explicitly cancel previous tasks. Old completion/cleanup cannot publish over
  or clear a newer operation. An in-flight first page is joined by page demand;
  an old cursor is never applied to a new query.
- Cancellation of one awaiter does not cancel the app-owned shared operation.
  That waiter still awaits shared completion. New queries, explicit
  `cancelSearch()`, or Feature deinit own operation cancellation. An already
  cancelled caller starts no work. This is intentional policy, not automatic
  disappearance cancellation; completed Search results survive returning.
- Internal synchronous admission methods return the same task to the existing
  UIKit callback adapter, preserving immediate clearing/loading. ViewModel retains
  those handles and clears them when loading finishes; it creates no wrapper
  task and does not cancel shared Feature work on deinit.
- Removed Search's reactive provider adapter and LegacySearchProjectsProvider.
  Native delay preserves first-request/no-debounce and later successful-result
  delay semantics; failures receive API delay only. Count/page/results/loading
  event order is protected by the original analytics assertions.
- Generic `paginate` and its tests remain for other consumers. Category/location
  lookups, selection/query signal projections and UIKit presentation/analytics
  adapters remain reactive. No visual files, strings or routes changed.

Verification:

- Baseline: 87 tests passed.
- awaitable-tests-1/-2 failed compilation: inaccessible ReactiveSwift interval
  conversion, then selection of its async scheduler overload. Added explicit
  interval conversion; kept lookup-fixture scheduler draining synchronous.
- awaitable-tests-3: 93 tests, three failing screen tests (`testFlow`,
  `test_flow_sort`, `test_flow_filterByCategory`). Those tests installed the
  next mock after submitting a query, relying on deferred legacy scheduling.
  Moved fixture installation before admission. No behavioural assertion changed.
- awaitable-tests-4/-5: 93 passed each. Added task-handle cleanup assertions;
  removed redundant fixture waits and unnecessary async-environment warnings.
- Final awaitable-tests-6: **93 passed, zero failures**, exit 0 and xcresult action
  succeeded. Six incremental warnings (earlier broader run 5 reported 369):
  not warning-free, and not a full-suite result.
- Kickstarter iOS Debug Simulator build passed, exit 0; bundle
  `/private/tmp/kickstarter-search-awaitable-build-1.xcresult`. App installed and
  launched on the same simulator.
- Agent smoke: Search discovery; scrolling to later-page Edition 3 cards through
  Neighbourhood Sounds; Forest query three results; Games one result; clearing
  resets category/discovery; Zzznomatch empty state; Solar Sketchbook detail and
  return to Search. No pixel diff, exhaustive sorting or live API check.

Commands use the six-suite async checkpoint selection, fresh bundle names
`/private/tmp/kickstarter-search-awaitable-tests-N.xcresult`, and
`-test-timeouts-enabled YES -default-test-execution-time-allowance 60` for runs
5 onward. Test request/delay arrival gates use two-second XCTest timeouts and
release pending continuations in cleanup; no arbitrary sleeps or yield polling.
The original SearchViewModel regressions now run through AsyncSearchProjectsProvider
and native Feature execution with an explicitly advanced result-delay clock.
Six additional Feature tests exercise shared await completion, cancelled waiters,
page/query interleaving, explicit cancellation/retry, already-cancelled callers
and no-cursor/no-initial-request no-ops. Transport race tests remain enabled.

Evidence is a local unreviewed draft in sibling
`Migration Evidence/kickstarter-search-awaitable-pagination`. It records failed
attempts as well as passing checks. No full-suite/snapshot, real-device, VoiceOver,
live-network, performance or complete Swift 6 validation is claimed.
## Category/location lookup checkpoint (26 October 2026)

Baseline commit: `eddcbeeef1abc581a22617906dfe7b07c01f1091`.

Implementation:
- SearchFeature owns categories, defaults and suggestions as separate snapshots,
  loading flags, errors and identified tasks. Equivalent option/query requests
  share completion. Distinct queries cancel and invalidate old work.
- Empty location text is now a superseding command, rejecting late success,
  failure and cleanup; whitespace remains a non-empty query. Successful previous
  suggestions stay visible during another non-empty lookup or its failure.
- Category reads/writes use the existing KSCache key, not another store. Nonempty
  cache hits publish synchronously; empty caches fetch. Only accepted, uncancelled
  category results can write the cache.
- Defaults and categories execute independently. Defaults request five results;
  suggestions request ten. Category API delay remains independently injectable.
- Service opts the three Search lookups into the verified Search Apollo bridge,
  now generic over payload type; legacy API consumers remain unchanged. Native
  category mapping is shared with the legacy envelope producer.
- SearchViewModel retains the exact Feature-owned option/location task handles.
  No screen, storyboard, user-facing string, navigation or styling changed.
- Fourteen new SearchLookupTests and one location-payload cancellation test are
  passing in the 114-test run below. They cover stale results/errors, sharing, cancellation,
  retries, empty/cached categories, independent publication and mock mapping.
- Legacy category use case remains live for Explore. The now-orphaned legacy
  location use case and its three tests are deliberately retained until the new
  coverage passed alongside them. Removal is a separate cleanup requiring a rerun.

Initial verification attempt (superseded by the successful run below):
- Baseline attempt exited 74 before compilation: Simulator service connection
  and SwiftPM/Clang cache writes denied by the execution sandbox. Escalation is
  disabled in this session. No fresh tests or simulator smoke have run.
- Swift frontend syntax parsing of changed Swift files passed. Project plist
  validation and `git diff --check` passed. These do NOT establish type checking,
  a successful build, test execution, correct UI behaviour or Swift 6 safety.
- The last verified checkpoint remains the prior 93-test run, not these changes.
- Local draft evidence: sibling `Migration Evidence/kickstarter-search-lookups`.
  Its `verify.zsh` runs all nine relevant nonvisual suites, then the app build,
  on iPhone Air/iOS 26.2. New xcresult/log paths are printed at startup.
- After tests/build pass, smoke-test default locations, type/change/clear a
  location query, select a category/location, close/reopen filters, and verify
  Search results/paging still work. Record limitations and commit this slice.

### Successful Terminal verification (26 October 2026, 23:20)

Matthew Thomas ran the prepared verification script in Terminal. The agent read
the resulting xcresult objects and individual test records directly:

- `/private/tmp/kickstarter-search-lookups.lZhg0s/tests.xcresult`:
  test action succeeded; **114 tests, all 114 Success, zero failures or skips**.
  This includes all 14 SearchLookupTests and the new location-payload cancellation
  test. The test/build result reports 1,798 warnings; not warning-free.
- `/private/tmp/kickstarter-search-lookups.lZhg0s/build.xcresult`:
  buildResult.status = succeeded, no errors, three incremental warnings.
- Runtime: iPhone Air Simulator iOS 26.2, Xcode 26.2, Debug public demo,
  Swift 5 language mode. Nine selected suites, not the full suite.
- No Swift implementation or test changes were made after this run; only
  evidence and progress documentation were updated before committing.
- The modern xcresult summary command attempted a denied TestReport cache write;
  the read-only legacy object API successfully provided counts and every test
  status. No permission workaround or rerun was needed.

Manual filter smoke checks, snapshots, real device/live API and complete Swift 6
validation remain outstanding. A passing checkpoint is not migration completion.
Keep the tested legacy location reference until the next separately verified
cleanup; its replacement behaviour now has passing equivalent tests.
The entire migration remains in progress. No push or publication performed.

### Category/location smoke and orphan cleanup (26 October 2026)

Installed Debug demo, iPhone Air / iOS 26.2: Art selection updates results/count;
default locations appear; Los produces Los Angeles, clear removes suggestions,
Port produces Portland. Selection survives reopening. Art + Portland shows the
empty result screen; resetting location restores results while preserving Art.
Category reset disables Reset. No UIKit layout, navigation or copy changed.
These checks are bounded interactions, not full snapshot or late-response tests.

Removed the unused FetchLocationsUseCase and its three obsolete tests, plus
their Xcode references/group. Git retains the deleted files. The 14 passing
SearchLookupTests cover their outcomes plus cancellation/races. Explore's
FetchCategoriesUseCase stays because it has active callers.

Fresh cleanup verification exited 74 before compilation: Simulator service and
SwiftPM/Clang cache access denied. No test/build pass is claimed for this deletion.
Project plist, script syntax, whitespace and stale-reference checks passed.
Evidence: sibling Migration Evidence/kickstarter-search-lookup-cleanup.
Run its verify.zsh from Terminal (eight suites, expected 111 tests, then app build).
Commit only after verification. Next: reactive selection/query projections with
reset event order and analytics/request semantics preserved. Migration incomplete.

### Cleanup verification confirmed — 27 October 2026

Matthew Thomas ran verify.zsh in Terminal; results were inspected directly:
`/private/tmp/kickstarter-search-lookup-cleanup.PQ3So7`.
The run completed on 26 October at approximately 23:55; confirmation was supplied
after midnight. Tests: 111 individual Success records, zero failures/skips.
App buildResult.status: succeeded. Test result reports 1,783 warnings; app build
reports three (Crashlytics script outputs, absent Frameworks search path, and
extension/host CFBundleVersion mismatch). No warning-free claim.
Only progress/evidence documentation changed after the successful run.
The earlier sandbox-blocked attempt remains recorded, superseded by this result.
This verifies the bounded orphan cleanup, not whole-Search or whole-app completion.

## Selection state and direct query construction — 27 October 2026

Baseline: d4cf779797b9975eaa487910fd30fa55417b0da2, 111 tests and app build passed.
Route remains SearchViewController → SearchViewModel → AppModel.searchFeature →
SearchFilterSelection (existing internal policy) / existing async providers.

- Filter choices now use ordinary main-actor stored values, not MutableProperty.
  Existing signal pipes only publish compatibility events. No new type or Task.
- SearchFeature.queryParameters(for: String) reads current selection directly:
  no subscriber, initial signal, network call or UI object is required.
- The legacy signal overload delegates query construction to that native API.
  Its initial-emission barrier remains, as do per-field reset order, duplicate
  events, optional false→nil semantics and the existing UIKit/analytics bindings.
- Six new Feature tests cover direct defaults/all fields/toggles, reset-all versus
  clear, scoped reset, initial adapter gating and ordered duplicate emissions.
  Existing three projection tests and all wider focused tests remain unchanged.
- No UI, persistence, transport, identifiers or error-delivery changes.

This is NOT completion of reactive removal. SearchViewModel still owns query-text
input signals, lifecycle/analytics projections and the request subscription.
The presentation adapter and toggle-output combineLatest remain deliberately.
Next: migrate that input/publication route after this checkpoint passes.

Swift syntax parsing, project plist, zsh syntax and diff checks passed.
Fresh verify.zsh attempt exited 74 before compilation: Simulator service/cache
access denied in the execution sandbox. No new test/build/manual pass claimed.
Output: /private/tmp/kickstarter-search-selection-state.ckH4Ho.
Evidence and repeatable script: sibling Migration Evidence/kickstarter-search-selection-state.
Expected 117 tests in eight suites plus app build; verification remains pending.
Matthew Thomas explicitly requested a checkpoint commit before this verification.
This saves work only: it does not establish a passing build, tests or completion.

### Selection-state and adapter baseline verified — 27 October 2026

Matthew Thomas ran the script in Terminal. Direct inspection of
`/private/tmp/kickstarter-search-selection-state.jLK7ZB` confirms 123 individual
Success test records, zero failures/skips, and app buildResult.status succeeded.
This verifies the selection-state implementation at 900b455b5 and the six new
SearchViewModel characterisation tests added before any adapter implementation.
Seven test-build warnings and three app-build warnings remain; no warning-free
claim. No additional manual UI or snapshot validation was performed.

The tests establish: animated=false does not initialise discovery or track a
page; the first animated=true replaces early text without clearing filters;
appearance before initial filter publication does not backfill analytics;
returning while loading preserves the request and uses the last published count;
a failed query adds no completion event; card clicks include current filters.
The misleading old variable name "viewWillAppearNotAnimated" actually filters
true. Preserve that behaviour rather than silently correcting it.
The earlier permission-blocked runs remain historical evidence, not regressions.

## Explicit Search input/lifecycle adapter — 27 October 2026

Route unchanged: SearchViewController → SearchViewModel → SearchFeature → providers.
SearchViewModel owns presentation query text and emitted-data snapshots, first
animated appearance, pagination threshold crossing, navigation and analytics
adaptation. SearchFeature still owns filter policy, async work/cancellation and
shared domain state. No new type, task, storage, identifier, transport or UI file.

Removed three input MutableProperty values, the tapped-index pipe, two tuple-heavy
navigation/click chains and the appearance analytics chain. Input methods now use
ordinary state and synchronous commands. Output-only query/appearance/navigation
pipes remain for the unchanged UI. First appearance and typed clearing remain
distinct commands; neither repeated appearance nor a row still near the bottom
starts fresh work. Observer handles are retained/disposed by the ViewModel.

The six characterisation tests remain unchanged in substance. Added
testPaginationRequiresAnotherThresholdCrossingAfterPageCompletes, covering the
three-row threshold, duplicate notification, task retention, threshold re-entry,
accumulated cards and no extra discovery page-view analytics.

Static checks passed: Swift parsing, project plist, script syntax, whitespace.
Fresh post-change verification exited 74 before compilation: Simulator/cache
permissions denied. Results: /private/tmp/kickstarter-search-lifecycle-adapter.WAFG2l.
No post-change runtime/manual pass claimed. Run sibling Migration Evidence/
kickstarter-search-lifecycle-adapter/verify.zsh (expected 124 tests and app build).
Changes remain uncommitted until verified; baseline commit is 925b2a36e.

Remaining: result-completion analytics still uses zip(hasResults, page), parameter
projection still combines query and selection outputs and drives request admission,
and filter/UI/reachability presentation adapters remain reactive. This pass does
not claim all query or analytics plumbing is migrated. Characterise buffered
page/result pairing, zero-count pages, errors and supersession before replacing it.
Whole-Search and whole-app migration remain in progress.

### Adapter verification confirmed — 27 October 2026

Matthew Thomas ran verify.zsh in Terminal. Direct inspection of
`/private/tmp/kickstarter-search-lifecycle-adapter.OvyAOX` confirms 124 individual
Success records, zero failures/skips, including the new threshold-crossing test.
App buildResult.status succeeded. The test build reports 567 warnings and the
app build reports three; no warning-free claim. No production/test source changed
after this run. This supersedes the permission-blocked attempt above.

The automated checkpoint is ready to commit. No new manual UI, snapshot,
physical-device, live-API or full-suite validation was performed. These remain
separate completion gates, not facts inferred from the focused test run.

## Explicit result-completion analytics — 27 October 2026

Verified baseline: acb105498d341705f5d909fe4fc1563e9e7d3d1c.
Replaced the result-completion combineLatest/zip/takeWhen chain with a private
SearchCompletionAnalytics compatibility helper in SearchViewModel.swift.
It owns only notification pairing and counts; the Feature retains domain state,
requests, cancellation and pagination. No new Task, transport, UI or dependency.

Zero counts publish separately, including an empty terminal page retaining cards.
Page ordinals pair FIFO with settlement notifications, even across query changes.
Empty/error notifications can remain buffered and cause a later first-page event
before card publication/loading=false. This source-inferred legacy behaviour is
preserved rather than silently changed to one event per successful request.
ViewModel analytics uses the current query/filter snapshot at emission time.

Three new end-to-end tests cover repeated empty searches, empty terminal paging,
and event ordering on recovery after empty/failed queries. Existing 124 tests
remain unchanged. The new cases have not yet run against either implementation.
BEH-S09's broad wording is qualified by SEARCH-ADAPTER-08 through -10.

Swift syntax, project plist, verification-script syntax and whitespace checks
passed. Fresh verification exited 74 before compilation due to Simulator/cache
permissions: /private/tmp/kickstarter-search-completion-analytics.x5EiiS.
No post-change test/build pass is claimed. Matthew Thomas has been asked to run
sibling Migration Evidence/kickstarter-search-completion-analytics/verify.zsh
(expected 127 tests, then app build). Keep this code stable during that run.
Evidence remains a local draft. Migration remains IN PROGRESS.

### Completion-analytics verification confirmed

Matthew Thomas ran the script in Terminal. Direct inspection of
/private/tmp/kickstarter-search-completion-analytics.dVAhV6 confirms 127 individual
Success records, zero failures/skips, including all three new cases. App
buildResult.status succeeded. The test build reports 1,589 warnings and the app
build three; no warning-free claim. No Swift files changed after this run.
This supersedes the permission-blocked result, not the remaining manual or wider
migration gates. The new cases passed the replacement; an old-code differential
run has not been performed. Proceed to the filter presentation adapter.

## Filter presentation adapter — verification pending

Baseline: 015444a6eb452beeabdcc4519d45b9d1e675b913 (127 tests and app build).
SearchFiltersUseCase no longer copies lookup arrays into three MutableProperty
instances. Feature outputs update the existing SearchFilters model directly,
preserving observeForUI delivery, empty replacements and duplicate notifications.
Pill taps directly toggle the Feature or publish the existing modal mapping.
The selection projection, initial-publication barrier and query admission remain
unchanged; this is not yet removal of the remaining parameter adapter.

The adapter now retains/disposes four observations. A presentation model retained
beyond its adapter no longer receives updates; this is an explicit owner-lifetime
cleanup, not an active-screen UI change. Three new tests cover refresh/clear
retaining selection, repeated-value notifications and release cleanup.
No new types, tasks, dependencies or UI files. Swift parsing, plist, whitespace
and script syntax checks passed. No post-change runtime pass yet. Matthew Thomas
is running sibling Migration Evidence/kickstarter-filter-presentation/verify.zsh
(expected 130 tests and app build). Keep source stable until it finishes.
Remaining query, UI/manual and app-wide migration gates remain open.

### Filter presentation verification confirmed

Direct inspection of Matthew Thomas's Terminal run in
/private/tmp/kickstarter-filter-presentation.iBVlAx confirms 130 individual
Success records, zero failures/skips, including all three new tests. The app
buildResult.status succeeded. Both test-build and app-build report three warnings.
No Swift source changed after this run. No manual/snapshot/full-suite pass.
The new observer-release guarantee is now runtime-protected.

Next query-adapter constraints from source review: parameter publication must
precede request admission, because cancellation/loading can emit analytics
synchronously; empty text publishes before the ten reset fields and final sort;
initial query admission waits for every selection output; identical assignments
remain observable. Repeated initialisation and a new ViewModel attached to an
already-used Feature need explicit tests before replacing this barrier.
Do not introduce a second owner for shared selection or coalesce notifications
as an incidental cleanup. Keep existing UI projection until its contract is met.
Session-level Simulator/cache access still prevents autonomous verification.
This access limitation is not a migration completion or code-failure claim.

## Explicit query admission — implementation pending verification

The live ViewModel now admits requests through refreshSearchIfReady, constructing
parameters with the native Feature API. Query input calls it directly; selection
notifications call the same command. Eight selection outputs retain their
per-screen initial barrier. Parameters/analytics snapshot and empty-state
parameter publication occur before request admission; query UI notification
follows admission, and typed empty-query resets occur last, as before.
No new types, tasks, protocols, shared state owners or UI files.

Three new tests cover early typing before initial selection, repeated load
retaining query/selection, and a new screen attached to an already-used Feature.
The legacy Feature signal overload is no longer used by the live screen; it is
temporarily retained with its reference tests until verified cleanup preserves
their coverage. Native Feature query construction and async requests are unchanged.

Agent initiated sibling Migration Evidence/kickstarter-query-admission/verify.zsh.
It exited 74 before compilation: CoreSimulator/cache permissions blocked access.
Output: /private/tmp/kickstarter-query-admission.GR09g5. Swift parsing, project
plist, script syntax and whitespace checks passed; 133 tests and app build have
NOT passed yet. Leave this implementation uncommitted until verified.
Last verified code remains 849495b7a; migration remains IN PROGRESS.

Matthew Thomas requested continued migration and checkpoint commits despite the
verification access blocker. Save the query-admission implementation as an
explicitly unverified checkpoint; this does not change its test/build status.
Consolidate the remaining Search close-out. Removing all presentation signals is
not a prerequisite: retained UIKit/SwiftUI compatibility must have an explicit
reason and owner, rather than become an open-ended reactive-code rewrite.
