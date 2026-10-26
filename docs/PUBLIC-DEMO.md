# Public fictional-data demo

This migration branch adds an opt-in **Debug-only browsing demo**. It does not
require Kickstarter API credentials and does not change the production service.
`MockService()` retains its original behavior for the upstream tests;
`MockService.publicDemo()` selects the new catalogue.

## Enable it

Use the public `Configs/Secrets.swift.example` as
`KsApi/Sources/KsApi/Secrets.swift`, then set `isOSS = true` in that local copy.
The file is intentionally ignored by Git; do not commit real credentials.
Select **Kickstarter iOS**, Debug, and an iOS simulator in Xcode. Do not run
the private-secrets bootstrap just to enable this demo.

## Data and supported journeys

- 24 fictional projects, marked `[Demo]`, with stable project and creator IDs.
- Discovery and GraphQL search share one immutable catalogue.
- Case-insensitive search, category/location/state/funding filters, sorting,
  and six-item pages with deterministic end-of-list behavior.
- Project details, a short fictional story, FAQ, and illustrative rewards.
- Empty search results and an explicit failure: search for `demo:error`, then
  change the query to recover.
- ReactiveSwift, async GraphQL, and Combine discovery entry points.

Dates are relative to the catalogue's creation date: live projects have 2–25
days remaining, successful projects ended three days earlier, and illustrative
reward delivery is 90 days later. The catalogue captures that date once so it
does not change halfway through pagination. Tests inject a fixed reference date.
This remains fictional data, not a live campaign calendar.

Project and avatar illustrations are generated locally from simple geometric
artwork, labelled as demo content. A Debug-only `DemoImageURLProtocol` serves
PNG responses for the reserved `https://images.demo.invalid` host through the
existing image loaders, configured explicitly in both AlamofireImage and
Kingfisher sessions. It never downloads these images or intercepts production
hosts. App Transport Security remains unchanged. Fictional project web URLs use
`example.invalid` so they cannot open a real campaign accidentally.

## Deliberate limits

This is not a complete local Kickstarter backend. Login is explicitly rejected;
saved/followed/recommended filters have no personalised results in the signed-out
demo. Payments, backing, account changes, comments, real videos and unsupported
GraphQL operations are not validated demo workflows. Do not enter real account
or payment information. Other upstream mocks are unchanged.

Some upstream fixture flags remain: project detail can show a restricted-creator
banner, and Ending Soon currently sorts successful fixtures alongside live ones.
These are demo limitations, not production API behaviour claims.

In Debug with `isOSS=true`, launch skips Facebook SDK configuration, Segment/
Braze and Statsig initialization, Firebase consent updates and explicit iCloud
defaults synchronization. Statsig uses the existing local overrides/default-off
behaviour. Demo substitutes decline push registration and report tracking as
restricted without requesting system permissions. Non-demo builds retain the
original integration paths. These changes do not remove SDK dependencies.

This is not a network firewall. Unsupported account flows, external links,
embedded web views and developer environment switches are not offline demo
workflows. No full-app offline or production-backend compatibility claim is made.

## Validation

`KsApiTests/DemoCatalogTests` covers deterministic content, fragments and date
scalars, filtering, pagination, project lookup, error recovery, rejected login,
async/reactive consistency, relative dates, decodable local project/avatar images,
non-interception of production image URLs and preservation of the original test mocks.
Existing caller-owned schedulers/cancellation remain in place; the catalogue
creates no tasks, queues or sleeps. Tests needing delayed delivery should use
the app's existing injected scheduler/API delay facilities.
