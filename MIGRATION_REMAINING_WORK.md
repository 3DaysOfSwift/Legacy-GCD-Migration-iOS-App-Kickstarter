# Remaining CFA migration work

Author: Matthew Thomas. Updated 3 November 2026.

The migration remains **in progress**. This inventory supersedes earlier compiler-frontier
lists. Verified implementation checkpoints and their evidence are in MIGRATION_LEDGER.md.

## Completed implementation milestones

- Search/Explore, project/rewards/backing/checkout, comments/media, Activity/Profile,
  session/authentication/account writes, messaging, friends/following, recommendations,
  attribution and creator drafts have Feature ownership and recorded regression checkpoints.
- Concrete Feature request providers map GraphQL/REST results to checked values; task
  cancellation, replacement/session identity and late-result protection are recorded.
- Platform permission/configuration/avatar/media callbacks have explicit lifetime checkpoints.
- Formatter cache access is synchronized; explicit-value rendering remains available off
  actor. Synchronous localization reads only a synchronized language/locale projection.
- Environment-backed UI formatters, navigation, payment/capability and Discovery/framework
  helpers declare MainActor ownership.
- **Global Environment stack ownership is implemented and verified.** AppEnvironment,
  Environment construction and test fixture lifecycles now share MainActor. Persistent
  IsolatedDefaultValues settings support default arguments. 2,770 regression tests passed,
  zero failures/skips, plus normal and complete-checking app builds.

## Remaining implementation review

1. **Completed boundary follow-up:** Feature service contracts, PPO templates, Discovery/root
   notifications and the Sendable-only GraphQL bridge are verified. 135 UIKit helper
   declarations and Help/Share/onboarding owners are isolated. Missing test membership is
   corrected; the integrated run verifies that required suites actually execute. Twenty
   style aliases retain MainActor/Sendable contracts; reachability compatibility, story
   media KVO and project app-event registrations now have explicit lifetime owners.
2. **Presentation and compatibility diagnostics:** review residual UI closure/protocol diagnostics and
   generic compatibility adapters separately from generated GraphQL, third-party and generic
   compatibility APIs. A successful Swift 5 build does not establish warning-free Swift 6.
3. **Final callback inventory:** refresh the source audit after these changes, including
   callback APIs without queue syntax, and document retained SDK mechanisms/lifetimes.

The generic Service.fetch(query:)/AsyncApolloClient API remains for protocol/default/mock
compatibility; no migrated application caller was found in the audited source roots. Its raw
response transfer and cancellation limitations are documented, not certified as migrated.
Legacy paginate has no audited production caller; its delay/scheduler are now explicit and
captured. The refreshed scan finds 7 queue-name matches in 5 production-source files: native
reachability, image SDK configuration, the retained 300ms UI debounce, generic Apollo
compatibility and MockService. These are classified in external evidence
`kickstarter-final-boundary-inventory`; counts are syntax matches, not defects.

## Final validation gates

- Run relevant broader regression after remaining fixes and applicable snapshots with their
  reference device requirements. The current 2,770-test cohort is not every repository test.
- Compare representative populated screens/navigation. Public-demo launch/card/scroll smoke
  checks are recorded, but do not establish full visual parity. The pinned iPad mini iOS 18.6
  snapshot runtime has not been available; the guard remains intact.
- Validate physical-device and authenticated journeys. Live Stripe, Apple Pay/3DS, APNs,
  server-accepted pledge changes and other live mutations remain unverified. Mock success
  does not establish live integration. Do not perform real financial mutations implicitly.
- Profile representative workloads and review remaining actor/task execution boundaries.
- Finish the evidence report with supported start/finish timestamp sources, model provenance,
  test/change statistics, failures/rework and explicit limits. Exact kickoff/active effort are
  unknown; finish time remains unset until app-wide completion gates are resolved.

Existing UI, branding, storage and target identifiers remain the preservation baseline.
