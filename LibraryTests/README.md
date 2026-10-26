# Migration test checkpoints

The real Xcode target is LibraryTests in Kickstarter.xcodeproj, using scheme
Library-iOS. The package test stub is not the migration regression suite.

Search checkpoint suites:

- SearchViewModelTests: existing presentation, navigation, analytics and lifecycle.
- SearchFiltersUseCaseTests: legacy filter selection/reset contract.
- PaginateTests: legacy paging and query-replacement ordering.
- SearchFeatureTests: provider-controlled request, stale completion, paging,
  error/recovery and no-fetch-on-construction scenarios.
- AppModelTests: isolated composition; no live singleton in tests.
- SearchRequestCancellationTests: async adapter, transport cancellation races,
  exactly-once callback completion, error mapping and replacement suppression.

MIGRATION_LEDGER.md records the baseline command and added suite selections.
The current checkpoint passed 87 tests on iPhone Air, iOS 26.2. These non-visual
suites opt out of the snapshot reference-device guard where needed; visual suites
retain it. No assertion was removed. Existing JSON fixtures are reused.

This is not a full-suite, snapshot, real-device or live-network result. The
baseline suites retain the legacy provider and deterministic scheduler. They do
not by themselves prove the live async route preserves every screen timing case.
The ten new cancellation tests exercise the async provider/Feature adapter and
controlled Apollo-shaped tokens/callbacks, including obsolete request cancellation
and late delivery. Simulator smoke covers the live demo route. Real-network
cancellation and complete async ViewModel/analytics coverage remain unverified.
Shared equivalent pagination and directly awaitable Feature commands are pending.
