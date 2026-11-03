# Migration test checkpoints

The real Xcode target is LibraryTests in Kickstarter.xcodeproj, using scheme
Library-iOS. The package test stub is not the migration regression suite.

## Latest checkpoint — discussion reads and project media

454 combined tests passed with zero failures/skips, followed by the app build:
/private/tmp/kickstarter-discussion-media.ga9kgf. Run the sibling
Migration Evidence/kickstarter-discussion-media/verify.zsh for that selection.

DiscussionFeatureTests covers page identity/cursors, empty-page termination,
missing-envelope silence, sharing, replacement, independent routes, failed-page
retry, cancellation and account changes. ProjectMediaFeatureTests protects
independent counters, duplicate sharing, route cancellation, account changes and
silent failures. Controlled requests acknowledge admission with bounded waits;
continuations are always released. Existing comments/replies/update/video
assertions are retained in their individual ViewModel suites and await owned work.

Seven framework UpdateViewModelTests and 19 KsApi discussion/update/service tests
also passed with zero failures/skips. The separate Kickstarter-Framework-iOS scheme now points at the real package
targets rather than deleted Xcode targets. Its UpdateViewModelTests protect
update/project/comment/Safari navigation. Search/comments/replies controller snapshot
test classes are explicitly MainActor to compile against the migrated adapters;
their snapshot guards and assertions remain untouched. Compilation does
not claim their visual tests passed. See the evidence for separate framework/API
results and retained intermediate failures. Full-app migration remains ongoing.

## Previous checkpoint — shipping and creator interactions

377 combined tests passed with zero failures/skips, followed by an app build
in /private/tmp/kickstarter-shipping-interactions.82bZbI.
Five KsApi LocationTests/Location_LocationFragmentTests passed separately in
/private/tmp/kickstarter-shipping-locations-api.xcresult.
Run the sibling Migration Evidence/kickstarter-shipping-interactions/verify.zsh
for the complete selection on iPhone Air, iOS 26.2.

RewardsFeatureTests now cover destination priority, no-network digital rewards,
empty success, failure/retry, selection, duplicate reads, late replacement,
independent routes, cancellation and account changes. ProjectDetailsFeatureTests
cover creator request preparation and current-session messaging authorization.
Existing shipping/creator/navigation assertions remain in their one-ViewModel
test files. Updates and pledge-web logic suites are included to protect the
shared WebKit event-data boundary; only these nonvisual suites opt out of the
snapshot reference-device guard. Visual suites retain that guard.

Initial baseline and expanded-run WebKit fixture crashes, plus a corrected
server-country fixture, are recorded in the evidence case. No assertions were
removed or skipped to obtain the passing run. This is not full-suite coverage,
live transactions, strict concurrency, snapshot equivalence or device sign-off.

## Previous rewards checkpoint — 27 October 2026

324 combined Search, Explore, project-detail, Rewards and composition tests pass;
six existing NoRewardInserterTests and two KsApi sorted-reward decoder tests also
pass. See MIGRATION_LEDGER.md for exact result bundles and the sibling migration
evidence verification script. These counts are not full-app coverage.

FeatureTests/Rewards/RewardsFeatureTests.swift covers ordering, visibility,
shipping insertion policy, request sharing/replacement, failure/retry, cancellation,
independent routes and account changes. ProjectDetailsFeatureTests adds related
request ownership tests. Existing per-view-model tests retain their presentation
assertions and await owned tasks. New test membership is in LibraryTests in the
Xcode project; production Library/KsApi sources use package file discovery.
RewardsCollectionViewModelTests, SimilarProjectsUseCaseTests and
NoRewardInserterTests are nonvisual and individually opt out of the snapshot-only
reference-device restriction. Visual suites retain that restriction.

## Initial Search checkpoint (historical)

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
That initial targeted selection passed 93 tests on iPhone Air, iOS 26.2. These
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
the public demo route. Later lookup, selection and presentation checkpoints are
recorded in MIGRATION_LEDGER.md; do not treat this historical note as current work.
