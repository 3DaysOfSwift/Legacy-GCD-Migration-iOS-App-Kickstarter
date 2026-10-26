# Kickstarter migration behaviour contract

Author: Matthew Thomas. Baseline captured 26 October 2026 at
`5ad48326904a4033e1b06ab21cb0942c51b077fe` (public-demo preparation).
Original upstream: `5f5463cfb830413d253efed45bfcec0322c9f152`.

This contract covers Search. Ownership, filters and async page transport have
incremental checkpoints recorded below. It is not a complete app contract, nor proof
that authentication, payments or live APIs work. UIKit presentation is retained.
Test names below refer to `LibraryTests/Library/ViewModels/SearchViewModelTests.swift`
unless another suite is named. The ledger records exact commands and results.

| ID | Plain-English requirement | Legacy evidence | Evidence status | Baseline | Replacement protection | Post-migration result | Manual regression | Difference and approval |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BEH-S01 | Opening Search displays discovery results and the Discover projects title once data arrives. | `testFlow`, `testSearchLoaderIndicatorIsAnimating` | Confirmed | Passed, 67-test focused baseline | Retain assertions; add Feature success test | Request-ownership pass: automated tests passed; async pending | Agent observed discovery cards and title on iPhone Air, iOS 26.2, 26 Oct | None |
| BEH-S02 | Changing the query immediately clears old cards and displays loading while the replacement request waits. | `testFlow`, `testCancelingOfSearchResultsWhenEnteringNewSearchTerms` | Confirmed | Passed, 67-test focused baseline | ViewModel presentation and Feature replacement tests | Request-ownership pass: automated tests passed; async pending | See bounded smoke checks below; remaining checks pending | None |
| BEH-S03 | Rapidly changing the query never lets an obsolete result replace the newest result. | `testCancelingOfSearchResultsWhenEnteringNewSearchTerms`, `testOrderingOfPopularAndDelayedSearches` | Confirmed | Passed, 67-test focused baseline | Controlled adverse-order completion and cancellation tests | Request-ownership pass: automated tests passed; async pending | Pending | Network cancellation itself is not established by these tests |
| BEH-S04 | Clearing the query resets filters and sort and returns to discovery results; changing to another non-empty query retains filters. | `testClearSearchText_clearsFilters`, `testEmptySearchText_clearsFilters`, `testChangingSearchText_keepsOriginalFilters` | Confirmed | Passed, 67-test focused baseline | Existing filter assertions passed; Feature filter extraction pending | Request-ownership pass: automated tests passed; async pending | Pending | None |
| BEH-S05 | Changing a sort or filter reloads results for the new selection and keeps its visible selection consistent. | `test_flow_sort`, `test_flow_filterByCategory`; `SearchFiltersUseCaseTests` selection/reset cases | Confirmed | Passed, 67-test focused baseline | Feature selections and existing filter presentation tests | Request-ownership pass: automated tests passed; async pending | Pending | None |
| BEH-S06 | Reaching the pagination threshold appends subsequent results in order and stops when no next cursor exists. | `testFlow`; `PaginateTests.testPaginateFlow`, `testPagination_StopsWhenCursorIsNil`, interleaving cases | Confirmed | Passed, 67-test focused baseline | Feature cursor, overlap and replacement tests | Request-ownership pass: automated tests passed; async pending | Pending | Current threshold is three remaining rows; repeated equivalent loads must share completion |
| BEH-S07 | A successful empty response displays the empty-result message; loading a new query hides it. | `testShowNoSearchResults` | Confirmed | Passed, 67-test focused baseline | Feature empty success and ViewModel empty/loading tests | Request-ownership pass: automated tests passed; async pending | Pending | Empty success must remain distinct from failure |
| BEH-S08 | Selecting a card opens the same project/prelaunch destination with the appropriate first-card/query ref tag. | Four `testSearch…_RefTag` cases; controller route; existing framework prelaunch tests | Confirmed | Passed, 67-test focused baseline; framework snapshots not run | Keep route/ref-tag assertions | Request-ownership pass: automated tests passed; async pending | Pending | No new routing design |
| BEH-S09 | Search analytics distinguish page visits, completed queries and card clicks, without counting pagination or cancelled queries as completed searches. | `testProjectCardClicked`, `testSlowTyping`, page-view tests, `testFlow` | Confirmed | Passed, 67-test focused baseline | Preserve event values/counts through local tracking fake | Request-ownership pass: automated tests passed; async pending | Production analytics not exercised | Demo startup intentionally disables external SDKs |
| BEH-S10 | Leaving and returning to Search retains its current results rather than automatically fetching more. | `testFlow`, `testSearchPageViewed_ReturningAfterSearching` | Confirmed | Passed, 67-test focused baseline | ViewModel lifecycle and Feature ownership tests | Request-ownership pass: automated tests passed; async pending | Pending | Cancellation on disappearance must not discard completed results |
| BEH-S11 | The video-feed banner follows its feature flag and reachability, without repeated identical visibility events. | Three `testShowVideoFeedBanner…` cases | Confirmed | Passed, 67-test focused baseline | Preserve flag/reachability presentation tests | Request-ownership pass: automated tests passed; async pending | Pending | Do not replace real flags with demo assumptions |
| BEH-S12 | A failed initial request stops loading, and a later changed query can recover. | New `testFailedInitialSearchStopsLoadingAndRecoversOnChangedQuery`; existing discarded error output | Confirmed by new baseline test | Passed, 67-test focused baseline | Feature retained error/retry test and presentation contract | Request-ownership pass: automated tests passed; async pending | Pending | Silent error presentation is an existing defect candidate, not an approved final UX |

## Unresolved design and verification boundaries

- The current ViewModel discards pagination errors. Preserve the distinction
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

The table above retains the request-ownership checkpoint's historical results.
The current focused run passes 87 tests. Three direct Feature tests now protect
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
