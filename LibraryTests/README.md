# Migration test checkpoints

The real Xcode target is LibraryTests in Kickstarter.xcodeproj, using scheme
Library-iOS. The package test stub is not the migration regression suite.

Search checkpoint suites:

- SearchViewModelTests: original presentation, navigation, analytics and lifecycle
  assertions through the async provider/native Feature; controlled result-delay
  clock, with the legacy scheduler only for filter lookup fixtures.
- SearchFiltersUseCaseTests: existing filter selection/reset presentation contract.
- PaginateTests: legacy paging regression for other consumers. Search no longer
  uses this implementation; these tests alone cannot validate native paging.
- SearchFeatureTests: controlled async requests, shared await completion, adverse
  query/page ordering, explicit cancellation, stale completion, no-cursor behaviour,
  error/retry and no-fetch-on-construction scenarios.
- AppModelTests: isolated composition; no live singleton in tests.
- SearchRequestCancellationTests: async provider, transport cancellation races,
  exactly-once callback completion, error mapping and replacement suppression.

MIGRATION_LEDGER.md records commands, failed attempts and passing checkpoints.
The current targeted selection passes 93 tests on iPhone Air, iOS 26.2. These
non-visual suites opt out of the snapshot reference-device guard where needed;
visual suites retain it. No original behavioural assertion was removed. Existing
JSON fixtures are reused with throwing unwraps in the touched Search suites.

Test gates acknowledge request/delay arrival with bounded XCTest expectations.
Cleanup cancels owned work and releases pending continuations. The native clock
advances explicitly; no polling/yield guesses or real-time sleeps. Runs 5 onward
also enable Xcode test timeouts with a 60-second default execution allowance.
Three legacy flow fixtures were moved before request admission: they previously
relied on deferred scheduler execution to swap the environment after submitting.

This is not a full-suite, snapshot, real-device, live-network, performance or
complete Swift 6 result. Controlled transport tests prove cancellation forwarding
and obsolete-delivery rejection, not real-network timing. Simulator smoke covers
the public demo route. Category/location lookup execution and remaining reactive
selection/presentation adapters still require migration and their own tests.
