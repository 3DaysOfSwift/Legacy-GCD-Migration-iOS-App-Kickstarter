# Remaining CFA migration work

Author: Matthew Thomas. Updated 3 November 2026.

The app-wide migration is **in progress**. Business-feature checkpoints are recorded
in MIGRATION_LEDGER.md; this is the remaining implementation/validation inventory,
not a percentage estimate. The earlier list of recommendations, attribution and
creator draft work is superseded by their completed checkpoints.

## Remaining implementation and audit work

1. **Remaining UIKit/shared-environment review:** app-owned controller/cell delegates,
   shimmer and feedback contracts now declare MainActor across the audited cohort.
   UIApplicationType, UIScreenType and the ChangeEmail integration contracts are now
   isolated and verified. UIDeviceType and KSRAnalytics now also declare MainActor;
   analytics identity/configuration/consent updates are explicit actor-owned methods.
   AppEnvironment stack ownership remains: formatter/environment dependency changes
   are still required, not a blanket annotation.
   Synchronous string rendering now reads a synchronized language-only projection;
   nested environment overrides and background localization are verified.
   Login/Settings style declarations now specify MainActor; three autofill compositions
   and their controller callers use direct calls to preserve actor ownership. Other
   global UI style helpers and shared Environment access still need classification.
   Date/number formatter cache operations now use scoped Mutex ownership; attributed
   currency styling is request-local. Value-only date/currency rendering entry points
   and explicit analytics clock/calendar capture reduce implicit dependency access.
   Number/percentage/currency and date parsing/style rendering also expose value inputs;
   Duration/relative-time rendering now accepts captured clock/calendar values, and
   project-card deadline callers use those inputs. Existing convenience wrappers
   still require Environment ownership migration. Login
   disclaimer URL resolution now occurs in a MainActor UI helper.
   Notification-center async delegates transfer checked push values before awaiting UI;
   AppDelegate session/dialog observers now have retained lifecycle owners.
   Older PassKit, five mail-composer conformances and the payment-plan delegate now
   declare their main-actor contracts; 26 payment lifetime tests and the complete-checking
   app build passed.
   PaymentSheet creation/selection/confirmation and optional card-ID lookup now have
   owned lifetimes. Older Apple Pay token observation now guarantees a PassKit reply
   on cancellation/release and rejects obsolete sessions. Native delegate selector
   wiring is tested. Four STPPaymentHandler confirmation paths and post-campaign
   Apple Pay lifetimes are also checkpointed; live integration remains unverified.
2. **Task-boundary values and shared state:** concrete migrated Feature providers now
   have recorded response/value checkpoints. Finish the shared-environment diagnostic
   review; retain explicit separation from generic compatibility APIs below. Account and
   checkout/backing/watch value graphs and payment command results are checkpointed.
   All five payment service operations now map Apollo data before callback-to-task
   transfer. The generic compatibility API remains; it is not the concrete Feature transport path.
   Six pledge mutation envelope/acknowledgement paths now map before transfer.
   Checkout validation/completion, payment-plan and managed backing/rewards now also
   map before transfer. Backing/reward/installment value graphs have checked Sendable
   conformances; payment plans carry eligibility/installments and completion carries Void.
   Pledged-project overview, including image/analytics and initial navigation values,
   now maps before transfer. Shared project cards also retain concrete snapshots.
   Project detail/base/extras/backing/rewards/add-ons/locations/related queries now map
   before transfer, including story/media/analytics/navigation values. Account setup,
   Apple login, session user, activity count and acknowledgement/reporting/block paths
   now map before transfer too.
   Profile/video/discussion/example/category providers, report options and Search results/lookups
   now also map before transfer. Search retains ID-based equality and event ordering; video
   formatting stays in the UI adapter. The raw cancellableQuery overload is removed.
   The shared native REST wrapper and nine additional UI delegate contracts are now isolated;
   messaging/configuration/draft/deep-link task results have checked value graphs. Activity,
   Profile and root session observers retain synchronous main-actor delivery.
   RichPushNotifications now has an owned native async download with exactly-once expiry/success
   delivery, verified locally; live APNs/system expiry remains unverified. Next: remaining UIKit
   SDK delegate/global style contracts, compatibility classification and final validation.
   A warning-free Swift 6 language conversion is a separate scope, not an implied
   requirement to rewrite all generated/third-party compatibility machinery.
3. **Compatibility classification recorded:** retain generic Service.fetch(query:)/
   AsyncApolloClient for the existing protocol/default/mock/test API surface. No migrated
   application caller was found in the audited source roots. Its raw response transfer
   and discarded cancellation handles remain a documented legacy limitation; retaining
   it does not certify it as migrated. Necessary SDK queues and Combine scheduling remain.

The scoped primitive scan finds 8 matching lines in 5 first-party files. These are
SDK queue arguments/registration functions, retained Combine debounce and legacy
compatibility/mock code. Counts are syntax inventory, not remaining defect totals.
Layout/HTML ownership, refresh cancellation, report-cell reuse and checked account
value transfer are verified checkpoints. The demo's sorting and card scrolling were
observed; full visual/device parity and live operations remain open.

## Stack isolation compiler frontier — 3 November 2026

The experimental AppEnvironment/Environment actor annotations were reverted, not shipped.
The compiler exposed these concrete next dependencies (not an exhaustive app inventory):

- FetchCategoriesUseCase is now an actor-owned async request with shared pending work,
  cancellation on release and captured cache identity. Its Discovery caller and tests
  await completion; the reactive network/cache callback path is removed.
- SearchFilters, VideoFeedItem presentation construction, and Activity status/friend
  presentation helpers now declare MainActor ownership and have passing focused tests.
- Navigation route callbacks capture API/web URLs; the compatibility entry points and
  dependent web/deep-link callers now declare MainActor, with 179 passing focused tests.
- Platform payment/notification helpers, localized postal-code lookup and project URLs
  now declare MainActor ownership. Lottie localization uses the language-only projection.
- Remaining concrete compiler dependencies include SharedFunctions convenience defaults,
  legacy Paginate scheduler/delay capture, and keychain/configuration reads used by
  synchronous Environment persistence. Test fixture stack push/pop ownership also needs
  alignment with the final stack contract.

Reward-card presentation, creator/shipping/clock helpers and response-side creator identity
are now isolated/captured and verified. Country/currency helpers expose checked value inputs.
Card-expiry rendering, its two cell ViewModels, HelpType URL lookup and feature/experiment
Environment readers are isolated and tested. Re-run the stack experiment after these
items; later compiler batches may expose additional callers. Do not treat a passing Swift 5
build as evidence that the stack is isolated.

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
