# CFA migration ledger

Author: Matthew Thomas. Updated 26 October 2026.

## Scope and first boundary

Search is the first selected feature because its existing tests exercise query
replacement, filters, paging, loading, navigation metadata and analytics.
The baseline is committed at `192fa9148ebec7409c9245354b206d344edc1e50`.
Request ownership and filter selection/reset/query composition are extracted.
Search page transport now uses cancellation-aware async requests. This is not a
complete Search migration: pagination/debounce still use a reactive adapter.

Current project-request route:
`SearchViewController → SearchViewModel → AppModel.searchFeature → AsyncSearchProjectsProvider → Service.fetchSearchPage → Apollo`.
SearchFeature owns selection policy and the legacy category/location lookup
collaborators. SearchFiltersUseCase is now a screen presentation adapter.

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
| Search | SearchViewController / SearchViewModel | AppModel.searchFeature / SearchFeatureTests | Request/selection ownership extracted; async page transport connected; reactive pagination pending |
| Profile (signed in/out variants) | Profile/account flow | AppModel.profileFeature / ProfileFeatureTests | Legacy; inspect authentication ownership first |

`RootViewModel.generateViewControllers` omits Activity when the floating-tab
flag is enabled. Preserve this actual flag/session-dependent composition. A tab
is not permission to duplicate shared user, pledge or project state.

## Search concurrency inventory (not an app-wide inventory)

| Mechanism and source | Existing guarantee or limitation | Planned ownership/replacement | Required protection |
| --- | --- | --- | --- |
| `SearchViewModel` combineLatest query/filter signals | Any change rebuilds full request parameters | SearchFeature owns query/filter domain state | BEH-S04/S05; all filters and reset behaviour |
| `ksr_debounce`, environment scheduler, firstRequest flag | First request has zero debounce; later replacements use configured interval | Explicit cancellable debounce with injected test clock | First-load, rapid/slow typing, cancelled delay |
| `paginate` outer switchMap | New query disposes prior result stream | Feature-owned latest-request-wins task + generation check | Adverse-order old/new completion, including cancellation-ignoring provider |
| `paginate` inner switchMap, mutable cursor | Cursor-based append; page requests can replace each other | Feature coalesces equivalent in-flight page loads; query replacement supersedes pages | Pagination overlap/interleaving and no-cursor tests |
| `paginate` delayed materialised results | Injectable API latency; spinner terminates on error | Provider/test gates + separate Feature operation/error properties | Failure, cleanup and retry tests |
| `ApolloClient+RAC.fetch` | Ignores Apollo cancellable; disposal suppresses values but does not establish transport cancellation | Cancellation-aware provider below Feature | Transport cancellation and exactly-once completion race tests |
| `AsyncApolloClient.fetch` | Existing checked-continuation API also ignores cancellable; @unchecked Sendable is pre-existing | Audit before reuse, including GraphQL errors/nil data | No assumption that native-looking async API preserves reactive error policy |
| Category cache and FetchCategoriesUseCase | Cached category read, conditional remote load | Preserve one authoritative cache/provider owner | Cached/uncached/failure checks |
| FetchLocationsUseCase switchMap | Replacement for non-empty location query; empty text separately emits [] | Feature-owned latest-location-query operation | Clear-query/late-result race characterisation needed |
| Reachability/feature flag streams | Banner presentation updates; not a search data request | Preserve existing compatibility adapter until separately migrated | BEH-S11 |
| Search analytics signal combinations | Visit/query/card events depend on timing and result/page signals | Preserve tested event contract through injected tracking dependency | BEH-S09; local fake, no external events |

AppModel, SearchFeature, its provider and SearchViewModel are MainActor-isolated.
The async provider retains a Task per subscription and cancels it on disposal.
ReactiveSwift pagination remains transitional. App-wide queues,
callbacks, persistence and other features still require their own inventories.

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
3. Replace model execution with directly awaitable commands, explicit latest-query
   identity, shared equivalent paging, cancellation ownership and tested cleanup.
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
