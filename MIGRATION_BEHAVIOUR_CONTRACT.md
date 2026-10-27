# Kickstarter migration behaviour contract

Author: Matthew Thomas. Baseline captured 26 October 2026 at
`5ad48326904a4033e1b06ab21cb0942c51b077fe` (public-demo preparation).
Original upstream: `5f5463cfb830413d253efed45bfcec0322c9f152`.

This contract covers Search. Ownership, filters, async transport and native awaitable pagination have
incremental checkpoints recorded below. It is not a complete app contract, nor proof
that authentication, payments or live APIs work. UIKit presentation is retained.
Test names below refer to `LibraryTests/Library/ViewModels/SearchViewModelTests.swift`
unless another suite is named. The ledger records exact commands and results.

| ID | Plain-English requirement | Legacy evidence | Evidence status | Baseline | Replacement protection | Post-migration result | Manual regression | Difference and approval |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BEH-S01 | Opening Search displays discovery results and the Discover projects title once data arrives. | `testFlow`, `testSearchLoaderIndicatorIsAnimating` | Confirmed | Passed, 67-test focused baseline | Retain assertions; add Feature success test | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Agent observed discovery cards and title on iPhone Air, iOS 26.2, 26 Oct | None |
| BEH-S02 | Changing the query immediately clears old cards and displays loading while the replacement request waits. | `testFlow`, `testCancelingOfSearchResultsWhenEnteringNewSearchTerms` | Confirmed | Passed, 67-test focused baseline | ViewModel presentation and Feature replacement tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | See bounded smoke checks below; remaining checks pending | None |
| BEH-S03 | Rapidly changing the query never lets an obsolete result replace the newest result. | `testCancelingOfSearchResultsWhenEnteringNewSearchTerms`, `testOrderingOfPopularAndDelayedSearches` | Confirmed | Passed, 67-test focused baseline | Controlled adverse-order completion and cancellation tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | Network cancellation itself is not established by these tests |
| BEH-S04 | Clearing the query resets filters and sort and returns to discovery results; changing to another non-empty query retains filters. | `testClearSearchText_clearsFilters`, `testEmptySearchText_clearsFilters`, `testChangingSearchText_keepsOriginalFilters` | Confirmed | Passed, 67-test focused baseline | Existing presentation assertions plus direct Feature selection/reset tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | None |
| BEH-S05 | Changing a sort or filter reloads results for the new selection and keeps its visible selection consistent. | `test_flow_sort`, `test_flow_filterByCategory`; `SearchFiltersUseCaseTests` selection/reset cases | Confirmed | Passed, 67-test focused baseline | Feature selections and existing filter presentation tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | None |
| BEH-S06 | Reaching the pagination threshold appends subsequent results in order and stops when no next cursor exists. | `testFlow`; `PaginateTests.testPaginateFlow`, `testPagination_StopsWhenCursorIsNil`, interleaving cases | Confirmed | Passed, 67-test focused baseline | Feature cursor, overlap and replacement tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | Current threshold is three remaining rows; repeated equivalent loads must share completion |
| BEH-S07 | A successful empty response displays the empty-result message; loading a new query hides it. | `testShowNoSearchResults` | Confirmed | Passed, 67-test focused baseline | Feature empty success and ViewModel empty/loading tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | Empty success must remain distinct from failure |
| BEH-S08 | Selecting a card opens the same project/prelaunch destination with the appropriate first-card/query ref tag. | Four `testSearch…_RefTag` cases; controller route; existing framework prelaunch tests | Confirmed | Passed, 67-test focused baseline; framework snapshots not run | Keep route/ref-tag assertions | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | No new routing design |
| BEH-S09 | Search analytics distinguish page visits, completed queries and card clicks, without counting pagination or cancelled queries as completed searches. | `testProjectCardClicked`, `testSlowTyping`, page-view tests, `testFlow` | Confirmed | Passed, 67-test focused baseline | Preserve event values/counts through local tracking fake | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Production analytics not exercised | Demo startup intentionally disables external SDKs |
| BEH-S10 | Leaving and returning to Search retains its current results rather than automatically fetching more. | `testFlow`, `testSearchPageViewed_ReturningAfterSearching` | Confirmed | Passed, 67-test focused baseline | ViewModel lifecycle and Feature ownership tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | Cancellation on disappearance must not discard completed results |
| BEH-S11 | The video-feed banner follows its feature flag and reachability, without repeated identical visibility events. | Three `testShowVideoFeedBanner…` cases | Confirmed | Passed, 67-test focused baseline | Preserve flag/reachability presentation tests | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | Do not replace real flags with demo assumptions |
| BEH-S12 | A failed initial request stops loading, and a later changed query can recover. | New `testFailedInitialSearchStopsLoadingAndRecoversOnChangedQuery`; existing discarded error output | Confirmed by new baseline test | Passed, 67-test focused baseline | Feature retained error/retry test and presentation contract | Native async Search checkpoint: automated tests passed; bounded manual evidence below | Pending | Silent error presentation is an existing defect candidate, not an approved final UX |

## Unresolved design and verification boundaries

- The current ViewModel has no error presentation for Feature failures. Preserve the distinction
  between an empty success and a failure in the new Feature. Do not invent a
  new error screen or claim that existing silence is the desired product UX.
- Existing names/comments describe "popular" discovery, but the filter
  implementation and its test default to `.magic`. Preserve actual tested
  selection; do not silently switch sort based on a comment.
- `viewWillAppearNotAnimated` currently filters `true`, despite its name.
  Preserve observed/tested lifecycle behaviour until explicitly resolved.
- Repeated filter reset emissions and debounce scheduling are observable in
  existing tests. Characterise their request and analytics effects before
  coalescing them; fewer calls alone is not proof of equivalence.
- Real-device timing, VoiceOver, logged-in filters, external APIs, all project
  destinations and snapshot comparisons remain separate validation gates.

## Bounded smoke checks after request extraction

On 26 October 2026, the agent observed discovery cards/title; Forest returning
three matches; a no-match query displaying the empty-state message; Cancel
restoring discovery; Newest selection showing its selected state; Paper Cities
opening the matching detail; and closing detail retaining Search cards/selection.
This supports parts of BEH-S01/S04/S05/S07/S08/S10, not every variant. No image
diff, rapid-typing timing measurement, complete filter journey, live API or
failure-UI test was performed. Newest ordering was not independently compared.

The Feature now retains errors separately from successful empty results. The
legacy ViewModel still has no new error presentation. Direct tests cover failed
first-page recovery, failed-page retry, cursor termination and obsolete
subscription completion suppression; they do not establish transport cancellation.

## Filter and async transport checkpoint (26 October 2026)

Historical checkpoint: this focused run passed 87 tests; the table now points
to the later native async checkpoint below. Three direct Feature tests now protect
BEH-S04/S05 query composition, reset-all retaining sort, empty-query resetting
sort, and toggle changes. The original presentation/analytics expectations remain
unchanged; a temporary analytics ordering regression was corrected in production
wiring before the filter commit (details in the ledger).

Ten additional tests protect Search's async transport and compatibility adapter:
exactly-once completion, cancellation before/during registration, cancellation
before invocation, GraphQL error precedence, nil/transport error mapping, mock
failure/recovery, Feature delivery, and query replacement cancelling its token
while ignoring late completion. This adds controlled transport evidence for
BEH-S03/S12, not a live-network or exhaustive async-screen verification claim.
Original baseline suites retain the legacy deterministic provider.

Fresh agent Simulator smoke on the async demo route observed discovery, Forest
returning three matches, Games narrowing to one, query clearing resetting category
and returning discovery, and the no-match message for Zzznomatch. This supports
BEH-S01/S04/S05/S07. No visual implementation changed; no pixel comparison was run.
Pagination/debounce, lookup cancellation and fully awaitable Feature commands
remain outstanding. Other manual gates in the table remain bounded as stated.
## Native awaitable pagination checkpoint (26 October 2026)

The current six-suite selection passes 93 tests. Existing ViewModel presentation,
navigation, lifecycle and analytics assertions now exercise the async provider and
native Feature execution, with a controlled result-delay clock rather than the
removed legacy provider. Three flow fixtures now install their service before
request admission; expectations were not weakened.

BEH-S02/S03/S06/S12 have direct adverse-order and retry coverage. Equivalent
in-flight first-page/page requests share one completion and append once. A new
query supersedes a pending page; its late completion cannot append or clear newer
loading. Explicit cancellation permits retry. Cancelled waiters do not cancel the
shared app-owned operation; they await its completion. Calls with no initial
query/next cursor are awaitable no-ops. Physical transport cancellation remains
covered by controlled callback/token tests, not live-network measurement.

Fresh agent smoke on the rebuilt Debug demo observed: Search discovery; scrolling
through later-page Edition 3 cards including Neighbourhood Sounds; query replacement
with Forest (three matches); Games (one match); clearing resets category/discovery;
Zzznomatch shows the existing no-results message; Solar Sketchbook detail opens and
closes back to Search. This supports BEH-S01/S04/S05/S06/S07/S08/S10 only for those
demo journeys. Pagination termination/repeated-load suppression is asserted in
tests, not inferred solely from a still screenshot. No pixel comparison, VoiceOver,
logged-in journey, error-UI injection or exhaustive destination check was run.

**Still incomplete:** category/location lookup execution and its races, remaining
reactive selection/presentation edges, full Search CFA review and broader validation.
Other app features remain outside this Search contract. Earlier checkpoint notes
about reactive pagination describe historical states, not the current implementation.
## Category/location lookup slice — automated verification passed

The initial baseline attempt was environment-blocked before compilation.
Matthew Thomas subsequently ran verify.zsh in Terminal. The agent inspected both
xcresult bundles: 114 tests passed (zero failures/skips), and the app build
succeeded. All 15 new tests passed. No fresh manual screen evidence is claimed.
See the ledger for paths, warning counts and runtime limitations.

| ID | Plain-English requirement | Legacy evidence | Evidence status | Baseline | Replacement protection | Post-migration result | Manual regression | Difference and approval |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BEH-S13 | Opening filters reuses nonempty cached categories; an empty cache fetches, and a failed lookup can be retried. | FetchCategoriesUseCaseTests (three cases), existing KSCache key | Confirmed | Fresh run blocked before compilation | SearchLookupTests cache/failure/retry cases | Passed in 114-test run | Pending | Same cache and category delay; no new error UI |
| BEH-S14 | Default locations appear independently of category loading; location queries return suggestions and clearing immediately empties them. | FetchLocationsUseCaseTests (three cases), query limits 5/10 in source | Confirmed | Fresh run blocked before compilation | SearchLookupTests initial outputs, independent defaults and live fixture mapping | Passed in 114-test run | Pending | Native commands replace reactive execution |
| BEH-S15 | Clearing or replacing a location query prevents obsolete results and failures from changing the current suggestions or loading state. | Legacy empty-query branch bypasses switchMap cancellation; source-confirmed stale-response route | Confirmed user-requested correction | Source diagnosis; no runtime reproducer run | SearchLookupTests clear/late success, clear/late error, old/new ordering and cleanup tests | Passed in 114-test run | Pending | Intended approved change: user explicitly requested stale responses after clearing be addressed, 26 Oct 2026 |
| BEH-S16 | Failed nonempty location lookups retain existing suggestions; retry can recover, and whitespace remains a submitted query. | FetchLocationsUseCase materialize/values, nonempty filter | Inferred from source | Fresh run blocked | SearchLookupTests failure/retry, whitespace and cancelled-before-admission cases | Passed in 114-test run | Pending | Preserve silent UI errors; Feature retains errors separately |
| BEH-S17 | Equivalent pending lookups share one execution and completion; cancelling one waiter does not cancel another caller's shared request. | New explicit Feature overlap policy | Confirmed migration policy | Not an existing tested guarantee | SearchLookupTests shared query/options and cancelled waiter; SearchRequestCancellationTests location payload | Passed in 114-test run | Pending | Same policy as the preceding native Search pagination checkpoint |

No new visual design is authorized. Legacy and replacement lookup tests passed
together; remove the orphaned legacy location code only in a separately verified
cleanup. Manual filter smoke, whole-Search and whole-app completion remain open
at that checkpoint; see the subsequent bounded smoke below.

### Subsequent bounded filter smoke — 26 October 2026

Installed public demo, iPhone Air / iOS 26.2: category options loaded; Art
selection changed results and count; default locations appeared. Los returned
Los Angeles, clear removed the suggestion, and Port returned Portland.
Selecting Portland alongside Art showed the empty-results screen with two
filters. Reopening retained Portland's selected radio/text. Resetting location
restored results while preserving Art/count 1. Category Reset became disabled
after clearing its selection.

This covers the visible normal/clear/reopen/reset paths, not injected failures,
cache persistence, simultaneous waiter cancellation or forced late responses.
BEH-S14 has bounded manual confirmation; BEH-S15's race guarantee still relies
on controlled tests. Other automated-only checks remain so.
No screenshot regression, physical-device or live-API verification is claimed.

The orphan location implementation and its three tests have now been removed
from the working tree, recoverable from Git. These manual checks use the
pre-cleanup installed binary. Fresh cleanup build/tests remain blocked by
execution permissions (exit 74 before compilation), not passed.
Whole-Search and whole-app migration remain incomplete.

Post-cleanup follow-up confirmed 27 October 2026: the user-run Terminal check
in /private/tmp/kickstarter-search-lookup-cleanup.PQ3So7 passed all 111 tests
(zero failures/skips) and the app build. This supersedes the cleanup execution
blocker above. No Swift or project changes followed that successful run.
Manual smoke remains bounded to the pre-cleanup binary; broader validation
and the rest of the migration remain outstanding.

## Selection-state checkpoint — verification pending, 27 October 2026

Ordinary main-actor state replaces reactive filter storage. Direct Feature query
construction must be usable without subscriptions/initial signals, must not start
IO, and must preserve query text, every selected field, page size 15 and false
toggles represented as nil. New native API tests cover these requirements.

Compatibility requirements retained, inferred from current source:
the signal projection waits for initial selection; reset-all emits category,
state, percent, location, amount, goal, following, recommended, projects-we-love,
saved in that order, retaining sort. Clear resets sort last. Repeated identical
assignments still emit. New initial-barrier and ordered-emission tests protect
these details; they are not permission to redesign the UI or analytics.

Six new tests plus the 111-test baseline are pending runtime verification.
Syntax parsing passed but is not a type-check or test result. The build attempt
was sandbox-blocked before compilation. Earlier manual smoke does not validate
these newly changed files. Query/lifecycle and analytics adapters remain in use;
the overall migration is still in progress.
