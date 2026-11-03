# Complete the CFA application structure

Author: Matthew Thomas. 3 November 2026.
Status: complete for CFA implementation handover. 765 app Swift files compile directly in the app; 2,929 existing tests passed. See MIGRATION_COMPLETION_REPORT.md for remaining validation limits.

## Binding destination

Core application code compiles directly in the Kickstarter iOS application target.
Do not create another app library, an umbrella package, or navigator-only aliases to
simulate this result. Existing verified CFA ownership and concurrency work is retained.
The application uses packages for services, generated APIs and genuinely reusable
non-core components. Packages must not own the app composition root, app Features,
screen ViewModels, navigation or app-specific screens and business workflows.

This plan takes priority over the earlier assumption that existing module boundaries
would remain the final application structure. Completion requires this structural work
as well as behavior and concurrency verification. No UIKit-to-SwiftUI rewrite is implied.

## Destination on disk and in Xcode

```text
Kickstarter-iOS/
  1 - View/
    AppDelegate.swift                  # existing UIKit lifecycle retained
    Views/
      Search/                          # screen/controller + adjacent ViewModel
      Discovery/
      ...                              # actual existing screens, not empty placeholders
    Shared Views/                      # app-owned cells, styles, UI helpers
  2 - AppModel/
    AppModel.swift
    Features/
      Search/                          # Feature, API, owned domain types and workers
      ...
    User Data Storage/                 # app repositories and external-service adapters
  3 - App Resources/                   # storyboards, nibs, localization, privacy/config
  4 - Swift Extensions/               # genuinely shared app extensions only
  Assets.xcassets
Application tests/
  View model tests/
  AppModel tests/
  FeatureTests/
  Repository tests/
  UI and snapshot tests/
Packages/                              # logical navigator grouping; move paths only if useful
  services, generated APIs, reusable non-core components
```

Keep existing target/bundle identifiers, configuration semantics and entitlements.
Keep extensions as separate targets; share only the minimum extension-safe service code.
Do not create SwiftUI App.swift beside the existing UIKit entry point. Place feature-local
helpers with their owner, not in a new generic dumping ground. Tests may keep existing
target names when renaming adds no value; their source layout and imports must match
application ownership.

## Package disposition

| Current location | Destination / rule |
| --- | --- |
| Library/2 - AppModel | Application 2 - AppModel; all composition and app Features move |
| Library screen ViewModels, styles, app models and helpers | Application presentation or owning Feature |
| Kickstarter-Framework app screens/controllers/cells/navigation | Application 1 - View, grouped by screen with ViewModels |
| Library and framework app resources | Application resources, with explicit bundle lookup conversion |
| LibraryTestHelpers and app-focused package tests | App test targets/support; no service package depending on the executable |
| KsApi | Retain transport/service contracts and DTOs; move any app policy/composition to the app |
| GraphAPI | Retain generated GraphQL schema/operations and supporting API implementation |
| Experimentation | Retain reusable flag service/SDK integration; app decisions stay in Features |
| KDS / ServerDrivenUI | Retain only reusable rendering/design infrastructure; audit and move app-specific workflows/screens |
| Third-party packages | Retain required dependencies; remove only proven unused dependencies |

Do not merely rename Library to Services. Once emptied of app code, remove Library and
Kickstarter-Framework products/manifests and references if no justified independent
service responsibility remains. Any retained local package gets a documented purpose
and an audit demonstrating it contains no core application ownership.

## Execution order and checkpoints

### 1. Produce the exact move and dependency manifest

Inventory tracked source/resources/tests in both app-bearing packages and current app
target. Map every file to an owning layer, destination and compile/resource target.
Identify duplicate names/symbols, access-level changes, package imports, Bundle.module,
Bundle(for:), resource helpers, Objective-C runtime names, storyboard/xib customModule,
localization, asset lookup, generated files and build scripts. Inventory extension and
test consumers. Capture the baseline build and actual discovered test identifiers.
Deliver a complete map with zero unclassified core files, plus the dependency order.

### 2. Consolidate module ownership and app target wiring

Prepare the numbered app hierarchy and transfer core source membership from the local
packages to the application target. Library owns dependencies of the framework, so do
not move AppModel alone and introduce an impossible package-to-executable dependency.
Move mutually dependent core code as a coherent module cutover, using the file map to
organise it directly by final owner. Maintain one compiled definition of each type.
Wire direct package products used by the application; replace internal Library and
Kickstarter_Framework imports and migrate app-focused test imports/hosting together.
Retain a temporary compatibility bridge only when necessary, with an explicit removal
item; it cannot be part of the finished architecture.
Deliver an app build and runnable test targets with core code compiled in the app.

### 3. Complete resource and runtime integration

Transfer resources alongside their consuming code during cutover; this phase verifies
all runtime paths. Update Bundle.module and old framework-bundle lookups explicitly.
Update storyboard/nib module references and runtime class names. Preserve localized
strings, fonts, image names, asset generation, storyboard identifiers, privacy files,
configuration paths and resource processing behavior. Avoid flattening colliding
resource namespaces. Verify launch, nib-backed screens, localization and image loading.
Deliver a working public-demo app with representative screens rendering correctly.

### 4. Finish CFA ownership and remove the old app modules

Audit each screen and Feature against the CFA rules, not just its folder name. Check
adjacent screen ViewModels, narrow Feature dependencies, authoritative shared state,
AppModel.live composition, repository boundaries, directly awaitable commands and
explicit task lifetimes. Preserve required UIKit lifecycle bridges and document them.
Move remaining app policy out of service packages. Remove empty old package products,
stale imports/project references and obsolete compatibility adapters. Do not remove
still-required services or generated API types to meet a file-count target.
Deliver zero core app source files compiled through Library/Kickstarter-Framework or
any replacement package, and no unresolved temporary consolidation bridges.

### 5. Verify the consolidated app and close the report

Build all supported app configurations and affected extension targets; verify Debug-only
demo behavior. Run migrated app/Feature/ViewModel/repository tests and retained service
tests, comparing discovered suite/test identifiers with baseline so no tests disappear.
Run complete concurrency diagnostics and classify first-party, SDK/generated and retained
compatibility findings; do not claim Swift 6 compliance from a Swift 5 build.
Refresh callback/task inventory. Compare representative populated navigation, search,
filters, project/reward/backing, account and messaging screens. Run pinned snapshots
when their runtime is available; record unavailable gates honestly. Reinstall the latest
build for device smoke/profiling and investigate the recorded main-thread microhang.
Keep live-payment and authenticated-service validation separate; no real mutations
without explicit authorization. Publish no unconditional completion claim while required
gates remain unresolved.

## Remove superseded implementations — mandatory

The finished checkout presents the CFA implementation, not parallel old and new apps.
Use tracked moves where practical; do not leave source copies at their former locations.
After replacement behavior is verified, delete superseded legacy implementations,
unused migration adapters, obsolete tests that target removed APIs, and abandoned
resources/scripts. Preserve meaningful behavior assertions by moving or adapting tests
before removing their obsolete counterparts. Git history preserves the original app;
do not keep Legacy, Old, Backup or archived source folders in the active checkout.

For each deletion, check source callers, target membership, package consumers, extension
consumers, storyboard/nib runtime references and resource/build-script lookups. Remove
stale project references, imports, package products and build-phase entries in the same
checkpoint. Verify that no source is compiled twice and no replacement has left an
unreferenced old implementation behind. Search by responsibility and call sites as well
as filenames: differently named types can still duplicate ownership.

Do not delete required SDK callback bridges, generated API code, services or reusable
components merely because they predate the migration. Retained code must have a current
purpose and comply with its documented boundary. Remove compatibility code when its
last consumer is gone; document any remaining necessity explicitly. Never delete user
work, credentials or unrelated files as part of migration cleanup.

Completion requires one authoritative implementation per migrated responsibility, no
superseded legacy application paths, no temporary migration bridges, no duplicate source
copies, no broken resource references and no abandoned app-library products. Record
removed/replaced files and retained exceptions in the final inventory, then build and
run relevant tests after cleanup. The original implementation remains available in Git.

## Progress reporting and completion criteria

Report: core files mapped/moved/remaining, app-bearing packages remaining, screens with
adjacent ViewModels, unresolved ownership violations, test discovery differences and
validation gates. Counts measure structural progress, not correctness by themselves.
Commit verified coherent checkpoints; never push automatically. Keep detailed case-study
evidence outside the repository. Structural moves must preserve the previous migration
work rather than rewrite working Features unnecessarily.

The final report records the original migration start evidence, structural-plan correction,
finish timestamp only when justified, observed model provenance, changed-file and test
statistics, rework and unverified limits. Historical elapsed time must not be presented
as continuous model execution time. This plan makes no unsupported duration promise.
