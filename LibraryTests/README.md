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

MIGRATION_LEDGER.md records the baseline command and added suite selections.
The current checkpoint passed 74 tests on iPhone Air, iOS 26.2. These non-visual
suites opt out of the snapshot reference-device guard where needed; visual suites
retain it. No assertion was removed. Existing JSON fixtures are reused.

This is not a full-suite, snapshot, real-device or live-network result. The
reactive provider remains transitional: disposed-observer tests establish stale
value suppression, not underlying transport cancellation. Async cancellation,
shared pagination and the remaining filter ownership need their own tests.
