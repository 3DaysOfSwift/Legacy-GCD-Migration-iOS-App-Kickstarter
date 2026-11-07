<a href="https://www.kickstarter.com"><img src=".github/ksr-wordmark.svg" width="36%" alt="Kickstarter for iOS"></a>

<p>
  <a href="https://www.3daysofswiftconcurrency.com/"><img src=".github/migration-branding/3days-of-swift-concurrency.png" width="140" alt="3 Days of Swift Concurrency"></a>
  <a href="https://github.com/3DaysOfSwift/CFA-AI-Toolkit-for-iOS"><img src=".github/migration-branding/cfa-ai-toolkit.png" width="140" alt="CFA AI Toolkit for iOS"></a>
</p>

# Kickstarter: Legacy GCD to Swift Concurrency using AI

[Browse the migrated branch](https://github.com/3DaysOfSwift/Legacy-GCD-Migration-iOS-App-Kickstarter/tree/migration/cfa-swift-concurrency) · [Browse the original baseline](https://github.com/3DaysOfSwift/Legacy-GCD-Migration-iOS-App-Kickstarter/tree/main) · [Read the migration ledger](https://github.com/3DaysOfSwift/Legacy-GCD-Migration-iOS-App-Kickstarter/blob/migration/cfa-swift-concurrency/MIGRATION_LEDGER.md)

This repository is an independent, AI-assisted migration of [Kickstarter's open-source iOS app](https://github.com/kickstarter/ios-oss). It is an educational case study by 3 Days of Swift Concurrency, not an official Kickstarter release. The original app and its authors retain their copyright and [Apache 2.0 licence](LICENSE).

The **`migration/cfa-swift-concurrency` branch contains the migrated app**. This branch is the place to inspect, build and run the result. The repository's `main` branch preserves the upstream starting point, with an overview of the two versions.

## Migration report

| Phase | Work and status |
| --- | --- |
| 1. Autonomous migration | AI-assisted migration to CFA and Swift Concurrency, with human direction and verification; implementation handover recorded. |
| 2. Structure and cleanup | Core app code moved into the CFA folders; redundant migrated files and application-library packaging removed. |
| 3. ReactiveSwift removal | Reactive workflows and state replaced with async operations, Observation and direct presentation callbacks; ReactiveSwift and ReactiveExtensions removed from app and test targets. |
| 4. Manual testing and refinement | Simulator build, regression tests and representative demo browsing checked; further validation remains open. |

| Recorded milestone | Bangkok time | Elapsed from first record |
| --- | --- | --- |
| Earliest recorded preparation | 26 Oct 2026, 14:18 | Starting point |
| CFA implementation handover | 3 Nov 2026, 21:44 | About 8 days 7 hours 26 minutes |
| ReactiveSwift removal checkpoint | 7 Nov 2026, 03:27 | About 11 days 13 hours 9 minutes |

These are **elapsed calendar times**, including interruptions, human input and review—not continuous AI work. Phases overlapped; exact start and finish times for each phase were not recorded. Screenshots identify GPT-6 Astra High for portions of the work, but not every model used.

**Verification:** 2,929 selected tests passed at handover; later separate, overlapping runs passed 1,944 non-snapshot model tests, 183 non-snapshot presentation tests and 39 signed keychain tests. Reference snapshot comparisons, physical-device review and live account/payment operations remain unverified. See the [migration ledger](MIGRATION_LEDGER.md) for evidence and limitations.

## Clone the migration branch

```sh
git clone --branch migration/cfa-swift-concurrency --single-branch https://github.com/3DaysOfSwift/Legacy-GCD-Migration-iOS-App-Kickstarter.git
cd Legacy-GCD-Migration-iOS-App-Kickstarter
```

## Run the fictional-data demo

The migrated app includes a **Debug-only demo** with fictional projects. It lets you explore discovery, search and project details without Kickstarter API keys for those flows.

1. **Create your local configuration file** by copying the example from the repository root:

   ```sh
   cp 'Kickstarter-iOS/3 - App Resources/Configuration/Secrets.swift.example' KsApi/Sources/KsApi/Secrets.swift
   ```

   The copy is ignored by Git. Do not commit real credentials. If `Secrets.swift` already exists at the destination, this command overwrites it.

2. **Enable the fictional-data demo.** Open the copied `KsApi/Sources/KsApi/Secrets.swift` and change:

   ```swift
   public static let isOSS = true
   ```

   `OSS` means **open-source software**. In this project, `isOSS` is the flag used to select the public demo configuration. Setting it to `true` enables the fictional-data demo in Debug builds, so supported browsing flows use demo content instead of requiring private Kickstarter API credentials. The example defaults to `false`, so this change is necessary to enable the demo.

3. **Open `Kickstarter.xcodeproj`** and let Xcode resolve the Swift package dependencies.

4. **Choose the Kickstarter iOS scheme**, select an iOS simulator and run the Debug build.

The migration was verified with Xcode 26.2 and an iPhone Air simulator running iOS 26.2.

See the [public-demo guide](docs/PUBLIC-DEMO.md) for supported flows and limitations. Login, real payments and other live operations are not complete offline demo workflows. Xcode must still download the project's Swift packages, and the app is not fully offline.

## Before and after

The upstream baseline uses a UIKit application with application code spread across local Swift packages, including `Library` and `Kickstarter-Framework`. Its view models use ReactiveSwift signals and producers to connect inputs, outputs and asynchronous work.

The migrated branch keeps the existing UIKit screens and moves core app code into the application target using **Cooperative Feature Architecture (CFA)**. An AppModel composes features that own application state and workflows; view models and controllers handle presentation and invoke feature operations. Swift Concurrency provides the primary async task and cancellation model, and Observation is used for migrated observable state. Some Combine, platform callbacks and third-party SDKs remain where applicable.

```text
Kickstarter-iOS/
  1 - View/              Screens, controllers, view models and shared UI
  2 - AppModel/          Composition, features, storage and service adapters
  3 - App Resources/     Configuration, localization and app resources
  4 - Swift Extensions/  Shared extensions
ApplicationTests/        App-hosted tests and support
```

The app no longer links ReactiveSwift or ReactiveExtensions. Local packages including `KsApi`, `GraphAPI`, `Experimentation`, `KDS` and `ServerDrivenUI` remain for services, generated APIs, design and reusable rendering. See the [implementation handover](MIGRATION_COMPLETION_REPORT.md) for the structural migration and the newer [ledger](MIGRATION_LEDGER.md) for subsequent changes, including ReactiveSwift removal.

## What the migration achieved

The work moved core app code out of the two application libraries and into the CFA folder structure, migrated feature workflows towards owned async tasks, and removed ReactiveSwift from app and test targets. A fictional-data demo supports discovery, search and project browsing without private API credentials.

The migration was AI-assisted and substantially autonomous, with human direction, review, testing and follow-up corrections. Exact per-commit model and cost information was not recorded.

## Verification and limits

At the 3 November handover, selected existing cohorts reported **2,929 passing tests**. Following ReactiveSwift removal, separate runs on iPhone Air / iOS 26.2 passed **1,944 non-snapshot model tests**, **183 non-snapshot presentation tests**, and **39 signed keychain tests**. These are separate checkpoints and overlapping cohorts, not additive totals. The simulator build succeeded, and a limited public-demo smoke check covered discovery sorting, opening a project and searching.

The original snapshot references require an iPad mini (A17 Pro) with iOS 18.6; those comparisons were not rerun because that runtime was unavailable. Physical-device review, full visual/accessibility validation and live account/payment operations remain unverified. This case study is not a production certification, a claim of race freedom, or a warning-free Swift 6 build. See [remaining work](MIGRATION_REMAINING_WORK.md) and the [ledger](MIGRATION_LEDGER.md) for details and dated evidence.

## Credits and licence

The starting application, its assets and original documentation are from [kickstarter/ios-oss](https://github.com/kickstarter/ios-oss). Third-party notices are in [NOTICE.md](NOTICE.md). The project is available under the [Apache License 2.0](LICENSE).
