# Remaining CFA migration work

Author: Matthew Thomas. Updated 29 October 2026.

The app-wide migration is **in progress**. Business-feature checkpoints are recorded
in MIGRATION_LEDGER.md; this is the remaining implementation/validation inventory,
not a percentage estimate. The earlier list of recommendations, attribution and
creator draft work is superseded by their completed checkpoints.

## Remaining implementation and audit work

1. **Compiler isolation at UIKit boundaries:** ValueCell/delegate contracts,
   legacy awakeFromNib hooks, notification delivery and nonisolated release.
2. **Remaining value-transfer and shared-state diagnostics:** Feature task results,
   transport providers, global style/lens values and generated Apollo metadata.
   Complete checking builds in Swift 5 mode; warnings still prevent a Swift 6 claim.
3. **Compatibility callback inventory:** finish the non-queue callback audit and
   decide the unused generic Apollo bridge's disposition after checking consumers.
   Keep necessary platform queues and documented Combine operator scheduling.

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
