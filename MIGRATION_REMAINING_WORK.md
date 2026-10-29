# Remaining CFA migration work

Author: Matthew Thomas. Updated 29 October 2026.

The app-wide migration is **in progress**. Business-feature checkpoints are recorded
in MIGRATION_LEDGER.md; this is the remaining implementation/validation inventory,
not a percentage estimate. The earlier list of recommendations, attribution and
creator draft work is superseded by their completed checkpoints.

## Remaining implementation and audit work

1. **Remaining UIKit callback contracts:** audit remaining checkout/controller
   notification callbacks, haptic helpers and UI protocol/delegate boundaries.
   Shared ValueCell/data-source ownership, discovery observations, nib entry points,
   processing/overlay protocols and the checkout release path are now checkpointed.
2. **Task-boundary values and shared state:** finish Feature result/provider graphs,
   separating immutable snapshots from actor-owned mutable objects. Account and
   checkout/backing/watch value graphs are checkpointed. Classify global style/lens
   and generated Apollo diagnostics; resolve unsafe migrated application boundaries.
   A warning-free Swift 6 language conversion is a separate scope, not an implied
   requirement to rewrite all generated/third-party compatibility machinery.
3. **Compatibility audit closure:** document retained callback paths and ownership,
   including generic Service.fetch(query:)/AsyncApolloClient. No migrated application
   consumer was found, but public/default/test consumers require a compatibility
   decision before removal. Keep necessary SDK queues and Combine scheduling.

The scoped primitive scan finds 8 matching lines in 5 first-party files. These are
SDK queue arguments/registration functions, retained Combine debounce and legacy
compatibility/mock code. Counts are syntax inventory, not remaining defect totals.
Layout/HTML ownership, refresh cancellation, report-cell reuse and checked account
value transfer are verified checkpoints. The demo's sorting and card scrolling were
observed; full visual/device parity and live operations remain open.

## Final validation gates

- Finish the request/callback inventory, including callbacks that do not contain
  queue syntax. Record each retained platform mechanism and its lifetime contract.
- Run broader regression and applicable snapshots with their reference device
  requirements. Compare representative navigation and populated screens.
- Validate physical-device and authenticated journeys. Live Stripe payments,
  Apple Pay/3DS, server-accepted pledge changes and other live mutations remain
  unverified; mock success is not production integration evidence.
- Profile realistic workloads and review remaining actor/task execution boundaries.
- Finish the evidence report with timestamp sources, model/effort provenance,
  measured statistics, failures/rework and explicit limits. Finish time remains
  unset until app-wide completion gates are resolved.

## Established checkpoints

Search/Explore, project/rewards/backing/checkout, comments and media, Activity/Profile,
session/authentication/account writes, messaging, friends/following, recommendations,
attribution, creator drafts, developer examples, redirect/avatar/permission/config
ownership and media/UI timer lifetimes have recorded checkpoints. Their tests cover
specified boundaries; they do not establish app-wide visual or live-service parity.

Existing UI, branding, storage and target identifiers remain the preservation baseline.
