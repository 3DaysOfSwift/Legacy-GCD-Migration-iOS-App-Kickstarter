# CFA migration ledger

Author: Matthew Thomas. Updated 27 October 2026.

## Latest verified checkpoint

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

**Overall: Search, Explore and project-detail loading have verified implementation checkpoints.**
AppModel composes searchFeature, discoveryFeature and projectDetailsFeature.
No top-level product area has passed every manual/snapshot/strict-concurrency exit
gate. The latest combined checkpoint passed 324 tests plus an app build; eight
additional reward insertion/decoder tests passed. Bounded Simulator journeys are recorded above.
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
| Media, updates/comments and other project interactions | Legacy execution remains | Migrate connected reads next; preserve transaction ordering and navigation |
| Account/session, Profile, settings and authentication | Legacy; not migrated | One shared session owner, persistence/security contract, authenticated/signed-out tests |
| Activity, pledged projects and transactional flows | Legacy; not migrated | Shared backing state, ordering/idempotency, cancellation, retry and storage guarantees |
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
| Explore / discovery | Discovery controllers / DiscoveryViewModel | AppModel.discoveryFeature / DiscoveryFeatureTests | Legacy; not in this pass |
| Activity (signed out) | Activity flow | AppModel.activityFeature / ActivityFeatureTests | Legacy; inspect complete flow before migration |
| Pledged projects and activity (signed in) | Pledged-project/activity flow | Ownership to map with shared pledge state | Legacy; not an empty placeholder Feature |
| Search | SearchViewController / SearchViewModel | AppModel.searchFeature / SearchFeatureTests | Implementation consolidated; final 133-test/app-build and manual checks pending |
| Profile (signed in/out variants) | Profile/account flow | AppModel.profileFeature / ProfileFeatureTests | Legacy; inspect authentication ownership first |

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
