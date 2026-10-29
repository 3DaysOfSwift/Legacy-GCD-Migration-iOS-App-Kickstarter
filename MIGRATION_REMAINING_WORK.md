# Remaining CFA migration work

Author: Matthew Thomas. Updated 29 October 2026.

The app-wide migration is **in progress**. Business-feature checkpoints are recorded
in MIGRATION_LEDGER.md; this is the remaining implementation/validation inventory,
not a percentage estimate. The earlier list of recommendations, attribution and
creator draft work is superseded by their completed checkpoints.

## Remaining implementation and audit work

1. **Remaining platform/UI inventory:** finish the non-queue callback audit and
   classify retained SDK boundaries. Project-video observers, campaign-image ownership
   and UIImageView consumer review now have verified checkpoints.
2. **Layout and compatibility helpers:** synchronous main-thread HTML helper,
   refresh/collection/table layout deferrals and the pledged-card Combine debounce.
   Preserve their required ordering; do not replace queue syntax mechanically.
3. **Compiler isolation boundaries:** resolve or explicitly classify the complete
   concurrency diagnostic baseline. Passing Swift 5 builds do not establish strict
   concurrency compliance or Swift 6 readiness.

The refreshed primitive scan finds 16 matching lines in 12 first-party files.
Some are SDK queue arguments or mock compatibility code. See
MIGRATION_PLATFORM_CALLBACK_AUDIT.md for scope, classification and limits.
Project-video and image-loading ownership are the latest checkpoint. A populated
demo launch passed; remote video and full visual/device parity remain open.

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
