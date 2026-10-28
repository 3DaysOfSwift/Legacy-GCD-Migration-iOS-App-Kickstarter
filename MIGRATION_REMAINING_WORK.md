# Remaining CFA migration work

Author: Matthew Thomas. Source audit: 28 October 2026.

The app-wide migration is **in progress**. The ledger records verified checkpoints;
this inventory records remaining implementation and validation, not a percentage
estimate. These groups differ substantially in size and risk.

## Implementation groups

| Group | Remaining application paths | Exit condition |
| --- | --- | --- |
| 1. Pledge and backing management | Pledge writes and ManagePledge reads verified; remaining PPO pledged-project pagination/address/receipt writes, PledgeManagerWeb project/update loading | Shared ownership, ordered mutations, session guards and existing screen regressions verified |
| 2. Checkout and payment plans | PostCampaignCheckout create/validate/complete verified; remaining PledgeOverTime payment-plan loading | Awaitable commands preserve checkout sequence, payment errors and duplicate-submission policy |
| 3. Reward add-ons | RewardAddOnSelection loading; RewardsUseCase secret reward-group write | Feature-owned requests with cancellation/order tests and unchanged selection behavior |
| 4. Friends and following | FindFriends lists/stats/pagination/follow-all; two follow-cell adapters | Shared follow state and ordered writes; obsolete-account results rejected |
| 5. Residual project, creator and account actions | WatchProject save/unsave; CuratedProjects and Thanks recommendations; project attribution; UpdateDraft editing/images; ReportProjectInfo options; SettingsAccount user read | Each remaining production request has an explicit owner and documented lifetime |

The named paths are source-audit findings, not evidence that every call in those
files is legacy. For example, PledgeManagerWeb currently mixes migrated interactions
with remaining project/update reads. Configuration access such as serverConfig is
not itself an asynchronous ownership gap. Developer-only examples will be listed
separately in the final audit, not counted as migrated product journeys.

## Final validation gates

- Refresh the application-wide request/GCD/OperationQueue/callback inventory.
  Classify retained UIKit/SDK delivery boundaries and remove obsolete owners.
- Check concurrency diagnostics and actor/task lifetimes across the app. Current
  passing Swift 5 builds do not establish full strict-concurrency compliance.
- Run broader regression and applicable snapshot suites with their reference
  device requirements. Compare representative navigation and populated screens.
- Validate authenticated and physical-device journeys. Live Stripe payments,
  Apple Pay/3DS, server-accepted pledge changes and other live mutations remain
  unverified; mock success is not proof of production integration.
- Complete the evidence report with start/finish timestamps and their sources,
  model/effort provenance, measured statistics, unsuccessful attempts and limits.
  Finish remains unset until app-wide completion gates are resolved.

## What the existing checkpoints establish

Search/Explore, project details/rewards loading, comments and media, Activity/Profile,
session/authentication/account work, messaging, and payment-method/intent paths have
verified migrated checkpoints. They do not imply every related screen is finished:
the residual paths above still need work. See MIGRATION_LEDGER.md for exact scopes.

Existing UI, branding, storage and target identifiers remain the preservation baseline.
